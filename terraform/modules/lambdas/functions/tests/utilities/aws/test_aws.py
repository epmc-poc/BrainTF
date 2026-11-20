import boto3

from tests.data.file_samples import MAIN_TF_FILE

TEST_BUCKET = "test-bucket"
TEST_PREFIX = ""
AWS_REGION = "eu-central-1"
VALIDATE_TF_CONTENT = 'variable "aws_region" { default = "eu-central-1" }\n'

def _s3_list_response(contents, is_truncated=False, token=None):
    response = {
        "IsTruncated": is_truncated,
        "Contents": contents,
        "KeyCount": len(contents),
        "Name": TEST_BUCKET,
        "Prefix": TEST_PREFIX,
        "MaxKeys": 1000,
    }
    if token:
        response["NextContinuationToken"] = token
    return response


class StubbedS3Client:
    def __init__(self, responses, call_counter, wrapped=None):
        self._responses = responses
        self._call_counter = call_counter
        self._wrapped = wrapped

    def list_objects_v2(self, **kwargs):
        index = self._call_counter["count"]
        self._call_counter["count"] += 1
        return self._responses[index]

    def __getattr__(self, name):
        if self._wrapped is None:
            raise AttributeError(name)
        return getattr(self._wrapped, name)


def test_get_file_names_from_s3_directory_success(patched_environment, s3_setup):
    from utilities.aws import get_file_names_from_s3_directory

    result = get_file_names_from_s3_directory(TEST_BUCKET, TEST_PREFIX)
    assert isinstance(result, list)
    assert len(result) == 2
    assert "main.tf" in result
    assert "validate.tf" in result


def test_get_all_files_from_s3_directory_success(s3_setup):
    from utilities.aws import get_all_files_from_s3_directory

    result = get_all_files_from_s3_directory(TEST_BUCKET, TEST_PREFIX)
    assert isinstance(result, list)
    assert len(result) == 2
    assert result == [("main.tf", MAIN_TF_FILE), ("validate.tf", VALIDATE_TF_CONTENT)]


def test_get_particular_files_from_s3_directory_success(patched_environment, s3_setup):
    from utilities.aws import get_particular_files_from_s3_directory

    result = get_particular_files_from_s3_directory(TEST_BUCKET, TEST_PREFIX, ["main.tf"])
    assert isinstance(result, list)
    assert len(result) == 1
    assert result == [("main.tf", MAIN_TF_FILE)]


def test_get_file_names_from_s3_directory_pagination_truncated_then_not_truncated(s3_setup, monkeypatch):
    from utilities.aws import get_file_names_from_s3_directory

    responses = [
        _s3_list_response([{"Key": "main.tf", "Size": 10}], is_truncated=True, token="token-1"),
        _s3_list_response([{"Key": "validate.tf", "Size": 20}], is_truncated=False),
    ]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_file_names_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == ["main.tf", "validate.tf"]
    assert call_counter["count"] == 2


def test_get_all_files_from_s3_directory_pagination_truncated_then_not_truncated(s3_setup, monkeypatch):
    from utilities.aws import get_all_files_from_s3_directory

    real_s3 = boto3.client("s3")
    responses = [
        _s3_list_response([{"Key": "main.tf", "Size": 10}], is_truncated=True, token="token-1"),
        _s3_list_response([{"Key": "validate.tf", "Size": 20}], is_truncated=False),
    ]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter, wrapped=real_s3)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_all_files_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == [("main.tf", MAIN_TF_FILE), ("validate.tf", VALIDATE_TF_CONTENT)]
    assert call_counter["count"] == 2


def test_get_file_names_from_s3_directory_zero_size_object(s3_setup, monkeypatch):
    from utilities.aws import get_file_names_from_s3_directory

    real_s3 = boto3.client("s3")
    responses = [_s3_list_response([{"Key": "empty.tf", "Size": 0}], is_truncated=False)]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter, wrapped=real_s3)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_file_names_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == []
    assert call_counter["count"] == 1


def test_get_file_names_from_s3_directory_none_file_object(s3_setup, monkeypatch):
    from utilities.aws import get_file_names_from_s3_directory

    responses = [_s3_list_response([{"Key": "empty/", "Size": 10}], is_truncated=False)]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_file_names_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == []
    assert call_counter["count"] == 1


