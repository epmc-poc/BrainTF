from types import SimpleNamespace

import pytest


TFSEC_ERROR = '''
Result #1 HIGH No public access block so not blocking public acls
  More Information
  - https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/
  - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block
'''


def test_extract_trivy_guide_urls_preserves_order_and_deduplicates(patched_environment):
    from utilities.ai.web_rag import extract_trivy_guide_urls

    errors = '''
See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104
See https://avd.aquasec.com/misconfig/aws/s3/aws-0086.
See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104
'''

    assert extract_trivy_guide_urls(errors) == [
        'https://avd.aquasec.com/misconfig/aws/ec2/aws-0104',
        'https://avd.aquasec.com/misconfig/aws/s3/aws-0086',
    ]


def test_extract_tfsec_guide_urls_preserves_order_and_deduplicates(patched_environment):
    from utilities.ai.web_rag import extract_tfsec_guide_urls

    errors = (
        '  - https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/\n'
        '  - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket\n'
        '  - https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/\n'
        '  - https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-policy/\n'
    )

    assert extract_tfsec_guide_urls(errors) == [
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-policy/',
    ]


def test_parse_trivy_guide_preserves_hcl_formatting(patched_environment):
    from utilities.ai.web_rag import parse_trivy_guide

    html = '''
    <html>
      <h1>No Public Egress SGR</h1>
      <h3>Recommended Actions</h3>
      <p>Set a more restrictive cidr range.</p>
      <pre><code><span>resource</span> <span>"aws_security_group"</span> <span>"good_example"</span> <span>{</span>
  <span>egress</span> <span>{</span>
    <span>cidr_blocks</span> <span>=</span> <span>["1.2.3.4/32"]</span>
  <span>}</span>
<span>}</span></code></pre>
      <h3>Links</h3>
    </html>
    '''

    result = parse_trivy_guide(
        'https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/',
        html,
    )

    assert 'resource "aws_security_group" "good_example" {' in result
    assert '    cidr_blocks = ["1.2.3.4/32"]' in result
    assert 'resource\n"aws_security_group"' not in result


