import pytest

from tests.data.logs_s3 import (
    LOG_TEXT_CHECKOV,
    LOG_TEXT_TFLINT,
    LOG_TEXT_TFSEC,
    LOG_TEXT_TRIVY,
)


@pytest.fixture
def log_file_text_tflint():
    return LOG_TEXT_TFLINT


@pytest.fixture
def log_file_text_checkov():
    return LOG_TEXT_CHECKOV


@pytest.fixture
def log_file_text_tfsec():
    return LOG_TEXT_TFSEC


@pytest.fixture
def log_file_text_trivy():
    return LOG_TEXT_TRIVY
