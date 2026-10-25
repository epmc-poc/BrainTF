import re
from collections.abc import Iterable
from copy import copy
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup, Tag

from config import config
from utilities.logger import logger

TRIVY_GUIDE_HOST = 'avd.aquasec.com'
TRIVY_GUIDE_URL_PATTERN = re.compile(
    r"(?m)^\s*See\s+(https://avd\.aquasec\.com/\S*)"
)
TFSEC_GUIDE_URL_PATTERN = re.compile(
    r"https://aquasecurity\.github\.io/tfsec/[^\s<>)\]]+"
)
HTML_PARSER = 'html.parser'
HEADING_TAGS = ['h2', 'h3']
TEXT_TAGS = ['p', 'h4', 'li']
PAGE_CHROME_TAGS = ['footer', 'nav', 'aside']
TERRAFORM_CODE_PATTERN = re.compile(
    r'(?m)^\s*(?:'
    r'(?:resource|data|module|provider|variable|output|check)\s+"'
    r'|(?:locals|terraform|moved|import|check)\s*\{'
    r')'
)


def is_trivy_guide_url(url: str) -> bool:
    """Return True only for https URLs on the Trivy guide host (no userinfo or custom port)."""
    try:
        parsed = urlparse(url)
        return (
            parsed.scheme == 'https'
            and parsed.hostname == TRIVY_GUIDE_HOST
            and parsed.port is None
            and parsed.username is None
        )
    except ValueError:
        return False


def extract_trivy_guide_urls(errors: str) -> list[str]:
    """Return unique Trivy guide URLs in the order they occur in the output."""
    urls: list[str] = []
    seen: set[str] = set()

    for match in TRIVY_GUIDE_URL_PATTERN.finditer(errors):
        url = match.group(1).rstrip('.,);]')
        if url not in seen:
            seen.add(url)
            urls.append(url)

    return urls


def extract_tfsec_guide_urls(errors: str) -> list[str]:
    """Return unique AquaSecurity TFSec guide URLs in occurrence order."""
    urls: list[str] = []
    seen: set[str] = set()

    for match in TFSEC_GUIDE_URL_PATTERN.finditer(errors):
        url = match.group(0).rstrip('.,;:)')
        if url not in seen:
            seen.add(url)
            urls.append(url)

    return urls


def extract_tfsec_guide_url(errors: str) -> str | None:
    """Return the first AquaSecurity TFSec guide URL in the output."""
    return next(iter(extract_tfsec_guide_urls(errors)), None)


def _join_unique(texts: Iterable[str]) -> str:
    """Join non-empty texts with newlines, dropping repeats while keeping order."""
    return '\n'.join(dict.fromkeys(text for text in texts if text))


def _text_blocks(node: Tag) -> list[str]:
    """Return the text of the outermost text blocks under node, never a block and its descendants."""
    if node.name in TEXT_TAGS:
        return [node.get_text(' ', strip=True)]
    texts: list[str] = []
    for child in node.find_all(recursive=False):
        if child.name != 'pre':
            texts.extend(_text_blocks(child))
    return texts


def _text_after(heading: Tag) -> str:
    """Return readable text that follows a heading in document order, up to the next h2/h3.

    Only the outermost text blocks are taken, so a block is never repeated through its
    descendants, and code inside ``pre`` and page chrome (footer, nav, aside) are skipped.
    """
    texts: list[str] = []
    for tag in heading.find_all_next():
        if tag.name in HEADING_TAGS:
            break
        if tag.name in TEXT_TAGS and not tag.find_parent([*TEXT_TAGS, 'pre', *PAGE_CHROME_TAGS]):
            texts.append(tag.get_text(' ', strip=True))
    return _join_unique(texts)


def _section_text(soup: BeautifulSoup, title: str) -> str:
    """Return readable text under the named h2/h3 heading, up to the next one."""
    heading = soup.find(
        lambda tag: tag.name in HEADING_TAGS
        and tag.get_text(' ', strip=True).casefold() == title.casefold()
    )
    return _text_after(heading) if heading else ''


def _extract_code_block(pre: Tag) -> str:
    """Extract a code block while preserving its source whitespace, leaving the HTML tree untouched."""
    pre_copy = copy(pre)
    for line_break in pre_copy.find_all('br'):
        line_break.replace_with('\n')

    return pre_copy.get_text('', strip=False).strip()


def _terraform_examples(scope: Tag | BeautifulSoup) -> list[tuple[str, str]]:
    """Return (preceding heading, code) for every Terraform block under scope.

    The heading must sit inside scope; a heading outside it may belong to unrelated
    content, so the label is left empty rather than misleading.
    """
    examples: list[tuple[str, str]] = []
    for pre in scope.find_all('pre'):
        code = _extract_code_block(pre)
        if TERRAFORM_CODE_PATTERN.search(code):
            heading = pre.find_previous(HEADING_TAGS)
            label = ''
            if heading is not None and scope in heading.parents:
                label = heading.get_text(' ', strip=True)
            examples.append((label, code))
    return examples


def _terraform_tab(soup: BeautifulSoup) -> Tag | None:
    """Return the Terraform tab of a tabbed Trivy remediation, if the page has one."""
    for panel in soup.select('div.tab-panel'):
        labels = [button.get_text(strip=True).casefold() for button in panel.select('.tab-nav button')]
        items = panel.select('.tab-content > .tab-item')
        if 'terraform' in labels and len(labels) == len(items):
            return items[labels.index('terraform')]
    return None


def _guide_header(url: str, soup: BeautifulSoup) -> list[str]:
    """Start a formatted guide with its URL and the page's h1 finding."""
    parts = [url]
    title = soup.find('h1')
    if title:
        parts.append(title.get_text(' ', strip=True))
    return parts


