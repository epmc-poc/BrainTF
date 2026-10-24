import re
from collections.abc import Iterable
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from config import config
from utilities.logger import logger

TRIVY_GUIDE_URL_PATTERN = re.compile(
    r"(?m)^\s*See\s+(https?://\S+)"
)
TFSEC_GUIDE_URL_PATTERN = re.compile(
    r"https://aquasecurity\.github\.io/tfsec/[^\s<>)\]]+"
)
TERRAFORM_CODE_PATTERN = re.compile(
    r"\b(?:resource|data|module|provider|terraform)\s+\""
)


def extract_trivy_guide_urls(errors: str) -> list[str]:
    """Return unique Trivy guide URLs in the order they occur in the output."""
    urls: list[str] = []
    seen: set[str] = set()

    for match in TRIVY_GUIDE_URL_PATTERN.finditer(errors):
        url = match.group(1).rstrip(".,);]")
        if url not in seen:
            seen.add(url)
            urls.append(url)

    return urls


def extract_tfsec_guide_urls(errors: str) -> list[str]:
    """Return unique AquaSecurity TFSec guide URLs in occurrence order."""
    urls: list[str] = []
    seen: set[str] = set()

    for match in TFSEC_GUIDE_URL_PATTERN.finditer(errors):
        url = match.group(0).rstrip(".,;:)")
        if url not in seen:
            seen.add(url)
            urls.append(url)

    return urls


def extract_tfsec_guide_url(errors: str) -> str | None:
    """Return the first AquaSecurity TFSec guide URL in the output."""
    return next(iter(extract_tfsec_guide_urls(errors)), None)


def _text_between_headings(heading, stop_titles: Iterable[str]) -> str:
    """Collect readable text after a heading until another section starts."""
    stop_titles = {title.casefold() for title in stop_titles}
    parts: list[str] = []

    for element in heading.find_all_next():
        if element.name in {"h2", "h3"}:
            title = element.get_text(" ", strip=True).casefold()
            if title in stop_titles:
                break
            continue

        if element.name in {"p", "h4", "li"}:
            text = element.get_text(" ", strip=True)
            if text and text not in parts:
                parts.append(text)

    return "\n".join(parts)


def _find_section(heading, section_title: str) -> str:
    """Return readable text from a named TFSec section."""
    section_heading = heading.find(
        lambda tag: tag.name in {"h2", "h3"}
        and tag.get_text(" ", strip=True).casefold() == section_title.casefold()
    )
    if section_heading is None:
        return ""

    parts: list[str] = []
    for element in section_heading.find_all_next():
        if element.name in {"h2", "h3"}:
            break
        if element.name in {"p", "h4", "li"}:
            text = element.get_text(" ", strip=True)
            if text and text not in parts:
                parts.append(text)
    return "\n".join(parts)


def _extract_code_block(pre) -> str:
    """Extract a code block while preserving its source whitespace."""
    for line_break in pre.find_all("br"):
        line_break.replace_with("\n")

    return pre.get_text("", strip=False).strip()


def parse_trivy_guide(url: str, html: str) -> str:
    """Extract Terraform-oriented remediation guidance from a Trivy guide page."""
    soup = BeautifulSoup(html, "html.parser")
    title = soup.find("h1")
    action_heading = soup.find(
        lambda tag: tag.name in {"h2", "h3"}
        and tag.get_text(" ", strip=True).casefold() == "recommended actions"
    )

    if action_heading is None:
        return ""

    action_text = _text_between_headings(action_heading, {"links"})
    terraform_examples: list[str] = []
    for pre in soup.find_all("pre"):
        code = _extract_code_block(pre)
        if TERRAFORM_CODE_PATTERN.search(code):
            terraform_examples.append(code)

    if not action_text and not terraform_examples:
        return ""

    guide_parts = [f"Guide: {url}"]
    if title:
        guide_parts.append(f"Finding: {title.get_text(' ', strip=True)}")
    if action_text:
        guide_parts.append(f"Recommended remediation:\n{action_text}")
    if terraform_examples:
        guide_parts.append(
            "Terraform example:\n```hcl\n"
            + "\n\n".join(terraform_examples)
            + "\n```"
        )

    return "\n\n".join(guide_parts)


