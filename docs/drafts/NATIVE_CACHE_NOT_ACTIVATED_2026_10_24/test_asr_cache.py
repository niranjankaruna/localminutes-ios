"""Real build-cache transport/integrity tests, never inference validation."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("use_asr_only", ROOT / "scripts/use_asr_only.py")
CONSUMER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONSUMER)


def sha(data):
    return hashlib.sha256(data).hexdigest()


class ASRCacheVerificationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = ROOT / ".agent-local/native-cache-tests"
        cls.scratch.mkdir(parents=True, exist_ok=True)
        cls.lock = json.loads((ROOT / "Vendor/SherpaASROnly/artifact-lock.json").read_text())
        cls.delivery = Path(os.environ.get("LOCALMINUTES_ASR_CACHE_FIXTURE",
            ROOT / ".agent-local/asr-native-delivery-40135661801"))
        cls.archive = cls.delivery / cls.lock["archive"]["name"]
        cls.manifest = cls.delivery / cls.lock["manifest"]["name"]
        # Missing/corrupt external artifacts are a harness error, never behavioral
        # RED. The real exact build must exist before these assertions execute.
        for path, expected in [(cls.archive, cls.lock["archive"]), (cls.manifest, cls.lock["manifest"])]:
            data = path.read_bytes()
            if len(data) != expected["sizeBytes"] or sha(data) != expected["sha256"]:
                raise RuntimeError("Exact independently reviewed cache fixture is required")
        with zipfile.ZipFile(cls.archive) as content:
            if content.testzip() is not None:
                raise RuntimeError("Actual build cache has a CRC failure")
            cls.members = {item.filename: content.read(item) for item in content.infolist()}
        if sha(cls.members["SherpaOnnxC.receipt.json"]) != cls.lock["frameworkReceiptSHA256"]:
            raise RuntimeError("Wrong independently reviewed native receipt")

    def mutate(self, directory, change):
        """Re-sign outer transport facts to reach inner adversarial validation.

        These are test copies of the lock/receipt, not edits to trusted pins.
        Real consumer input always uses the committed lock.
        """
        lock = copy.deepcopy(self.lock)
        members = dict(self.members)
        change(members, lock)
        archive = directory / lock["archive"]["name"]
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as output:
            for name, value in members.items():
                if isinstance(value, tuple):
                    output.writestr(value[0], value[1])
                else:
                    output.writestr(name, value)
        data = archive.read_bytes()
        lock["archive"].update(sizeBytes=len(data), sha256=sha(data))
        manifest = json.loads(self.manifest.read_text())
        manifest.update(sha256=sha(data), sizeBytes=len(data))
        manifest_path = directory / lock["manifest"]["name"]
        manifest_data = (json.dumps(manifest, indent=2) + "\n").encode()
        manifest_path.write_bytes(manifest_data)
        lock["manifest"].update(sizeBytes=len(manifest_data), sha256=sha(manifest_data))
        return archive, manifest_path, lock

    def reject_mutation(self, change, message):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temporary:
            archive, manifest, lock = self.mutate(Path(temporary), change)
            with self.assertRaisesRegex(ValueError, message):
                CONSUMER.verify_asr_bundle(archive, manifest, lock)

    def test_actual_reviewed_bundle_accepts_all_five_architecture_slices_and_all_file_hashes(self):
        try:
            receipt = CONSUMER.verify_asr_bundle(self.archive, self.manifest, self.lock)
        except NotImplementedError:
            self.fail("The real, independently reviewed all-platform ASR cache must be accepted and return its verified receipt")
        self.assertEqual(receipt["sourceRevision"], self.lock["sherpaRevision"])
        self.assertEqual(receipt["onnxRuntimeVersion"], "1.28.2")
        self.assertEqual(set(receipt["platforms"]), {"ios", "macos"})
        self.assertEqual(len(receipt["outputFiles"]), 13)

    def test_changed_archive_bytes_rejected_before_unpacking(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temporary:
            path = Path(temporary) / self.archive.name
            data = bytearray(self.archive.read_bytes()); data[-1] ^= 1
            path.write_bytes(data)
            with self.assertRaisesRegex(ValueError, "archive.*SHA"):
                CONSUMER.verify_asr_bundle(path, self.manifest, self.lock)

    def test_wrong_manifest_source_rejected_even_when_its_transport_digest_matches(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temporary:
            lock = copy.deepcopy(self.lock)
            value = json.loads(self.manifest.read_text())
            value["sourceCommit"] = "0" * 40
            data = json.dumps(value).encode()
            path = Path(temporary) / self.manifest.name
            path.write_bytes(data)
            lock["manifest"].update(sizeBytes=len(data), sha256=sha(data))
            with self.assertRaisesRegex(ValueError, "source"):
                CONSUMER.verify_asr_bundle(self.archive, path, lock)

    def test_parent_path_traversal_rejected(self):
        self.reject_mutation(lambda m, _: m.update({"../escape": b"outside"}), "path")

    def test_windows_backslash_and_drive_paths_rejected(self):
        for name in ["..\\escape", "C:/escape", "/escape"]:
            with self.subTest(name=name):
                self.reject_mutation(lambda m, _, n=name: m.update({n: b"outside"}), "path")

    def test_symlink_member_rejected(self):
        def change(members, _):
            item = zipfile.ZipInfo("SherpaOnnxC.xcframework/link")
            item.create_system = 3
            item.external_attr = (stat.S_IFLNK | 0o777) << 16
            members[item.filename] = (item, b"../../escape")
        self.reject_mutation(change, "symlink|regular")

    def test_missing_and_unlisted_files_rejected(self):
        victim = "SherpaOnnxC.xcframework/Info.plist"
        self.reject_mutation(lambda m, _: m.pop(victim), "inventory")
        self.reject_mutation(lambda m, _: m.update({"SherpaOnnxC.xcframework/extra": b"unlisted"}), "inventory")

    def test_changed_binary_rejected_by_receipt_member_hash(self):
        victim = "SherpaOnnxC.xcframework/ios-arm64/SherpaOnnxC.framework/SherpaOnnxC"
        def change(members, _):
            members[victim] = members[victim][:-1] + bytes([members[victim][-1] ^ 1])
        self.reject_mutation(change, "member.*SHA")

    def test_tts_enabled_receipt_rejected_even_with_matching_receipt_digest(self):
        def change(members, lock):
            receipt = json.loads(members["SherpaOnnxC.receipt.json"])
            receipt["platforms"]["ios"]["buildFlags"]["SHERPA_ONNX_ENABLE_TTS"] = "ON"
            data = json.dumps(receipt).encode()
            members["SherpaOnnxC.receipt.json"] = data
            lock["frameworkReceiptSHA256"] = sha(data)
        self.reject_mutation(change, "TTS|flags")

    def test_duplicate_member_rejected(self):
        with tempfile.TemporaryDirectory(dir=self.scratch) as temporary:
            archive, manifest, lock = self.mutate(Path(temporary), lambda _m, _l: None)
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(archive, "a") as output:
                    output.writestr("SherpaOnnxC.receipt.json", self.members["SherpaOnnxC.receipt.json"])
            data = archive.read_bytes()
            lock["archive"].update(sizeBytes=len(data), sha256=sha(data))
            value = json.loads(manifest.read_text()); value.update(sizeBytes=len(data), sha256=sha(data))
            raw = json.dumps(value).encode(); manifest.write_bytes(raw)
            lock["manifest"].update(sizeBytes=len(raw), sha256=sha(raw))
            with self.assertRaisesRegex(ValueError, "duplicate"):
                CONSUMER.verify_asr_bundle(archive, manifest, lock)


if __name__ == "__main__":
    unittest.main()
