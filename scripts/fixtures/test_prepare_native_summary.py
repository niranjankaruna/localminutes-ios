"""Offline safety checks for the optional, pinned native source extraction."""
import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile


SPEC = importlib.util.spec_from_file_location(
    "prepare_native_summary", Path(__file__).with_name("prepare_native_summary.py"))
PREPARER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARER)


class NativeSummarySourceExtractionTests(unittest.TestCase):
    def make_archive(self, root, name, payload=b"fixture", mode=None):
        archive = root / "source.zip"
        with zipfile.ZipFile(archive, "w") as output:
            entry = zipfile.ZipInfo(name)
            # Preserve the requested on-wire spelling: ZipInfo otherwise
            # normalizes backslashes before writing on Windows.
            entry.filename = name
            if mode is not None:
                entry.external_attr = mode << 16
            output.writestr(entry, payload)
        return archive

    def test_extracts_regular_source_under_exact_pinned_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.make_archive(root, "llama.cpp-b11900/include/llama.h")
            destination = root / "source"
            PREPARER.extract_source(archive, destination, root)
            self.assertEqual((destination / "include/llama.h").read_bytes(), b"fixture")

    def test_rejects_parent_traversal_and_different_source_root(self):
        for name in ("llama.cpp-b11900/../escaped", "llama.cpp-main/include/llama.h",
                     "llama.cpp-b11900/evil\\path", "llama.cpp-b11900/null\0suffix"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = self.make_archive(root, name)
                with self.assertRaises(ValueError):
                    PREPARER.extract_source(archive, root / "source", root)
                self.assertFalse((root / "escaped").exists())

    def test_rejects_source_symlinks(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = self.make_archive(root, "llama.cpp-b11900/link", b"../../escape",
                                        stat.S_IFLNK | 0o777)
            with self.assertRaises(ValueError):
                PREPARER.extract_source(archive, root / "source", root)

    def test_refuses_to_replace_directory_outside_fixture_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            allowed = root / "fixtures"
            allowed.mkdir()
            outside = root / "keep"
            outside.mkdir()
            (outside / "important").write_bytes(b"keep")
            archive = self.make_archive(root, "llama.cpp-b11900/include/llama.h")
            with self.assertRaises(ValueError):
                PREPARER.extract_source(archive, outside, allowed)
            self.assertEqual((outside / "important").read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
