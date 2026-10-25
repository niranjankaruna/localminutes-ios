"""Audit real unsigned IPA bytes; no synthetic binary establishes delivery proof.

Required environment: LOCALMINUTES_AUDIT_IPA, LOCALMINUTES_AUDIT_SOURCE_COMMIT,
LOCALMINUTES_AUDIT_IPA_SHA256. Missing or corrupt inputs fail setup.
This test does not extract or modify the archive, strip code or change licenses.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import subprocess
import unittest
import zipfile


REPOSITORY = Path(__file__).resolve().parents[2]
MAX_IPA_BYTES = 512 * 1024 * 1024
MAX_ENTRY_BYTES = 128 * 1024 * 1024
MAX_TOTAL_BYTES = 512 * 1024 * 1024
APP = "Payload/LocalMinutes.app"
EXTENSION = APP + "/PlugIns/LocalMinutesLiveActivity.appex"
MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
    b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xce",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
    b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bounded_json(path):
    with path.open("rb") as handle:
        data = handle.read(65_537)
    require(len(data) <= 65_536, "Package receipt exceeds its bound")
    return json.loads(data)


def sha256_file(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def validate_canonical_archive_names(names):
    # Keep the established exact app/extension path and traversal rules. Archive
    # names are passed as JSON data on stdin, never interpolated into shell/code.
    script = """
