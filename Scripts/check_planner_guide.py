#!/usr/bin/env python3
"""Fails when Planner sources change without the Planner's info panel.

Usage: check_planner_guide.py [BASE [HEAD]]   (default: HEAD~1 HEAD)
       check_planner_guide.py --self-test
"""
import subprocess
import sys

GUIDE = "Sources/EVENexusSimpleApp/PlannerFlowGuide.swift"
EXEMPTION = "Planer-Info: geprüft, keine Änderung nötig"
PLANNER_SOURCES = {
    "Sources/EVENexusSimpleApp/PlaceholderViews.swift",
    "Sources/EVENexusSimpleApp/PlannerAutomationViews.swift",
    "Sources/EVENexusCore/Industry/PlannerAutomation.swift",
    "Sources/EVENexusCore/Industry/IndustryPlanner.swift",
    "Sources/EVENexusCore/Industry/PlannerPurchaseBook.swift",
    "Sources/EVENexusCore/Industry/ProductionTree.swift",
    "Sources/EVENexusCore/Industry/ProductionInputParser.swift",
}


def violation(changed_files, commit_messages):
    """Returns the planner files left without a guide update, or an empty list."""
    touched = sorted(PLANNER_SOURCES.intersection(changed_files))
    if not touched or GUIDE in changed_files:
        return []
    if any(EXEMPTION in message for message in commit_messages):
        return []
    return touched


def git(*arguments):
    return subprocess.run(
        ["git", *arguments], check=True, capture_output=True, text=True
    ).stdout


def self_test():
    planner = next(iter(PLANNER_SOURCES))
    assert violation([planner], ["fix"]) == [planner]
    assert violation([planner, GUIDE], ["fix"]) == []
    assert violation([planner], ["fix\n\n" + EXEMPTION]) == []
    assert violation(["README.md"], ["docs"]) == []
    print("check_planner_guide: self-test passed")
    return 0


def main(arguments):
    if arguments == ["--self-test"]:
        return self_test()
    base = arguments[0] if arguments else "HEAD~1"
    head = arguments[1] if len(arguments) > 1 else "HEAD"
    changed = git("diff", "--name-only", base, head).splitlines()
    messages = git("log", "--format=%B%x00", f"{base}..{head}").split("\0")
    touched = violation(changed, messages)
    if not touched:
        print("check_planner_guide: ok")
        return 0
    print("Planner sources changed without updating " + GUIDE + ":")
    for path in touched:
        print("  " + path)
    print(f'Update the panel, or state in a commit message: "{EXEMPTION}"')
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
