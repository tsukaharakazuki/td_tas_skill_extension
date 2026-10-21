#!/usr/bin/env python3
"""Create a local Project/<slug> from this skill's bundled project template.

Use ``python3 -I`` to avoid importing modules from a workspace or template.
This command never invokes Treasure Data, Git, or a network client.
"""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import sys


SLUG = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}\Z", re.ASCII)
EXCLUDED_NAMES = {
    ".git", ".hg", ".svn", ".venv", "venv", "env", "__pycache__",
    ".env", "secret", "secrets", ".secrets", "credentials", ".aws", ".ssh", ".td", ".tdx",
}


def check_path(path):
    """Reject traversal and existing symlinks in a path, including its parents."""
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("paths must be absolute and must not contain '..'")
    for part in reversed((path,) + tuple(path.parents)):
        if part.is_symlink():
            raise ValueError("symlinks are not allowed: {}".format(part))


def excluded(relative):
    for part in relative.parts:
        lower = part.lower()
        if (lower in EXCLUDED_NAMES
                or lower.startswith((".env", "secret.", "secrets.", ".secrets.", "credentials."))
                or lower.endswith((".pem", ".key", ".p12", ".pfx"))):
            return True
    return False


def walk_error(error):
    raise error


def template_entries(template):
    """Preflight the entire source tree before creating anything at all."""
    check_path(template)
    if not template.is_dir():
        raise ValueError("project template is missing: {}".format(template))
    entries = []
    for directory, directories, files in os.walk(template, followlinks=False, onerror=walk_error):
        for name in sorted(directories + files):
            source = Path(directory) / name
            mode = source.lstat().st_mode
            if stat.S_ISLNK(mode):
                raise ValueError("template contains a symlink: {}".format(source))
            if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError("template contains a nonregular entry: {}".format(source))
            relative = source.relative_to(template)
            if not excluded(relative):
                entries.append((source, relative, stat.S_ISDIR(mode)))
    memory = template / "MEMORY.md"
    if not memory.is_file():
        raise ValueError("template must supply the project's MEMORY.md")
    return sorted(entries, key=lambda item: (len(item[1].parts), str(item[1])))


def index_plan(index, name):
    """Read, but never replace, an existing project index."""
    check_path(index)
    if index.exists() and not index.is_file():
        raise ValueError("project index is not a regular file: {}".format(index))
    existing = index.read_text(encoding="utf-8") if index.exists() else ""
    pointer = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(name) + r"/MEMORY\.md(?=[)#\s]|$)")
    if pointer.search(existing):
        return ""
    prefix = "" if not existing or existing.endswith("\n") else "\n"
    return prefix + "- [{0}]({0}/MEMORY.md)\n".format(name)


def initialize(workspace, name, dry_run=False):
    if not SLUG.fullmatch(name):
        raise ValueError("--name must be a 1-64 character lowercase ASCII slug: [a-z0-9][a-z0-9_-]*")
    check_path(workspace)
    if not workspace.is_dir():
        raise ValueError("--workspace must be an existing directory")
    root = workspace / "Project"
    project = root / name
    check_path(project)
    if root.exists() and not root.is_dir():
        raise ValueError("Project exists but is not a directory")
    if project.exists():
        raise ValueError("project already exists; refusing to overwrite: {}".format(project))
    template = Path(__file__).absolute().parent.parent / "templates" / "project"
    entries = template_entries(template)
    index = root / "MEMORY.md"
    addition = index_plan(index, name)
    empty_directories = ("dashboard_output", "dashboard_template", "runs")
    for relative in empty_directories:
        source = template / relative
        if source.exists() and not source.is_dir():
            raise ValueError("template output path must be a directory: {}".format(source))
    print("{} project: {}".format("Would create" if dry_run else "Create", project))
    for _, relative, is_directory in entries:
        print("  {} {}".format("directory" if is_directory else "copy", project / relative))
    for relative in empty_directories:
        print("  ensure directory {}".format(project / relative))
    print("  {} index {}".format("append project pointer to" if addition else "keep existing", index))
    if dry_run:
        print("Dry run: no directories or files were created or changed.")
        return project
    root.mkdir(exist_ok=True)
    project.mkdir()  # No exist_ok: concurrent initialization must not overwrite a project.
    for source, relative, is_directory in entries:
        destination = project / relative
        if is_directory:
            destination.mkdir(exist_ok=True)
        else:
            # Recheck after preflight; never intentionally dereference a source link.
            if source.is_symlink():
                raise ValueError("template changed to a symlink: {}".format(source))
            shutil.copyfile(source, destination, follow_symlinks=False)
    for relative in empty_directories:
        (project / relative).mkdir(exist_ok=True)
    check_path(index)
    # Reinspect just before appending, preserving all preexisting index content.
    addition = index_plan(index, name)
    if addition or not index.exists():
        flags = os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0)
        with os.fdopen(os.open(index, flags, 0o644), "a", encoding="utf-8") as stream:
            stream.write(addition)
    print("Project MEMORY: {}".format(project / "MEMORY.md"))
    print("Project index: {}".format(index))
    print("README: {}".format(project / "README.md"))
    print("Next: review config/project.json and the adapters, then validate locally.")
    return project


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True, help="existing absolute workspace directory")
    parser.add_argument("--name", required=True, help="lowercase ASCII project slug (maximum 64 characters)")
    parser.add_argument("--dry-run", action="store_true", help="print the plan without creating or writing anything")
    arguments = parser.parse_args(argv)
    try:
        initialize(arguments.workspace, arguments.name, arguments.dry_run)
    except (OSError, UnicodeError, ValueError) as error:
        print("ERROR: {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
