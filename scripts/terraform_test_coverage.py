#!/usr/bin/env python3
"""Summarise what the Terraform tests cover, as Markdown for the GitHub job summary.

HCL has no line coverage, so this counts what a reviewer can act on: which configurations have
tests, which variables with validation rules have an `expect_failures` run, and which resources,
module calls, outputs, locals and policy documents at least one `assert` condition names. Names are matched as text,
so the last number is approximate. Usage: terraform_test_coverage.py [REPO_ROOT]
"""

import re
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent).resolve()
TERRAFORM = ROOT / "terraform"
TESTS = TERRAFORM / "tests"

HEADER = re.compile(r'\b(resource|data|module|output|variable|locals|run|assert|validation)((?:\s*"[^"\n]*")*)\s*\{')
HEREDOC = re.compile(r"<<-?([A-Za-z_]\w*)\n")
ATTRIBUTE = re.compile(r"(?m)^\s*([A-Za-z_][\w-]*)\s*=(?!=)")
# Data sources that hold BrainTF's own logic; the others (aws_region, aws_kms_alias, ...) are lookups.
COMPUTED_DATA = {"aws_iam_policy_document"}


class Source:
    """An HCL file with comments, strings and heredocs blanked out, so braces can be matched."""

    def __init__(self, path):
        self.text = path.read_text()
        self.clean = blank_strings_and_comments(self.text)
        self.depth, level = [], 0
        for ch in self.clean:
            self.depth.append(level)
            level += {"{": 1, "}": -1}.get(ch, 0)

    def blocks(self, level=0, lo=0, hi=None):
        """Blocks whose header is at brace depth `level` in [lo, hi): (kind, labels, body_lo, body_hi)."""
        found = []
        for m in HEADER.finditer(self.clean, lo, len(self.clean) if hi is None else hi):
            if self.depth[m.start()] != level:
                continue
            opening = m.end() - 1
            closing = next(i for i in range(opening + 1, len(self.clean))
                           if self.clean[i] == "}" and self.depth[i] == level + 1)
            labels = re.findall(r'"([^"]*)"', self.text[m.start(2):m.end(2)])
            found.append((m.group(1), labels, opening + 1, closing))
        return found

    def attributes(self, level, lo, hi):
        return [m.group(1) for m in ATTRIBUTE.finditer(self.clean, lo, hi) if self.depth[m.start(1)] == level]


def blank_strings_and_comments(text):
    """Return text of the same length where comments, heredocs and the contents of strings
    (including ${...} templates) are spaces; the quotes of top-level strings are kept."""
    out, stack, i = list(text), [], 0  # stack: "str", or [depth] for a template inside a string

    def blank(lo, hi):
        for k in range(lo, hi):
            if out[k] != "\n":
                out[k] = " "

    while i < len(text):
        c, before, step = text[i], bool(stack), 1
        if not stack or isinstance(stack[-1], list):
            if c == "#" or text.startswith("//", i) or text.startswith("/*", i):
                end = text.find("*/", i) + 2 if c == "/" and text[i + 1] == "*" else text.find("\n", i)
                end = len(text) if end < 2 else end
                blank(i, end)
                i = end
                continue
            heredoc = HEREDOC.match(text, i) if not stack and c == "<" else None
            if heredoc:
                end = re.compile(rf"(?m)^\s*{heredoc.group(1)}\s*$").search(text, heredoc.end())
                end = end.end() if end else len(text)
                blank(i, end)
                i = end
                continue
            if c == '"':
                stack.append("str")
            elif stack and c == "{":
                stack[-1][0] += 1
            elif stack and c == "}":
                if stack[-1][0]:
                    stack[-1][0] -= 1
                else:
                    stack.pop()
        elif c == "\\":
            step = 2
        elif c == '"':
            stack.pop()
        elif text.startswith(("${", "%{"), i):
            stack.append([0])
            step = 2
        if before and stack:
            blank(i, i + step)
        i += step
    return "".join(out)


def configurations():
    """Root modules and child modules: every directory with .tf files outside terraform/tests."""
    dirs = {p.parent for p in TERRAFORM.rglob("*.tf") if TESTS not in p.parents and ".terraform" not in p.parts}
    return sorted(dirs)