import { validateArchiveEntries } from './scripts/ios-artifacts.mjs';
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
validateArchiveEntries(JSON.parse(Buffer.concat(chunks).toString('utf8')));
"""
    subprocess.run(["node", "--input-type=module", "-e", script], cwd=REPOSITORY,
                   input=json.dumps(names), text=True, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)


def defined_symbols(binary):
    """Bounded Mach-O64/fat symbol-table parser; exclude STAB and imports.

    N_SECT, N_ABS and N_INDR are definitions. Undefined/common imports and
    prebound undefined records cannot establish embedded implementation proof.
    """
    magic = binary[:4]
    fat_layouts = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
                   b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if magic in fat_layouts:
        endian, wide = fat_layouts[magic]
        require(len(binary) >= 8, "Truncated universal Mach-O header")
        count = struct.unpack_from(endian + "I", binary, 4)[0]
        stride = 32 if wide else 20
        require(1 <= count <= 16 and 8 + count * stride <= len(binary), "Invalid universal slice table")
        ranges = []
        result = []
        for index in range(count):
            cursor = 8 + index * stride
            if wide:
                cpu, subtype, offset, size, align, _ = struct.unpack_from(endian + "iiQQII", binary, cursor)
            else:
                cpu, subtype, offset, size, align = struct.unpack_from(endian + "iiIII", binary, cursor)
            require(size > 0 and offset >= 8 + count * stride and offset + size <= len(binary), "Invalid Mach-O slice bounds")
            require(align <= 30 and offset % (1 << align) == 0, "Invalid Mach-O slice alignment")
            require(all(offset + size <= start or offset >= end for start, end in ranges), "Overlapping Mach-O slices")
            ranges.append((offset, offset + size))
            values = defined_symbols(binary[offset:offset + size])
            require(all(arch == cpu for arch, _ in values), "Mach-O architecture disagrees with universal table")
            result.extend(values)
        return result
    require(magic in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"), "Expected a supported64-bit device Mach-O")
    endian = "<" if magic == b"\xcf\xfa\xed\xfe" else ">"
    require(len(binary) >= 32, "Truncated Mach-O64 header")
    _, cpu, _, _, commands, command_bytes, _, _ = struct.unpack_from(endian + "IiiIIIII", binary)
    require(0 < commands <= 4096 and command_bytes <= len(binary) - 32, "Invalid Mach-O load commands")
    cursor = 32
    command_end = cursor + command_bytes
    symbol_table = None
    for _ in range(commands):
        require(cursor + 8 <= command_end, "Truncated Mach-O load command")
        command, size = struct.unpack_from(endian + "II", binary, cursor)
        require(size >= 8 and size % 4 == 0 and cursor + size <= command_end, "Invalid Mach-O command size")
        if command == 2:  # LC_SYMTAB
            require(size == 24 and symbol_table is None, "Invalid/duplicate Mach-O symbol table")
            symbol_table = struct.unpack_from(endian + "IIII", binary, cursor + 8)
        cursor += size
    require(cursor == command_end and symbol_table is not None, "A real symbol table is required; absent symbols are not proof")
    symbol_offset, symbol_count, string_offset, string_size = symbol_table
    require(0 <= symbol_count <= 2_000_000 and symbol_offset + symbol_count * 16 <= len(binary), "Invalid Mach-O symbol bounds")
    # Some embedded system/runtime slices legitimately have a stripped empty
    # table. They contribute no definition records; the main executable must
    # independently retain actual named CPU ASR definitions below.
    if symbol_count == 0:
        require(string_offset + string_size <= len(binary), "Invalid empty-table string bounds")
        return []
    require(string_size > 0 and string_offset + string_size <= len(binary), "Invalid Mach-O string bounds")
    strings = binary[string_offset:string_offset + string_size]
    result = []
    for index in range(symbol_count):
        name_index, kind, section, _, _ = struct.unpack_from(endian + "IBBHQ", binary, symbol_offset + index * 16)
        if kind & 0xE0 or (kind & 0x0E) not in (0x02, 0x0A, 0x0E):
            continue
        if kind & 0x0E == 0x0E:
            require(section != 0, "A section-defined symbol must identify its section")
        if name_index == 0:
            continue
        require(name_index < string_size, "Mach-O symbol name exceeds string table")
        end = strings.find(b"\0", name_index)
        require(end >= name_index, "Unterminated Mach-O symbol name")
        result.append((cpu, strings[name_index:end].decode("utf-8")))
    return result


def forbidden_tts_symbol(name):
    # Anchored namespaces avoid false matches against legitimate ASR classes
    # such as OfflineSpeaker...; this is not a case-insensitive string scan.
    return name.startswith("_espeak") or name.startswith("_piper_") or bool(
        re.match(r"^__Z(?:N[KVRO]*5piper|T[VIS]N5piper)", name))


class ActualIPANativeHygieneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ipa = Path(os.environ["LOCALMINUTES_AUDIT_IPA"]).resolve(strict=True)
        cls.source = os.environ["LOCALMINUTES_AUDIT_SOURCE_COMMIT"]
        cls.expected_digest = os.environ["LOCALMINUTES_AUDIT_IPA_SHA256"]
        require(re.fullmatch(r"[0-9a-f]{40}", cls.source) is not None, "Expected source must be an immutable SHA")
        require(re.fullmatch(r"[0-9a-f]{64}", cls.expected_digest) is not None, "Expected IPA digest must be SHA256")
        require(cls.ipa.is_file() and cls.ipa.stat().st_size <= MAX_IPA_BYTES, "Invalid/big IPA input")
        cls.receipt = bounded_json(cls.ipa.parent / "build-manifest.json")
        require(cls.receipt["sourceCommit"] == cls.source and cls.receipt["sha256"] == cls.expected_digest,
                "Wrong source/artifact receipt: setup cannot establish RED")
        require(cls.receipt["artifact"] == cls.ipa.name and cls.receipt["sizeBytes"] == cls.ipa.stat().st_size,
                "Wrong artifact identity/length")
        require(sha256_file(cls.ipa) == cls.expected_digest, "Actual delivered IPA checksum differs")
        cls.symbols = {}
        cls.bundle_sources = []
        with zipfile.ZipFile(cls.ipa) as archive:
            entries = archive.infolist()
            require(0 < len(entries) <= 4096, "Unexpected archive entry count")
            validate_canonical_archive_names([entry.filename for entry in entries])
            seen_casefold = set()
            total = 0
            for entry in entries:
                name = entry.filename.rstrip("/")
                require(name.casefold() not in seen_casefold, "Case-colliding/duplicate ZIP entry")
                seen_casefold.add(name.casefold())
                require(not entry.flag_bits & 1, "Encrypted archive input is unsupported")
                require(entry.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), "Unsupported archive compression")
                mode = stat.S_IFMT(entry.external_attr >> 16)
                require(mode in (0, stat.S_IFDIR, stat.S_IFREG), "Links/special archive entries are forbidden")
                require(mode != stat.S_IFDIR or entry.is_dir(), "Directory mode disagrees with ZIP path")
                require(0 <= entry.file_size <= MAX_ENTRY_BYTES, "Oversized native archive entry")
                total += entry.file_size
                require(total <= MAX_TOTAL_BYTES, "Archive expansion exceeds bound")
            for entry in entries:
                if entry.is_dir():
                    continue
                # ZipFile.read verifies actual CRC. No member is extracted.
                data = archive.read(entry)
                require(len(data) == entry.file_size, "ZIP member length mismatch")
                if entry.filename in (APP + "/Info.plist", EXTENSION + "/Info.plist"):
                    require(len(data) <= 262_144, "Oversized product plist")
                    cls.bundle_sources.append(plistlib.loads(data)["LocalMinutesSourceCommit"])
                if data[:4] in MACHO_MAGICS:
                    cls.symbols[entry.filename] = defined_symbols(data)
        require(APP + "/LocalMinutes" in cls.symbols, "The real main device executable was not inspected")
        require(EXTENSION + "/LocalMinutesLiveActivity" in cls.symbols, "The real embedded extension was not inspected")

    def test_01_actual_delivered_source_and_receipt_are_the_audited_build(self):
        self.assertEqual(self.bundle_sources, [self.source, self.source])
        self.assertEqual(self.receipt["signing"], "unsigned")

    def test_02_actual_binary_retains_defined_cpu_streaming_asr_entrypoints(self):
        actual = {name for _, name in self.symbols[APP + "/LocalMinutes"]}
        required = {"_SherpaOnnxCreateOnlineRecognizer", "_SherpaOnnxOnlineStreamAcceptWaveform",
                    "_SherpaOnnxDecodeOnlineStream", "_SherpaOnnxGetOnlineStreamResult"}
        self.assertTrue(required <= actual, "Removing symbols indiscriminately cannot establish an ASR-only build")

    def test_03_actual_device_binaries_define_no_unused_espeak_or_piper_implementation(self):
        unexpected = sorted({(path, name) for path, values in self.symbols.items()
                             for _, name in values if forbidden_tts_symbol(name)})
        self.assertEqual(unexpected, [],
            "Delivered Mach-O contains defined unused TTS implementation symbols (non-STAB, not imports):\n"
            + "\n".join(path + ": " + name for path, name in unexpected))


if __name__ == "__main__":
    unittest.main(verbosity=2)