def test_extract_trivy_guides_parses_terraform_remediation(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    html = '''
    <html>
      <h1>No Public Egress SGR</h1>
      <h3>Recommended Actions</h3>
      <p>Set a more restrictive cidr range.</p>
      <pre><code>AWSTemplateFormatVersion: "2010-09-09"</code></pre>
      <pre><code>resource "aws_security_group" "good_example" {
  egress {
    cidr_blocks = ["1.2.3.4/32"]
  }
}</code></pre>
      <h3>Links</h3>
      <p>Do not include this unrelated section.</p>
    </html>
    '''

    monkeypatch.setattr(
        web_rag,
        '_fetch_trivy_guide',
        lambda url: web_rag.parse_trivy_guide(url, html),
    )

    result = web_rag.extract_trivy_guides(
        'See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104'
    )

    assert 'No Public Egress SGR' in result
    assert 'Set a more restrictive cidr range.' in result
    assert 'resource "aws_security_group" "good_example"' in result
    assert 'Do not include this unrelated section.' not in result


def test_extract_trivy_guides_skips_failed_requests(patched_environment, monkeypatch, caplog):
    from utilities.ai import web_rag
    import requests

    def raise_request_error(_url):
        raise requests.RequestException('connection failed')

    monkeypatch.setattr(web_rag, '_fetch_trivy_guide', raise_request_error)

    result = web_rag.extract_trivy_guides(
        'See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104'
    )

    assert result == ''
    assert 'Unable to retrieve Trivy guide' in caplog.text


def test_fetch_trivy_guide_follows_html_refresh(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    refresh_html = '''
    <!doctype html>
    <html><head>
      <meta http-equiv="refresh" content="0; url=https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/">
    </head></html>
    '''
    guide_html = '''
    <html>
      <h1>No Public Egress SGR</h1>
      <h3>Recommended Actions</h3>
      <p>Set a more restrictive cidr range.</p>
      <pre><code>resource "aws_security_group" "good_example" {}</code></pre>
      <h3>Links</h3>
    </html>
    '''
    responses = iter([
        SimpleNamespace(text=refresh_html, raise_for_status=lambda: None),
        SimpleNamespace(text=guide_html, raise_for_status=lambda: None),
    ])
    requested_urls = []

    def request_page(url):
        requested_urls.append(url)
        return next(responses)

    monkeypatch.setattr(web_rag, '_request_page', request_page)

    result = web_rag._fetch_trivy_guide(
        'https://avd.aquasec.com/misconfig/aws-0104'
    )

    assert requested_urls == [
        'https://avd.aquasec.com/misconfig/aws-0104',
        'https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/',
    ]
    assert '```hcl' in result
    assert 'resource "aws_security_group" "good_example"' in result


def test_extract_trivy_guide_urls_rejects_other_hosts(patched_environment):
    from utilities.ai.web_rag import extract_trivy_guide_urls

    errors = '''
See http://127.0.0.1:8080/admin
See http://169.254.169.254/latest/meta-data/
See http://avd.aquasec.com/misconfig/aws-0104
See https://avd.aquasec.com.evil.com/x
See https://avd.aquasec.com@evil.com/x
See https://avd.aquasec.com:8080/x
See https://avd.aquasec.com/misconfig/aws-0104
'''

    assert extract_trivy_guide_urls(errors) == ['https://avd.aquasec.com/misconfig/aws-0104']


def test_fetch_trivy_guide_refuses_refresh_to_other_host(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    refresh_html = (
        '<html><head><meta http-equiv="refresh" '
        'content="0; url=http://169.254.169.254/latest/meta-data/"></head></html>'
    )
    requested_urls = []

    def request_page(url):
        requested_urls.append(url)
        return SimpleNamespace(text=refresh_html, raise_for_status=lambda: None)

    monkeypatch.setattr(web_rag, '_request_page', request_page)

    assert web_rag._fetch_trivy_guide('https://avd.aquasec.com/misconfig/aws-0104') == ''
    assert requested_urls == ['https://avd.aquasec.com/misconfig/aws-0104']


def test_fetch_trivy_guide_accepts_unquoted_same_domain_stub(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    stub_html = '''<!doctype html>
<html lang=en-us>
<head>
    <title>https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/</title>
    <link rel=canonical href=https://avd.aquasec.com/misconfig/aws/ec2/aws-0104 />
    <meta name=robots content="noindex">
    <meta charset=utf-8>
    <meta http-equiv=refresh content="0; url=https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/">
</head>
</html>'''
    guide_html = '''<html><h1>No Public Egress SGR</h1>
<h3>Recommended Actions</h3><p>Restrict the cidr range.</p>
<pre><code>resource "aws_security_group" "good_example" {}</code></pre></html>'''
    pages = {
        'https://avd.aquasec.com/misconfig/aws-0104': stub_html,
        'https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/': guide_html,
    }
    requested_urls = []

    def request_page(url):
        requested_urls.append(url)
        return SimpleNamespace(text=pages[url], raise_for_status=lambda: None)

    monkeypatch.setattr(web_rag, '_request_page', request_page)

    result = web_rag._fetch_trivy_guide('https://avd.aquasec.com/misconfig/aws-0104')

    assert requested_urls == list(pages)
    assert 'resource "aws_security_group" "good_example"' in result


def test_extract_tfsec_guide_url_uses_only_first_aquasecurity_source(patched_environment):
    from utilities.ai.web_rag import extract_tfsec_guide_url

    errors = TFSEC_ERROR.replace(
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
        'https://example.com/first https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
    )

    assert extract_tfsec_guide_url(errors) == (
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/'
    )


def test_parse_tfsec_guide_preserves_hcl_formatting(patched_environment):
    from utilities.ai.web_rag import parse_tfsec_guide

    html = '''
    <html>
      <h1>S3 Access block should block public ACL</h1>
      <p>Default Severity: high</p>
      <h2>Explanation</h2><p>S3 buckets should block public ACLs.</p>
      <h2>Possible Impact</h2><p>PUT calls with public ACLs specified can make objects public</p>
      <h2>Suggested Resolution</h2><p>Enable blocking any PUT calls with a public ACL specified</p>
      <h2>Insecure Example</h2>
      <pre><code><span>resource</span> <span>"aws_s3_bucket"</span> <span>"bad_example"</span> <span>{</span>
  <span>bucket</span> <span>=</span> <span>"mybucket"</span>
<span>}</span></code></pre>
      <h2>Secure Example</h2>
      <pre><code>resource "aws_s3_bucket_public_access_block" "good_example" {
  bucket = aws_s3_bucket.good_example.id
  block_public_acls = true
}</code></pre>
    </html>
    '''

    result = parse_tfsec_guide(
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
        html,
    )

    assert 'Default Severity' not in result
    assert 'high' not in result
    assert 'resource "aws_s3_bucket" "bad_example" {' in result
    assert '  block_public_acls = true' in result
    assert 'resource\n"aws_s3_bucket"' not in result


def test_fetch_tfsec_guide_retries_latest_after_404(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    html = '''
    <h1>S3 Access block should block public ACL</h1>
    <h2>Suggested Resolution</h2><p>Enable blocking public ACLs.</p>
    '''
    responses = iter([
        SimpleNamespace(status_code=404, text='', raise_for_status=lambda: None),
        SimpleNamespace(status_code=200, text=html, raise_for_status=lambda: None),
    ])
    requested_urls = []

    def request_page(url):
        requested_urls.append(url)
        return next(responses)

    monkeypatch.setattr(web_rag, '_request_page', request_page)

    result = web_rag._fetch_tfsec_guide(
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/'
    )

    assert requested_urls == [
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
        'https://aquasecurity.github.io/tfsec/latest/checks/aws/s3/block-public-acls/',
    ]
    assert 'Enable blocking public ACLs.' in result
    assert 'Suggested Resolution' not in result


def test_extract_tfsec_guide_fetches_all_aquasecurity_sources(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    urls = [
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-acls/',
        'https://aquasecurity.github.io/tfsec/v1.28.14/checks/aws/s3/block-public-policy/',
    ]
    fetched_urls = []

    def fetch_guide(url):
        fetched_urls.append(url)
        return f"Guide: {url}"

    monkeypatch.setattr(web_rag, '_fetch_tfsec_guide', fetch_guide)

    result = web_rag.extract_tfsec_guide(
        '\n'.join(urls)
        + '\nhttps://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket'
    )

    assert fetched_urls == urls
    assert result == '\n---\n'.join(f"Guide: {url}" for url in urls)


def test_parse_tfsec_guide_labels_insecure_and_secure_examples(patched_environment):
    from utilities.ai.web_rag import parse_tfsec_guide

    html = '''
    <h1>S3 Access block should block public ACL</h1>
    <h3>Suggested Resolution</h3><p>Enable blocking public ACLs.</p>
    <h3>Insecure Example</h3>
    <pre>resource "aws_s3_bucket" "bad_example" {}</pre>
    <h3>Secure Example</h3>
    <pre>resource "aws_s3_bucket" "good_example" {}</pre>
    <h3>Links</h3><p>Do not include this unrelated section.</p>
    '''

    result = parse_tfsec_guide('https://aquasecurity.github.io/tfsec/latest/', html)

    assert result.index('Insecure Example') < result.index('bad_example')
    assert result.index('\nSecure Example') < result.index('good_example')
    assert result.index('bad_example') < result.index('\nSecure Example')
    assert 'Do not include this unrelated section.' not in result


def test_parse_trivy_guide_prefers_terraform_tab(patched_environment):
    from utilities.ai.web_rag import parse_trivy_guide

    html = '''
    <h1>Block Public ACLs</h1>
    <h3>Recommended Actions</h3>
    <p>Follow the appropriate remediation steps below.</p>
    <div class="tab-panel">
      <div class="tab-nav"><button>CloudFormation</button><button>Management Console</button><button>Terraform</button></div>
      <div class="tab-content">
        <div class="tab-item"><p>CFN text.</p><pre>Resources: {}</pre></div>
        <div class="tab-item"><ol><li>Log in to the AWS Management Console.</li></ol></div>
        <div class="tab-item"><p>Enable blocking PUT calls.</p><pre>resource "aws_s3_bucket" "good_example" {}</pre></div>
      </div>
    </div>
    <h3>Links</h3>
    '''

    result = parse_trivy_guide('https://avd.aquasec.com/misconfig/aws/s3/aws-0086/', html)

    assert 'Enable blocking PUT calls.' in result
    assert 'resource "aws_s3_bucket" "good_example"' in result
    assert 'Management Console' not in result
    assert 'CFN text.' not in result


def test_parse_trivy_guide_includes_rule_description(patched_environment):
    from utilities.ai.web_rag import parse_trivy_guide

    html = '''
    <h1>No Public Egress SGR</h1>
    <div class="content vulnerability_content">
      <h3 id="summary">A security group rule should not allow unrestricted egress.</h3>
      <p>Opening up ports to the public internet is generally to be avoided.</p>
      <h3 id="impact">Impact</h3>
      <h3 id="recommended-actions">Recommended Actions</h3>
      <p>Set a more restrictive cidr range</p>
      <pre>resource "aws_security_group" "good_example" {}</pre>
      <h3 id="links">Links</h3>
    </div>
    '''

    result = parse_trivy_guide('https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/', html)

    assert '\nA security group rule should not allow unrestricted egress.\n' in result
    assert 'Opening up ports to the public internet is generally to be avoided.' in result
    assert result.index('A security group rule') < result.index('Set a more restrictive cidr range')


def test_section_text_does_not_duplicate_nested_text_blocks(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _section_text

    soup = BeautifulSoup(
        '''
        <h2>Explanation</h2>
        <ul><li>Use encryption.<p>Enable encryption at rest.</p></li></ul>
        <h2>Suggested Resolution</h2>
        ''',
        'html.parser',
    )

    assert _section_text(soup, 'Explanation') == 'Use encryption. Enable encryption at rest.'


def test_section_text_stays_inside_heading_container(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _section_text

    soup = BeautifulSoup(
        '''
        <article><h2>Suggested Resolution</h2><p>Enable it.</p></article>
        <footer><p>Copyright footer</p></footer>
        ''',
        'html.parser',
    )

    assert _section_text(soup, 'Suggested Resolution') == 'Enable it.'


def test_section_text_keeps_text_before_nested_heading(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _section_text

    soup = BeautifulSoup(
        '<h2>Explanation</h2><div><p>Important explanation text.</p><h3>Details</h3><p>More.</p></div>',
        'html.parser',
    )

    assert _section_text(soup, 'Explanation') == 'Important explanation text.'


def test_section_text_follows_heading_wrapped_in_its_own_container(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _section_text

    soup = BeautifulSoup(
        '<div><h2>Explanation</h2></div><div><p>Explanation text.</p></div><h2>Next</h2><p>Other.</p>',
        'html.parser',
    )

    assert _section_text(soup, 'Explanation') == 'Explanation text.'


def test_terraform_examples_ignore_heading_outside_scope(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _terraform_examples, _terraform_tab

    soup = BeautifulSoup(
        '''
        <h2>Insecure Example</h2>
        <div class="tab-panel">
          <div class="tab-nav"><button>CloudFormation</button><button>Terraform</button></div>
          <div class="tab-content">
            <div class="tab-item"><pre>Resources: {}</pre></div>
            <div class="tab-item"><pre>resource "aws_s3_bucket" "good" {}</pre></div>
          </div>
        </div>
        ''',
        'html.parser',
    )

    assert _terraform_examples(_terraform_tab(soup)) == [('', 'resource "aws_s3_bucket" "good" {}')]


def test_terraform_examples_keep_heading_inside_scope(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _terraform_examples

    soup = BeautifulSoup(
        '''
        <h2>Insecure Example</h2>
        <pre>resource "aws_s3_bucket" "bad" {}</pre>
        <h2>Secure Example</h2>
        <div class="code-wrapper"><pre>resource "aws_s3_bucket" "good" {}</pre></div>
        ''',
        'html.parser',
    )

    assert _terraform_examples(soup) == [
        ('Insecure Example', 'resource "aws_s3_bucket" "bad" {}'),
        ('Secure Example', 'resource "aws_s3_bucket" "good" {}'),
    ]


@pytest.mark.parametrize('code', [
    'terraform {\n  required_version = ">= 1.5.0"\n}',
    'locals {\n  common_tags = {}\n}',
    'variable "bucket_name" {\n  type = string\n}',
    'output "bucket_id" {\n  value = aws_s3_bucket.example.id\n}',
    'moved {\n  from = a.b\n  to = a.c\n}',
    'import {\n  to = a.b\n  id = "x"\n}',
    'check "health" {\n}',
    '  resource "aws_s3_bucket" "example" {}',
    '# comment\ndata "aws_caller_identity" "current" {}',
])
def test_terraform_code_pattern_matches_valid_blocks(patched_environment, code):
    from utilities.ai.web_rag import TERRAFORM_CODE_PATTERN

    assert TERRAFORM_CODE_PATTERN.search(code)


@pytest.mark.parametrize('code', [
    'terraform init',
    'import os\ncheck = 1',
    'import "fmt"\nfunc main() {}',
    'Resources:\n  Bucket:\n    Type: AWS::S3::Bucket',
])
def test_terraform_code_pattern_ignores_other_languages(patched_environment, code):
    from utilities.ai.web_rag import TERRAFORM_CODE_PATTERN

    assert not TERRAFORM_CODE_PATTERN.search(code)


def test_extract_code_block_converts_line_breaks_without_modifying_tree(patched_environment):
    from bs4 import BeautifulSoup
    from utilities.ai.web_rag import _extract_code_block

    soup = BeautifulSoup('<div><pre>resource "a" "b" {<br>  x = 1<br/>}</pre></div>', 'html.parser')
    original = str(soup)

    assert _extract_code_block(soup.pre) == 'resource "a" "b" {\n  x = 1\n}'
    assert str(soup) == original
    assert len(soup.pre.find_all('br')) == 2
