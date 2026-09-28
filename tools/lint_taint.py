"""Reject addon code that writes into or hooks Blizzard's objects, or runs Blizzard code whose state it would taint.

Forever runs Blizzard's UI through secure delegates. A method an addon hooked or replaced on a Blizzard object,
a field it wrote there, or a lazy cache Blizzard first built from addon code, then fails or is blocked inside
Blizzard's own calls, blamed on this addon. See AGENTS.md for the ways to hook that stay clean.
"""

import re
import sys
from pathlib import Path

from tools.lint_multivalue import Token, tokenize
from tools.typecheck_coverage import runtime_files

# Globals this addon owns. Every other global root is Blizzard's (or another addon's).
OWN = re.compile(
    r"(?:Tweaks|SkillUp|Legacy|ShortestPath|AdventureGuide|WorkOrders)Forever\w*|WOF_\w+|SLASH_\w+|SlashCmdList"
)

# Blizzard functions that must only run from Blizzard's code: layout that writes its frames' state, lazy caches
# built on first call, and links other Blizzard code reads.
CALLS = {
    "SetModuleContainer": "registering addon modules taints Blizzard tracker layout",
    "UpdateFrameSize": "bag layout writes the bag's state",
    "UpdateItemLayout": "bag layout builds the bag's item cache",
    "UpdateContainerFrameAnchors": "bag anchoring builds the shown-bags cache",
    "UpdateUIPanelPositions": "panel layout writes the panel manager's state",
    "GetBagsShown": "lazy cache of shown bags",
    "EnumerateValidItems": "lazy cache of a bag's items",
    "GetBagSize": "lazy cache of a bag's size",
    "GetRows": "reads the lazy bag size cache",
    "ContainerFrameUtil_EnumerateContainerFrames": "lazy cache of bag frames",
    "SetParentInitializer": "the settings search reads this link",
    "AddMaskableTexture": "writes into the map canvas's texture list",
    "UpdateAnchors": "nameplate layout writes the plate's state",
}


def flagged(comments: dict[int, str], line: int) -> bool:
    return not re.fullmatch(r"taint-ok:\s*\S.*", comments.get(line, ""))


def locals_of(tokens: list[Token]) -> tuple[set[str], set[str]]:
    """Names bound by local, for or function parameters anywhere in the file, and those bound to a new table."""
    names: set[str] = {"ns", "self", "_G"}
    tables: set[str] = {"ns"}
    for index, token in enumerate(tokens):
        if token.value == "local" and tokens[index + 1].value == "function":
            names.add(tokens[index + 2].value)
        elif token.value in {"local", "for"}:
            cursor = index + 1
            bound = []
            while tokens[cursor].kind == "name":
                bound.append(tokens[cursor].value)
                if tokens[cursor + 1].value != ",":
                    break
                cursor += 2
            names.update(bound)
            if token.value == "local" and len(bound) == 1 and tokens[cursor + 1].value == "=":
                if tokens[cursor + 2].value == "{":
                    tables.add(bound[0])
        elif token.value == "function":
            cursor = index + 1
            while tokens[cursor].value != "(":
                cursor += 1
            cursor += 1
            while tokens[cursor].value != ")":
                if tokens[cursor].kind == "name":
                    names.add(tokens[cursor].value)
                cursor += 1
    return names, tables


def chain_end(tokens: list[Token], index: int) -> int:
    """Index just past `root(.name|[expr])*` starting at the root name at `index`."""
    cursor = index + 1
    while True:
        if tokens[cursor].value == "." and tokens[cursor + 1].kind == "name":
            cursor += 2
        elif tokens[cursor].value == "[":
            depth = 0
            while True:
                depth += tokens[cursor].value == "["
                depth -= tokens[cursor].value == "]"
                cursor += 1
                if depth == 0:
                    break
        else:
            return cursor


def check(source: str) -> list[tuple[int, str]]:
    comments: dict[int, str] = {}
    tokens, _ = tokenize(source, comments=comments)
    names, tables = locals_of(tokens)
    findings: list[tuple[int, str]] = []

    def report(line: int, message: str) -> None:
        if flagged(comments, line):
            findings.append((line, message))

    headers: set[int] = set()
    for index, token in enumerate(tokens):
        previous = tokens[index - 1].value if index else ""
        if token.value == "function" and tokens[index + 1].kind == "name":
            # A named definition: its name chain is not a call, and a Blizzard root is a replaced method.
            cursor = index + 1
            while tokens[cursor].value != "(":
                headers.add(cursor)
                cursor += 1
            root = tokens[index + 1]
            if cursor > index + 2 and root.value not in names and not OWN.fullmatch(root.value):
                report(root.line, f"taint-blizzard-write: defines a method on Blizzard's {root.value}")
            continue
        if token.kind != "name" or index in headers:
            continue
        if token.value == "hooksecurefunc" and tokens[index + 1].value == "(":
            first = tokens[index + 2]
            if first.kind != "string" and not (first.value in tables and tokens[index + 3].value == ","):
                report(token.line, "taint-method-hook: hooksecurefunc on an object; hook a script or an event")
        elif token.value in CALLS and tokens[index + 1].value == "(" and previous != "function":
            report(token.line, f"taint-blizzard-call: {token.value} ({CALLS[token.value]})")
        elif previous not in {".", ":"} and token.value not in names and not OWN.fullmatch(token.value):
            end = chain_end(tokens, index)
            if end > index + 1 and tokens[end].value == "=":
                report(token.line, f"taint-blizzard-write: writes a field of Blizzard's {token.value}")
    return findings


def main() -> int:
    paths = [Path(arg) for arg in sys.argv[1:]] or runtime_files(Path.cwd().resolve())
    failed = False
    for path in paths:
        try:
            findings = check(path.read_text())
        except (ValueError, OSError) as error:
            print(f"{path}: {error}", file=sys.stderr)
            failed = True
            continue
        for line, message in findings:
            print(f"{path}:{line}: {message}")
            failed = True
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
