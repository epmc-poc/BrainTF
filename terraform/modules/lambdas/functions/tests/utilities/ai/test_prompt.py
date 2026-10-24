from tests.data.file_samples import DEMO_BROKEN_MAIN_TF_FILE
from tests.data.logs_s3 import LOG_TEXT_TFLINT_NEW


def test_make_prompt_block_with_errors_and_files_tflint(patched_environment):
    from config import config
    from utilities.ai.prompt import make_prompt_block_with_errors_and_files
    event = {"metadata": {"tool_name": "checkov"}}
    patched_environment.setattr(config, "rag_enabled", True)
    patched_environment.setattr(
        "utilities.ai.prompt.get_all_tf_files_from_paths_list",
        lambda current_event, paths_to_files: [("demo/broken/main.tf", DEMO_BROKEN_MAIN_TF_FILE)],
    )
    make_prompt_block_with_errors_and_files(event, LOG_TEXT_TFLINT_NEW)


def test_make_prompt_block_with_trivy_guides_when_rag_enabled(patched_environment, monkeypatch):
    from utilities.ai.prompt import make_prompt_block_with_errors_and_files

    event = {"metadata": {"tool_name": "trivy"}}
    monkeypatch.setattr(
        "utilities.ai.prompt.extract_trivy_guides",
        lambda errors: "Guide: https://avd.aquasec.com/misconfig/aws/ec2/aws-0104\nTerraform example",
    )
    monkeypatch.setattr(
        "utilities.ai.prompt.get_all_tf_files_from_paths_list",
        lambda current_event, paths_to_files: [("demo/broken/main.tf", DEMO_BROKEN_MAIN_TF_FILE)],
    )

    prompt = make_prompt_block_with_errors_and_files(
        event,
        "Running Trivy analysis in directory: demo/broken\n"
        "AWS-0104 (CRITICAL): unrestricted egress\n"
        "See https://avd.aquasec.com/misconfig/aws/ec2/aws-0104",
    )

    assert "Guide: https://avd.aquasec.com/misconfig/aws/ec2/aws-0104" in prompt
    assert prompt.index("Terraform example") < prompt.index("File content on:")


def test_make_prompt_block_with_trivy_guides_disabled(patched_environment, monkeypatch):
    from config import config
    from utilities.ai.prompt import make_prompt_block_with_errors_and_files

    event = {"metadata": {"tool_name": "trivy"}}
    patched_environment.setattr(config, "rag_enabled", False)
    monkeypatch.setattr(
        "utilities.ai.prompt.extract_trivy_guides",
        lambda errors: (_ for _ in ()).throw(AssertionError("retrieval should be disabled")),
    )
    monkeypatch.setattr(
        "utilities.ai.prompt.get_all_tf_files_from_paths_list",
        lambda current_event, paths_to_files: [],
    )

    prompt = make_prompt_block_with_errors_and_files(
        event,
        "Running Trivy analysis in directory: demo/broken\n"
        "AWS-0104 (CRITICAL): unrestricted egress",
    )

    assert "Guide:" not in prompt
