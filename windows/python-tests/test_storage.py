import threading

import pytest

from localminutes import exchange, library
from localminutes.audio import CaptureWriter, Recorder, Timeline
from localminutes.files import Profile, atomic_write, identifier, json_bytes, safe_path
from localminutes.store import Store


@pytest.fixture
def libraries(tmp_path):
    left, right = Profile(tmp_path / "left"), Profile(tmp_path / "right")
    source, target = Store(left.database), Store(right.database)
    yield left, source, right, target
    source.close(); target.close(); left.close(); right.close()


@pytest.mark.parametrize("path", ["../escape", "/root", "x/../a", "x\\file", "x:stream", "CON", "a/COM1.txt", "a.", "a/", "a//b"])
def test_path_boundary(tmp_path, path):
    with pytest.raises(ValueError):
        safe_path(tmp_path, path)


def test_profile_lock_and_persistent_identity(tmp_path):
    profile = Profile(tmp_path)
    identity, run = profile.identity, profile.run_id
    with pytest.raises((RuntimeError, PermissionError)):
        Profile(tmp_path)
    profile.close()
    again = Profile(tmp_path)
    assert again.identity == identity and again.run_id != run
    again.close()


def test_sender_wins_without_deletions_or_models_and_retry_is_idempotent(libraries, tmp_path):
    left, source, right, target = libraries
    meeting = source.create("Shared")
    target.insert("meeting", meeting)
    local = target.create("Receiver only")
    source.save_note(meeting["id"], "Sender value", 0)
    target.save_note(meeting["id"], "Newer receiver value", 0)
    source.execute("UPDATE manual_notes SET modified_at=100")
    target.execute("UPDATE manual_notes SET modified_at=200")
    (left.models / "private.gguf").write_bytes(b"MODEL MUST NOT SYNC")
    snapshot = tmp_path / "snapshot"
    manifest = exchange.create(left, source, snapshot)
    assert [entry["relativePath"] for entry in manifest["files"]] == ["records.jsonl"]
    result = exchange.apply(right, target, snapshot)
    assert result["notes"] == 1
    assert target.get("note", meeting["id"])["text"] == "Sender value"
    assert target.get("note", meeting["id"])["modifiedAt"] == 100
    assert target.get("meeting", local["id"])
    revision = target.get("note", meeting["id"])["editRevision"]
    assert exchange.apply(right, target, snapshot)["alreadyApplied"]
    assert target.get("note", meeting["id"])["editRevision"] == revision


def test_immutable_conflict_rolls_back_editable_rows(libraries, tmp_path):
    left, source, right, target = libraries
    meeting = source.create("Sender title")
    target.insert("meeting", dict(meeting, title="Receiver title"))
    segment = dict(id=identifier(), meetingId=meeting["id"], sequence=0, startSample=0, endSample=10, text="Original", modelRevision="fixture")
    source.insert("segment", segment)
    target.insert("segment", dict(segment, text="Different original"))
    snapshot = tmp_path / "snapshot"
    exchange.create(left, source, snapshot)
    with pytest.raises(ValueError, match="collision"):
        exchange.apply(right, target, snapshot)
    assert target.get("meeting", meeting["id"])["title"] == "Receiver title"


def test_original_audio_round_trip(libraries, tmp_path):
    left, source, right, target = libraries
    meeting = source.create("Audio")
    writer = CaptureWriter(left.meeting_dir(meeting["id"]), meeting["id"])
    audio = b"\x01\x00\xff\x7f" * 200
    writer.append(audio)
    writer.finish()
    source.finish(meeting["id"], len(audio) // 2)
    snapshot = tmp_path / "snapshot"
    exchange.create(left, source, snapshot)
    exchange.apply(right, target, snapshot)
    assert b"".join(Timeline(right.meeting_dir(meeting["id"])).chunks()) == audio


def test_interrupted_import_recovers_media(libraries):
    _, _, right, target = libraries
    transfer, meeting = identifier(), identifier()
    relative = f"Meetings/{meeting}/recovery-report.json"
    path = safe_path(right.library, relative)
    backup = safe_path(right.root, f"rollback/{transfer}/{relative}")
    atomic_write(path, b"changed")
    atomic_write(backup, b"original")
    atomic_write(right.root / "pending-import.json", json_bytes(dict(transferId=transfer, digest="a" * 64, replaced=[relative], added=[])))
    exchange.recover(right, target)
    assert path.read_bytes() == b"original"


def test_local_delete_finishes_after_restart(libraries):
    _, _, right, target = libraries
    meeting = target.create("Remove me")
    directory = right.meeting_dir(meeting["id"])
    directory.mkdir()
    (directory / "segment-000000.caf").write_bytes(b"synthetic")
    atomic_write(right.root / "deletions" / (meeting["id"] + ".json"), json_bytes(meeting["id"]))
    library.recover_deletions(right, target)
    assert target.get("meeting", meeting["id"]) is None and not directory.exists()


def test_cancelled_snapshot_is_not_sealed(libraries, tmp_path):
    left, source, _, _ = libraries
    source.create("Synthetic")
    cancel = threading.Event(); cancel.set()
    snapshot = tmp_path / "cancelled"
    with pytest.raises(InterruptedError):
        exchange.create(left, source, snapshot, cancel)
    assert not (snapshot / "manifest.json").exists()


def test_microphone_stop_failure_still_drains_and_releases_worker(libraries):
    profile, store, _, _ = libraries
    recorder = Recorder(profile, store, None)
    recorder.meeting_id = store.create("Interrupted device", "recording")["id"]
    closed = threading.Event()
    class DisconnectedMicrophone:
        def stop(self):
            raise OSError("Device disconnected")
        def close(self):
            closed.set()
    recorder.stream = DisconnectedMicrophone()
    worker = threading.Thread(target=lambda: recorder.stopping.wait(3))
    recorder.worker = worker; worker.start()
    with pytest.raises(RuntimeError, match="Device disconnected"):
        recorder.stop()
    assert not worker.is_alive() and not recorder.active and closed.is_set()
    assert store.get("meeting", recorder.meeting_id)["recordingState"] == "interrupted"
