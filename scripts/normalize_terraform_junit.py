#!/usr/bin/env python3
"""Make the JUnit XML of `terraform test` readable in dorny/test-reporter.

Fills in <testsuite time> (Terraform leaves it out, the report shows "NaNms") and replaces the
message "Encountered an error" with the error's title and explanation. Values Terraform already
sets are kept. Usage: normalize_terraform_junit.py FILE [FILE ...]; files are rewritten in place.
"""

import re
import sys
import xml.etree.ElementTree as ET

GENERIC_MESSAGE = "Encountered an error"
# Lines of a Terraform diagnostic that only point at the source: "on file line N, in ...:",
# "with resource.address,", "  112:   code".
LOCATION_LINE = re.compile(r"^(on |with |\d+:)")


def error_summary(text):
    """Return "<title>: <explanation>" for the first diagnostic in a Terraform error text."""
    lines = text.strip().splitlines()
    title_index = next((i for i, line in enumerate(lines) if line.startswith("Error: ")), None)
    if title_index is None:
        return None
    title = lines[title_index][len("Error: "):].strip()

    explanation = []
    for line in lines[title_index + 1:]:
        if line.startswith("Error: "):  # next diagnostic
            break
        stripped = line.strip()
        if stripped and not LOCATION_LINE.match(stripped) and not line.startswith(" "):
            explanation.append(stripped)
    return f"{title}: {' '.join(explanation)}" if explanation else title


def normalize(path):
    tree = ET.parse(path)
    root = tree.getroot()
    suites = [root] if root.tag == "testsuite" else root.findall("testsuite")

    total = 0.0
    for suite in suites:
        duration = sum(float(case.get("time", 0)) for case in suite.iter("testcase"))
        total += duration
        if suite.get("time") is None:
            suite.set("time", f"{duration:.3f}")

        for error in suite.iter("error"):
            if error.get("message") == GENERIC_MESSAGE and error.text:
                summary = error_summary(error.text)
                if summary:
                    error.set("message", summary)

    if root.tag == "testsuites" and root.get("time") is None:
        root.set("time", f"{total:.3f}")

    tree.write(path, encoding="UTF-8", xml_declaration=True)


def main(paths):
    if not paths:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    for path in paths:
        try:
            normalize(path)
            print(f"Normalized {path}")
        except FileNotFoundError:
            print(f"Skipped {path}: no such file")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
