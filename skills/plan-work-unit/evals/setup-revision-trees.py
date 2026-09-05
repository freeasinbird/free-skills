"""Create disposable source repositories for revision-grounding evaluations."""

import json
from pathlib import Path
import subprocess
import tempfile


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], text=True, stderr=subprocess.PIPE
    ).strip()


def write(repo, path, content):
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content)


def verify(repo):
    subprocess.run(
        ["python3", "-m", "unittest", "discover", "-s", "test"], cwd=repo, check=True
    )
    subprocess.run(
        ["python3", "-m", "compileall", "-q", "src", "test"], cwd=repo, check=True
    )


def main():
    root = Path(tempfile.mkdtemp(prefix="planning-revision-eval-"))
    source = root / "controller-source"
    source.mkdir()
    git(source, "init", "-b", "main")
    git(source, "config", "user.name", "Planning Fixture")
    git(source, "config", "user.email", "fixture@example.invalid")
    write(source, ".gitignore", "__pycache__/\n")
    write(source, "src/export/render.py", '''class InvalidDocument(ValueError):
    pass


class LegacyRenderer:
    def draw(self, document):
        if not document:
            raise InvalidDocument("empty")
        return document
''')
    write(source, "test/test_legacy_render.py", '''import sys
import unittest
sys.path.insert(0, "src/export")
from render import InvalidDocument, LegacyRenderer


class RenderTest(unittest.TestCase):
    def test_text(self):
        self.assertEqual(LegacyRenderer().draw("hello"), "hello")

    def test_empty(self):
        with self.assertRaises(InvalidDocument):
            LegacyRenderer().draw("")
''')
    commands = ("Run `python3 -m unittest discover -s test` and "
                "`python3 -m compileall -q src test`.\n"
                "No dependencies, generated files, or separate lint, format, "
                "or build checks.\n")
    write(source, "README.md", "# Renderer\n\nLegacyRenderer.draw(document) returns "
          "a string; empty input raises InvalidDocument.\n\n" + commands)
    verify(source)
    git(source, "add", ".")
    git(source, "commit", "-m", "Create legacy renderer")
    a = git(source, "rev-parse", "HEAD")
    for name in ("unreadable", "advance"):
        target = root / name
        git(root, "clone", "--no-local", str(source), str(target))
        git(target, "remote", "remove", "origin")
    git(source, "rm", "src/export/render.py", "test/test_legacy_render.py")
    write(source, "src/render/service.py", '''from dataclasses import dataclass


class InvalidDocument(ValueError):
    pass


@dataclass
class RenderedDocument:
    text: str


class RenderService:
    def render(self, document):
        if not document:
            raise InvalidDocument("empty")
        return RenderedDocument(document)
''')
    write(source, "test/test_render_service.py", '''import sys
import unittest
sys.path.insert(0, "src/render")
from service import InvalidDocument, RenderedDocument, RenderService


class RenderTest(unittest.TestCase):
    def test_text(self):
        self.assertEqual(RenderService().render("hello"), RenderedDocument("hello"))

    def test_empty(self):
        with self.assertRaises(InvalidDocument):
            RenderService().render("")
''')
    write(source, "README.md", "# Renderer\n\nRenderService.render(document) returns "
          "RenderedDocument; empty input raises InvalidDocument.\n\n" + commands)
    verify(source)
    git(source, "add", ".")
    git(source, "commit", "-m", "Replace renderer with service")
    b = git(source, "rev-parse", "HEAD")
    target = root / "mismatch"
    git(root, "clone", "--no-local", str(source), str(target))
    git(target, "checkout", "--detach", a)
    git(target, "branch", "-f", "main", a)
    git(target, "remote", "remove", "origin")
    for name in ("unreadable", "advance"):
        missing = subprocess.run(
            ["git", "-C", str(root / name), "cat-file", "-e", b],
            capture_output=True,
        )
        if missing.returncode == 0:
            raise RuntimeError(f"{name} fixture unexpectedly contains B")
    manifest = root / "controller.json"
    manifest.write_text(json.dumps({
        "A": a, "B": b,
        "repositories": {name: str(root / name)
                         for name in ("mismatch", "unreadable", "advance")},
    }, indent=2) + "\n")
    print(manifest)


if __name__ == "__main__":
    main()