def parse_trivy_guide(url: str, html: str) -> str:
    """Extract Terraform-oriented remediation guidance from a Trivy guide page."""
    soup = BeautifulSoup(html, HTML_PARSER)

    for heading in soup.find_all('h4', string=re.compile(r"^\s*Remediation Links\s*$", re.IGNORECASE)):
        if links := heading.find_next_sibling('ul'):
            links.decompose()
        heading.decompose()

    # Newer pages split remediation into CloudFormation / Console / Terraform tabs.
    tab = _terraform_tab(soup)
    if tab:
        action_text = _join_unique(_text_blocks(tab))
    else:
        action_text = _section_text(soup, 'Recommended Actions')
    examples = _terraform_examples(tab or soup)

    # The rule's summary is the page's first h3, followed by its description.
    summary = soup.select_one('.vulnerability_content > h3')
    description = ''
    if summary:
        description = _join_unique([summary.get_text(' ', strip=True), _text_after(summary)])

    if not action_text and not examples:
        return ''

    guide_parts = _guide_header(url, soup)
    if description:
        guide_parts.append(description)
    if action_text:
        guide_parts.append(action_text)
    if examples:
        code = '\n'.join(code for _, code in examples)
        guide_parts.append(f"```hcl\n{code}\n```")

    return '\n'.join(guide_parts)


def parse_tfsec_guide(url: str, html: str) -> str:
    """Extract remediation guidance and Terraform examples from a TFSec page."""
    soup = BeautifulSoup(html, HTML_PARSER)
    sections = {
        title: _section_text(soup, title)
        for title in ('Explanation', 'Possible Impact', 'Suggested Resolution')
    }
    examples = _terraform_examples(soup)

    if not any(sections.values()) and not examples:
        return ''

    guide_parts = _guide_header(url, soup)
    guide_parts.extend(text for text in sections.values() if text)
    # Keep the page's own "Insecure Example" / "Secure Example" labels so the
    # model can tell the broken snippet from the fix.
    guide_parts.extend(
        f"{label}\n```hcl\n{code}\n```" if label else f"```hcl\n{code}\n```"
        for label, code in examples
    )

    return '\n'.join(guide_parts)


def _request_trivy_page(url: str):
    return requests.get(url, timeout=config.default_timeout)


def _request_tfsec_page(url: str):
    return requests.get(url, timeout=config.default_timeout)


def _get_refresh_target(url: str, html: str) -> str | None:
    """Return a page's HTML refresh or canonical target, if it has one."""
    soup = BeautifulSoup(html, HTML_PARSER)

    refresh_tag = soup.find(
        'meta',
        attrs={'http-equiv': lambda value: value and value.casefold() == 'refresh'},
    )
    if refresh_tag:
        content = str(refresh_tag.get('content') or '')
        match = re.search(r"url\s*=\s*[\"']?([^\"'\s]+)", content, flags=re.IGNORECASE)
        if match:
            return urljoin(url, match.group(1))

    for link in soup.find_all('link'):
        raw_rel = link.get('rel')
        if isinstance(raw_rel, str):
            rel = {raw_rel.casefold()}
        elif raw_rel:
            rel = {str(value).casefold() for value in raw_rel}
        else:
            rel = set()

        href = link.get('href')
        if 'canonical' in rel and href:
            return urljoin(url, str(href))

    return None


def _fetch_trivy_guide(url: str) -> str:
    current_url = url

    for _ in range(3):
        response = _request_trivy_page(current_url)
        response.raise_for_status()

        refresh_target = _get_refresh_target(current_url, response.text)
        if not refresh_target or refresh_target.rstrip('/') == current_url.rstrip('/'):
            return parse_trivy_guide(current_url, response.text)

        if not is_trivy_guide_url(refresh_target):
            logger.warning(f"Refusing to follow Trivy guide refresh to {refresh_target}")
            return ''

        logger.debug(f"Following Trivy guide refresh from {current_url} to {refresh_target}")
        current_url = refresh_target

    logger.warning(f"Too many refresh redirects while retrieving Trivy guide {url}")
    return ''


def _tfsec_latest_url(url: str) -> str:
    """Replace a version segment in a TFSec guide URL with latest."""
    return re.sub(r"(/tfsec/)[^/]+(/)", r"\1latest\2", url, count=1)


def _fetch_tfsec_guide(url: str) -> str:
    response = _request_tfsec_page(url)
    if response.status_code == 404:
        latest_url = _tfsec_latest_url(url)
        if latest_url != url:
            logger.debug(f"Retrying TFSec guide with latest version: {latest_url}")
            response = _request_tfsec_page(latest_url)
            url = latest_url

    response.raise_for_status()
    return parse_tfsec_guide(url, response.text)


def extract_trivy_guides(errors: str) -> str:
    """Fetch and format Terraform remediation guides referenced by Trivy errors."""
    guides: list[str] = []

    for url in extract_trivy_guide_urls(errors):
        try:
            guide = _fetch_trivy_guide(url)
        except (requests.RequestException, ValueError) as error:
            logger.warning(f"Unable to retrieve Trivy guide {url}: {error}")
            continue

        if guide:
            guides.append(guide)

    return '\n---\n'.join(guides)


def extract_tfsec_guide(errors: str) -> str:
    """Fetch and format Terraform remediation guides referenced by TFSec."""
    guides: list[str] = []

    for url in extract_tfsec_guide_urls(errors):
        try:
            guide = _fetch_tfsec_guide(url)
        except (requests.RequestException, ValueError) as error:
            logger.warning(f"Unable to retrieve TFSec guide {url}: {error}")
            continue

        if guide:
            guides.append(guide)

    return '\n---\n'.join(guides)
