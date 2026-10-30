"""Fetch only the three pinned, public CC-BY-4.0 audio clips; never models.

Temporary signed audio URLs are resolved in memory and never saved or printed.
The tracked manifest is the authority for references and exact original bytes.
"""
import hashlib
import json
from pathlib import Path
import re
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "Tests/Fixtures/ASRQualityCorpus.json"
OUTPUT = ROOT / ".agent-local/asr-quality-corpus"


def read_public(url, limit):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "datasets-server.huggingface.co" or parsed.username or parsed.password:
        raise ValueError("Unexpected public dataset host")
    with urllib.request.urlopen(url, timeout=30) as response:
        final = urllib.parse.urlsplit(response.geturl())
        if final.scheme != "https" or final.hostname != "datasets-server.huggingface.co":
            raise ValueError("Unexpected dataset redirect")
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Dataset response exceeds declared byte bound")
    return data


def verify_audio(raw, clip):
    if len(raw) != clip["bytes"] or hashlib.sha256(raw).hexdigest() != clip["sha256"]:
        raise ValueError("Pinned public audio digest or size mismatch")
    if not raw.startswith(b"fLaC") or raw[4] & 127 != 0 or int.from_bytes(raw[5:8], "big") != 34:
        raise ValueError("Expected native FLAC STREAMINFO")
    packed = int.from_bytes(raw[18:26], "big")
    actual = (packed >> 44, ((packed >> 41) & 7) + 1, ((packed >> 36) & 31) + 1, packed & ((1 << 36) - 1))
    expected = tuple(clip[key] for key in ["sampleRate", "channels", "bitsPerSample", "sampleFrames"])
    if actual != expected:
        raise ValueError("Pinned FLAC stream metadata mismatch")


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert manifest["dataset"] == "openslr/librispeech_asr" and manifest["config"] == "all"
    assert manifest["split"] == "test.clean" and manifest["license"] == "CC-BY-4.0"
    assert manifest["publisher"] == "https://www.openslr.org/12/"
    assert len(manifest["clips"]) == 3
    assert sum(c["sampleFrames"] for c in manifest["clips"]) == 733600
    assert not (ROOT / ".agent-local").is_symlink() and not OUTPUT.is_symlink()
    assert OUTPUT.resolve().is_relative_to(ROOT.resolve())
    assert OUTPUT.resolve().is_relative_to((ROOT / ".agent-local").resolve())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for clip in manifest["clips"]:
        assert re.fullmatch(r"[0-9]+-[0-9]+-[0-9]+", clip["id"])
        assert 0 < clip["bytes"] < 2_000_000
        destination = OUTPUT / (clip["id"] + ".flac")
        assert not destination.is_symlink()
        if destination.exists():
            assert destination.stat().st_size == clip["bytes"]
            verify_audio(destination.read_bytes(), clip)
            print("Verified cached licensed clip " + clip["id"])
            continue
        query = urllib.parse.urlencode(dict(dataset=manifest["dataset"], config=manifest["config"],
            split=manifest["split"], offset=clip["rowOffset"], length=1))
        metadata = json.loads(read_public("https://datasets-server.huggingface.co/rows?" + query, 64_000))
        assert len(metadata["rows"]) == 1
        item = metadata["rows"][0]
        assert item["row_idx"] == clip["rowOffset"] and not item["truncated_cells"]
        row = item["row"]
        assert row["id"] == clip["id"] and row["text"] == clip["text"]
        assert len(row["audio"]) == 1 and row["audio"][0]["type"] == "audio/flac"
        source = row["audio"][0]["src"]
        assert "/--/" + manifest["datasetRevision"] + "/--/" in urllib.parse.urlsplit(source).path
        raw = read_public(source, clip["bytes"])
        verify_audio(raw, clip)
        temporary = destination.with_suffix(".pending")
        assert not temporary.is_symlink()
        temporary.write_bytes(raw)
        temporary.replace(destination)
        print("Prepared licensed clip " + clip["id"])
    print("LOCALMINUTES_ASR_CORPUS_DIRECTORY=" + str(OUTPUT))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # urllib errors can contain signed URLs; log only the public-safe type.
        raise SystemExit("Corpus preparation failed: " + type(error).__name__) from None
