from types import SimpleNamespace


def test_extract_trivy_guide_urls_preserves_order_and_deduplicates(patched_environment):
    from utilities.ai.web_rag import extract_trivy_guide_urls

    errors = """
See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104
See https://avd.aquasec.com/misconfig/aws/s3/aws-0086.
See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104
"""

    assert extract_trivy_guide_urls(errors) == [
        "https://avd.aquasec.com/misconfig/aws/ec2/aws-0104",
        "https://avd.aquasec.com/misconfig/aws/s3/aws-0086",
    ]


def test_parse_trivy_guide_preserves_hcl_formatting(patched_environment):
    from utilities.ai.web_rag import parse_trivy_guide

    html = """
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
    """

    result = parse_trivy_guide(
        "https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/",
        html,
    )

    assert 'resource "aws_security_group" "good_example" {' in result
    assert '    cidr_blocks = ["1.2.3.4/32"]' in result
    assert 'resource\n"aws_security_group"' not in result


def test_extract_trivy_guides_parses_terraform_remediation(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    html = """
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
    """

    monkeypatch.setattr(
        web_rag,
        "_fetch_trivy_guide",
        lambda url: web_rag.parse_trivy_guide(url, html),
    )

    result = web_rag.extract_trivy_guides(
        "See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104"
    )

    assert "Finding: No Public Egress SGR" in result
    assert "Set a more restrictive cidr range." in result
    assert 'resource "aws_security_group" "good_example"' in result
    assert "Do not include this unrelated section." not in result


def test_extract_trivy_guides_skips_failed_requests(patched_environment, monkeypatch, caplog):
    from utilities.ai import web_rag
    import requests

    def raise_request_error(_url):
        raise requests.RequestException("connection failed")

    monkeypatch.setattr(web_rag, "_fetch_trivy_guide", raise_request_error)

    result = web_rag.extract_trivy_guides(
        "See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104"
    )

    assert result == ""
    assert "Unable to retrieve Trivy guide" in caplog.text


def test_fetch_trivy_guide_follows_html_refresh(patched_environment, monkeypatch):
    from utilities.ai import web_rag

    refresh_html = """
    <!doctype html>
    <html><head>
      <meta http-equiv="refresh" content="0; url=https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/">
    </head></html>
    """
    guide_html = """
    <html>
      <h1>No Public Egress SGR</h1>
      <h3>Recommended Actions</h3>
      <p>Set a more restrictive cidr range.</p>
      <pre><code>resource "aws_security_group" "good_example" {}</code></pre>
      <h3>Links</h3>
    </html>
    """
    responses = iter([
        SimpleNamespace(text=refresh_html, raise_for_status=lambda: None),
        SimpleNamespace(text=guide_html, raise_for_status=lambda: None),
    ])
    requested_urls = []

    def request_page(url):
        requested_urls.append(url)
        return next(responses)

    monkeypatch.setattr(web_rag, "_request_trivy_page", request_page)

    result = web_rag._fetch_trivy_guide(
        "https://avd.aquasec.com/misconfig/aws-0104"
    )

    assert requested_urls == [
        "https://avd.aquasec.com/misconfig/aws-0104",
        "https://avd.aquasec.com/misconfig/aws/ec2/aws-0104/",
    ]
    assert "Terraform example:" in result
    assert 'resource "aws_security_group" "good_example"' in result