def inventory(directory):
    """Objects an assert can check, and the number of validation rules per variable."""
    objects, rules = set(), {}
    for path in sorted(directory.glob("*.tf")):
        src = Source(path)
        for kind, labels, lo, hi in src.blocks():
            if kind == "resource" and len(labels) == 2:
                objects.add(f"{labels[0]}.{labels[1]}")
            elif kind == "data" and len(labels) == 2 and labels[0] in COMPUTED_DATA:
                objects.add(f"data.{labels[0]}.{labels[1]}")
            elif kind in ("module", "output") and labels:
                objects.add(f"{kind}.{labels[0]}")
            elif kind == "locals":
                objects.update(f"local.{name}" for name in src.attributes(1, lo, hi))
            elif kind == "variable" and labels:
                count = sum(1 for k, *_ in src.blocks(1, lo, hi) if k == "validation")
                if count:
                    rules[labels[0]] = count
    return objects, rules


def runs():
    """Every run block of the test files with the configuration it tests."""
    for path in sorted(TESTS.rglob("*.tftest.hcl")):
        if ".terraform" in path.parts:
            continue
        src = Source(path)
        kind = path.relative_to(TESTS).parts[0]
        for block, _, lo, hi in src.blocks():
            if block != "run":
                continue
            inner = src.blocks(1, lo, hi)
            module = next(((mlo, mhi) for k, labels, mlo, mhi in inner if k == "module" and not labels), None)
            source = module and re.search(r'source\s*=\s*"([^"]+)"', src.text[module[0]:module[1]])
            if not source:
                continue
            expected = re.search(r"expect_failures\s*=\s*\[([^\]]*)\]", src.clean[lo:hi])
            conditions = "\n".join(
                line for k, _, alo, ahi in inner if k == "assert"
                for line in src.text[alo:ahi].splitlines() if not line.strip().startswith("error_message"))
            yield {
                "kind": kind,
                "target": (path.parent / source.group(1)).resolve(),
                "expected": re.findall(r"\bvar\.([\w-]+)", src.text[lo:hi][expected.start(1):expected.end(1)]) if expected else [],
                "conditions": conditions,
            }


def referenced(name, text):
    return re.search(rf"(?<![\w.]){re.escape(name)}\b", text) is not None


def percent(done, total):
    return f"{100 * done // total}%" if total else "–"


def main():
    all_runs = list(runs())
    rows, unchecked, unmatched = [], [], []
    totals = {"configs": [0, 0], "rules": [0, 0], "objects": [0, 0]}

    for directory in configurations():
        name = directory.relative_to(ROOT).as_posix()
        objects, rules = inventory(directory)
        mine = [r for r in all_runs if r["target"] == directory]
        conditions = "\n".join(r["conditions"] for r in mine)
        expected = {v for r in mine for v in r["expected"]}

        checked = {o for o in objects if referenced(o, conditions)}
        tested_rules = set(rules) & expected
        unit = sum(r["kind"] == "unit" for r in mine)
        integration = sum(r["kind"] == "integration" for r in mine)

        totals["configs"][0] += bool(mine)
        totals["configs"][1] += 1
        totals["rules"][0] += len(tested_rules)
        totals["rules"][1] += len(rules)
        totals["objects"][0] += len(checked)
        totals["objects"][1] += len(objects)

        rules_cell = f"{len(tested_rules)}/{len(rules)}" if rules else "–"
        checked_cell = f"{len(checked)}/{len(objects)} ({percent(len(checked), len(objects))})"
        rows.append(f"| `{name}` | {unit} | {integration} | {rules_cell} | {checked_cell} |")
        if mine and objects - checked:
            unchecked.append(f"- `{name}`: " + ", ".join(f"`{o}`" for o in sorted(objects - checked)))
        unmatched += [f"`{name}` `var.{v}`" for v in sorted(expected - set(rules))]

    print("## Terraform test coverage\n")
    print("HCL has no line coverage. These numbers count what the tests name; "
          "*checked* means at least one `assert` condition refers to the object, so it is approximate.\n")
    print("| | Covered | Total | % |\n|---|---|---|---|")
    for label, key in (("Configurations with tests", "configs"),
                       ("Variables with validation rules that have an `expect_failures` run", "rules"),
                       ("Resources, module calls, outputs, locals and policy documents checked by an assert", "objects")):
        done, total = totals[key]
        print(f"| {label} | {done} | {total} | {percent(done, total)} |")

    print("\n| Configuration | Unit runs | Integration runs | Validated variables tested | Checked by asserts |")
    print("|---|---|---|---|---|")
    print("\n".join(rows))

    if unchecked:
        print("\n<details><summary>Not checked by any assert, in configurations that have tests</summary>\n")
        print("\n".join(unchecked))
        print("\n</details>")
    if unmatched:
        print("\nExpected failures on variables without a validation rule (open findings): " + ", ".join(unmatched) + ".")


if __name__ == "__main__":
    main()