def parse_tfsec_guide(url: str, html: str) -> str:
    """Extract remediation guidance and Terraform examples from a TFSec page."""
    soup = BeautifulSoup(html, "html.parser")
    title = soup.find("h1")
    page_text = soup.get_text(" ", strip=True)
    severity = re.search(r"Default Severity:\s*(\S+)", page_text, flags=re.IGNORECASE)

    sections = {
        "Explanation": _find_section(soup, "Explanation"),
        "Possible Impact": _find_section(soup, "Possible Impact"),
        "Suggested Resolution": _find_section(soup, "Suggested Resolution"),
    }
    examples: list[str] = []
    for pre in soup.find_all("pre"):
        code = _extract_code_block(pre)
        if TERRAFORM_CODE_PATTERN.search(code):
            examples.append(code)

    if not any(sections.values()) and not examples:
        return ""

    guide_parts = [f"Guide: {url}"]
    if title:
        guide_parts.append(f"Finding: {title.get_text(' ', strip=True)}")
    if severity:
        guide_parts.append(f"Default Severity: {severity.group(1)}")
    for section_name, section_text in sections.items():
        if section_text:
            guide_parts.append(f"{section_name}\n{section_text}")
    if examples:
        guide_parts.append(
            "Terraform examples:\n```hcl\n"
            + "\n\n".join(examples)
            + "\n```"
        )

    return "\n\n".join(guide_parts)


def _request_trivy_page(url: str):
    return requests.get(url, timeout=config.default_timeout)


def _request_tfsec_page(url: str):
    return requests.get(url, timeout=config.default_timeout)


def _get_refresh_target(url: str, html: str) -> str | None:
    """Return a page's HTML refresh or canonical target, if it has one."""
    soup = BeautifulSoup(html, "html.parser")

    refresh_tag = soup.find(
        "meta",
        attrs={"http-equiv": lambda value: value and value.casefold() == "refresh"},
    )
    if refresh_tag:
        content = str(refresh_tag.get("content") or "")
        match = re.search(r"url\s*=\s*[\"']?([^\"'\s]+)", content, flags=re.IGNORECASE)
        if match:
            return urljoin(url, match.group(1))

    for link in soup.find_all("link"):
        raw_rel = link.get("rel")
        if isinstance(raw_rel, str):
            rel = {raw_rel.casefold()}
        elif raw_rel:
            rel = {str(value).casefold() for value in raw_rel}
        else:
            rel = set()

        href = link.get("href")
        if "canonical" in rel and href:
            return urljoin(url, str(href))

    return None


def _fetch_trivy_guide(url: str) -> str:
    current_url = url

    for _ in range(3):
        response = _request_trivy_page(current_url)
        response.raise_for_status()

        refresh_target = _get_refresh_target(current_url, response.text)
        if not refresh_target or refresh_target.rstrip("/") == current_url.rstrip("/"):
            return parse_trivy_guide(current_url, response.text)

        logger.debug("Following Trivy guide refresh from %s to %s", current_url, refresh_target)
        current_url = refresh_target

    logger.warning("Too many refresh redirects while retrieving Trivy guide %s", url)
    return ""


def _tfsec_latest_url(url: str) -> str:
    """Replace a version segment in a TFSec guide URL with latest."""
    return re.sub(r"(/tfsec/)[^/]+(/)", r"\1latest\2", url, count=1)


def _fetch_tfsec_guide(url: str) -> str:
    response = _request_tfsec_page(url)
    if response.status_code == 404:
        latest_url = _tfsec_latest_url(url)
        if latest_url != url:
            logger.debug("Retrying TFSec guide with latest version: %s", latest_url)
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
            logger.warning("Unable to retrieve Trivy guide %s: %s", url, error)
            continue

        if guide:
            guides.append(guide)

    return "\n\n---\n\n".join(guides)


def extract_tfsec_guide(errors: str) -> str:
    """Fetch and format Terraform remediation guides referenced by TFSec."""
    guides: list[str] = []

    for url in extract_tfsec_guide_urls(errors):
        try:
            guide = _fetch_tfsec_guide(url)
        except (requests.RequestException, ValueError) as error:
            logger.warning("Unable to retrieve TFSec guide %s: %s", url, error)
            continue

        if guide:
            guides.append(guide)

    return "\n\n---\n\n".join(guides)
