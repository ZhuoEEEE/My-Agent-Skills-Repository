#!/usr/bin/env python3
"""Initialize and maintain a versioned multi-topic Playground workspace."""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path


VERSION = "1"
MARKER_PREFIX = "playground-workspace-init"
TOPIC_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}-.+")
TOPIC_MARKER_PATTERN = re.compile(
    rf'<!-- {re.escape(MARKER_PREFIX)}:topic version="[^"]+" -->'
)
LOCK_NAME = ".playground-workspace-init.lock"
SKILL_ROOT = Path(__file__).resolve().parent.parent


class UnmanagedFileError(RuntimeError):
    """Raised when an existing file needs a semantic merge."""


def asset_path(name: str) -> Path:
    return SKILL_ROOT / "assets" / name


def read_asset(name: str) -> str:
    return asset_path(name).read_text(encoding="utf-8")


def normalize_newlines(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(text, encoding="utf-8", newline="\n")
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def block_pattern(name: str) -> re.Pattern[str]:
    prefix = re.escape(MARKER_PREFIX)
    block = re.escape(name)
    return re.compile(
        rf"<!-- {prefix}:{block}:start version=\"[^\"]+\" -->.*?"
        rf"<!-- {prefix}:{block}:end -->",
        re.DOTALL,
    )


def extract_block(template: str, name: str) -> str:
    match = block_pattern(name).search(template)
    if not match:
        raise RuntimeError(f"Template is missing managed block: {name}")
    return match.group(0)


def contains_block(text: str, name: str) -> bool:
    return block_pattern(name).search(text) is not None


def block_count(text: str, name: str) -> int:
    return len(block_pattern(name).findall(text))


def merge_blocks(existing: str, template: str, names: list[str]) -> str:
    merged = normalize_newlines(existing).rstrip()
    for name in names:
        replacement = extract_block(template, name)
        pattern = block_pattern(name)
        if pattern.search(merged):
            merged = pattern.sub(lambda _: replacement, merged, count=1)
        else:
            merged = f"{merged}\n\n{replacement}" if merged else replacement
    return f"{merged.rstrip()}\n"


def render_topic_index(workspace: Path) -> str:
    topics: list[str] = []
    for path in workspace.iterdir():
        readme = path / "README.md"
        if (
            path.is_dir()
            and TOPIC_PATTERN.fullmatch(path.name)
            and readme.is_file()
            and TOPIC_MARKER_PATTERN.search(readme.read_text(encoding="utf-8"))
        ):
            topics.append(path.name)
    topics.sort()
    if not topics:
        return "No topic directories yet."
    return "\n".join(f"- [{name}]({name}/)" for name in topics)


def render_workspace_readme(workspace: Path) -> str:
    return read_asset("workspace-README.md").replace(
        "{{TOPIC_INDEX}}", render_topic_index(workspace)
    )


def preflight_managed_file(path: Path, required_blocks: list[str]) -> None:
    if not path.exists():
        return
    if not path.is_file():
        raise RuntimeError(f"Expected a file but found another object: {path}")
    existing = path.read_text(encoding="utf-8")
    duplicates = [name for name in required_blocks if block_count(existing, name) > 1]
    if duplicates:
        joined = ", ".join(duplicates)
        raise RuntimeError(f"Duplicate managed block(s) in {path}: {joined}")
    if not any(contains_block(existing, name) for name in required_blocks):
        raise UnmanagedFileError(str(path))


def update_managed_file(path: Path, template: str, block_names: list[str]) -> str:
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        duplicates = [name for name in block_names if block_count(existing, name) > 1]
        if duplicates:
            joined = ", ".join(duplicates)
            raise RuntimeError(f"Duplicate managed block(s) in {path}: {joined}")
        if not any(contains_block(existing, name) for name in block_names):
            raise UnmanagedFileError(f"Semantic merge required: {path}")
        updated = merge_blocks(existing, template, block_names)
        action = "updated" if normalize_newlines(existing) != updated else "unchanged"
    else:
        updated = f"{normalize_newlines(template).rstrip()}\n"
        action = "created"
    if action != "unchanged":
        atomic_write(path, updated)
    return action


@contextmanager
def workspace_lock(workspace: Path, timeout_seconds: float = 10.0):
    lock_path = workspace / LOCK_NAME
    deadline = time.monotonic() + timeout_seconds
    descriptor = None
    while descriptor is None:
        try:
            descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(descriptor, f"pid={os.getpid()}\ntime={time.time()}\n".encode())
        except FileExistsError:
            try:
                if time.time() - lock_path.stat().st_mtime > 60:
                    lock_path.unlink()
                    continue
            except FileNotFoundError:
                continue
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Timed out waiting for workspace lock: {lock_path}")
            time.sleep(0.05)
    try:
        yield
    finally:
        os.close(descriptor)
        try:
            lock_path.unlink()
        except FileNotFoundError:
            pass


def require_workspace(path_text: str) -> Path:
    workspace = Path(path_text).expanduser().resolve()
    if not workspace.exists():
        raise RuntimeError(f"Workspace does not exist: {workspace}")
    if not workspace.is_dir():
        raise RuntimeError(f"Workspace is not a directory: {workspace}")
    if workspace == SKILL_ROOT:
        raise RuntimeError("Refusing to initialize the Skill installation directory")
    return workspace


def init_workspace(workspace: Path) -> int:
    agents_path = workspace / "AGENTS.md"
    readme_path = workspace / "README.md"
    management_dir = workspace / "workspace-management"
    management_path = management_dir / "README.md"
    if management_dir.exists() and not management_dir.is_dir():
        raise RuntimeError(f"Expected a directory but found another object: {management_dir}")
    checks = [
        (agents_path, ["rules"]),
        (readme_path, ["overview", "topic-index"]),
        (management_path, ["workspace-management"]),
    ]

    unmanaged: list[str] = []
    for path, blocks in checks:
        try:
            preflight_managed_file(path, blocks)
        except UnmanagedFileError:
            unmanaged.append(str(path))
    if unmanaged:
        print("Semantic merge required before initialization:", file=sys.stderr)
        for path in unmanaged:
            print(f"- {path}", file=sys.stderr)
        print("No files were changed.", file=sys.stderr)
        return 2

    agents_template = read_asset("AGENTS.md")
    readme_template = render_workspace_readme(workspace)
    management_template = read_asset("workspace-management-README.md")

    with workspace_lock(workspace):
        results = [
            (
                agents_path,
                update_managed_file(agents_path, agents_template, ["rules"]),
            ),
            (
                readme_path,
                update_managed_file(
                    readme_path,
                    readme_template,
                    ["overview", "topic-index"],
                ),
            ),
            (
                management_path,
                update_managed_file(
                    management_path,
                    management_template,
                    ["workspace-management"],
                ),
            ),
        ]
    for path, action in results:
        print(f"{action}: {path}")
    print(f"Playground workspace specification version: {VERSION}")
    return 0


def assert_initialized(workspace: Path) -> None:
    agents_path = workspace / "AGENTS.md"
    readme_path = workspace / "README.md"
    if not agents_path.is_file() or not contains_block(
        agents_path.read_text(encoding="utf-8"), "rules"
    ):
        raise RuntimeError("Workspace is not initialized: managed AGENTS.md block missing")
    if not readme_path.is_file() or not contains_block(
        readme_path.read_text(encoding="utf-8"), "topic-index"
    ):
        raise RuntimeError("Workspace is not initialized: managed topic index missing")


def refresh_index(workspace: Path) -> int:
    assert_initialized(workspace)
    readme_path = workspace / "README.md"
    with workspace_lock(workspace):
        action = update_managed_file(
            readme_path,
            render_workspace_readme(workspace),
            ["overview", "topic-index"],
        )
    print(f"{action}: {readme_path}")
    return 0


def valid_date(value: str) -> str:
    try:
        return datetime.strptime(value, "%Y-%m-%d").date().isoformat()
    except ValueError as error:
        raise argparse.ArgumentTypeError("date must use YYYY-MM-DD") from error


def create_topic(
    workspace: Path, date_text: str | None, conversation_id: str | None
) -> int:
    assert_initialized(workspace)
    now = datetime.now().astimezone()
    creation_date = date_text or now.date().isoformat()
    base_name = f"{creation_date}-undetermined-topic"

    suffix = 1
    while True:
        name = base_name if suffix == 1 else f"{base_name}-{suffix}"
        topic_path = workspace / name
        try:
            topic_path.mkdir()
            break
        except FileExistsError:
            suffix += 1

    try:
        topic_readme = (
            read_asset("topic-README.md")
            .replace("{{CREATED_DATE}}", creation_date)
            .replace("{{CREATED_TIME}}", now.isoformat(timespec="seconds"))
            .replace("{{CONVERSATION_ID}}", conversation_id or "Unavailable")
            .replace("{{INITIAL_DIRECTORY}}", name)
        )
        atomic_write(topic_path / "README.md", topic_readme)
        refresh_index(workspace)
    except Exception:
        readme_path = topic_path / "README.md"
        if readme_path.exists():
            readme_path.unlink()
        topic_path.rmdir()
        raise

    print(f"created topic: {topic_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init", help="initialize or upgrade a workspace")
    init_parser.add_argument("workspace")

    topic_parser = subparsers.add_parser("create-topic", help="create a new topic directory")
    topic_parser.add_argument("workspace")
    topic_parser.add_argument("--date", type=valid_date)
    topic_parser.add_argument("--conversation-id")

    index_parser = subparsers.add_parser("refresh-index", help="refresh the root topic index")
    index_parser.add_argument("workspace")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        workspace = require_workspace(args.workspace)
        if args.command == "init":
            return init_workspace(workspace)
        if args.command == "create-topic":
            return create_topic(workspace, args.date, args.conversation_id)
        return refresh_index(workspace)
    except (OSError, RuntimeError, UnicodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