def test_get_all_files_from_s3_directory_none_file_object(s3_setup, monkeypatch):
    from utilities.aws import get_all_files_from_s3_directory

    responses = [_s3_list_response([{"Key": "empty/", "Size": 10}], is_truncated=False)]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_all_files_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == []
    assert call_counter["count"] == 1


def test_get_all_files_from_s3_directory_zero_size_object(s3_setup, monkeypatch):
    from utilities.aws import get_all_files_from_s3_directory

    responses = [_s3_list_response([{"Key": "empty.tf", "Size": 0}], is_truncated=False)]
    call_counter = {"count": 0}
    stubbed_client = StubbedS3Client(responses, call_counter)
    monkeypatch.setattr("utilities.aws._s3_client", lambda: stubbed_client)

    result = get_all_files_from_s3_directory(TEST_BUCKET, TEST_PREFIX)

    assert result == []
    assert call_counter["count"] == 1


# --- Branch instance registry ---------------------------------------------------

REGISTRY_PATH = "/BrainTF/_instances"


def _use_registry(monkeypatch, path=REGISTRY_PATH):
    from config import config
    from utilities import aws

    monkeypatch.setattr(config, "instance_registry_path", path)
    monkeypatch.setattr(aws, "_instance_registry_cache", {'expires_at': 0.0, 'branches': frozenset()})
    return aws


def _register(instance_id, branch):
    boto3.client("ssm").put_parameter(
        Name=f"{REGISTRY_PATH}/{instance_id}", Value=branch, Type="String", Overwrite=True,
    )


def test_registered_instance_branches_lists_registered_branches(patched_config_github, monkeypatch):
    aws = _use_registry(monkeypatch)
    _register("epmcacmaws-504", "feature/EPMCACMAWS-504-automated-deployment")
    _register("epmcacmaws-505", "feature/EPMCACMAWS-505-testing")
    # An instance's own parameters live under another prefix and are not branches.
    boto3.client("ssm").put_parameter(Name="/BrainTF/epmcacmaws-504/vcs_token", Value="secret", Type="String")

    assert aws.get_registered_instance_branches() == frozenset({
        "feature/EPMCACMAWS-504-automated-deployment",
        "feature/EPMCACMAWS-505-testing",
    })


def test_registered_instance_branches_empty_registry(patched_config_github, monkeypatch):
    aws = _use_registry(monkeypatch)

    assert aws.get_registered_instance_branches() == frozenset()


def test_registered_instance_branches_without_registry_makes_no_call(patched_config_github, monkeypatch):
    aws = _use_registry(monkeypatch, path="")

    def fail_if_called(*args, **kwargs):
        raise AssertionError("must not be called")

    monkeypatch.setattr(aws.boto3, "client", fail_if_called)

    assert aws.get_registered_instance_branches() == frozenset()


def test_registered_instance_branches_are_cached_until_ttl(patched_config_github, monkeypatch):
    aws = _use_registry(monkeypatch)
    clock = {"now": 1000.0}
    monkeypatch.setattr(aws.time, "monotonic", lambda: clock["now"])
    _register("epmcacmaws-504", "feature-a")
    assert aws.get_registered_instance_branches() == frozenset({"feature-a"})

    _register("epmcacmaws-505", "feature-b")
    clock["now"] += aws.INSTANCE_REGISTRY_TTL_SECONDS - 1
    assert aws.get_registered_instance_branches() == frozenset({"feature-a"})

    clock["now"] += 2
    assert aws.get_registered_instance_branches() == frozenset({"feature-a", "feature-b"})


def test_registered_instance_branches_fail_open_and_do_not_cache_failure(patched_config_github, monkeypatch):
    from botocore.exceptions import ClientError

    aws = _use_registry(monkeypatch)
    _register("epmcacmaws-504", "feature-a")
    real_client = aws.boto3.client

    def denied(*args, **kwargs):
        raise ClientError({"Error": {"Code": "AccessDeniedException", "Message": "denied"}}, "GetParametersByPath")

    monkeypatch.setattr(aws.boto3, "client", denied)
    assert aws.get_registered_instance_branches() == frozenset()

    monkeypatch.setattr(aws.boto3, "client", real_client)
    assert aws.get_registered_instance_branches() == frozenset({"feature-a"})
