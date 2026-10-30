from __future__ import annotations

from pathlib import Path
import queue
import re
import struct
import threading
import time

import numpy as np
import sounddevice as sd
import soxr

from .files import atomic_write, check_cancel, identifier, json_bytes, read_json, require_regular, safe_path


RATE = 16000
SEGMENT_BYTES = RATE * 2 * 60


def caf_header(size: int) -> bytes:
    return (struct.pack(">4sHH4sq", b"caff", 1, 0, b"desc", 32)
            + struct.pack(">d4sIIIII", RATE, b"lpcm", 2, 2, 1, 1, 16)
            + struct.pack(">4sqI", b"data", size + 4 if size >= 0 else -1, 0))


def inspect_caf(path: Path) -> tuple[int, int]:
    require_regular(path)
    with path.open("rb") as stream:
        header = stream.read(8)
        if len(header) != 8 or header[:6] != b"caff\x00\x01":
            raise ValueError("Unsupported CAF header.")
        length = path.stat().st_size
        described = False
        audio = None
        while stream.tell() < length:
            chunk = stream.read(12)
            if len(chunk) != 12:
                raise ValueError("Incomplete CAF chunk.")
            kind, size = struct.unpack(">4sq", chunk)
            if size < 0 or size > length - stream.tell():
                raise ValueError("Incomplete CAF audio segment.")
            end = stream.tell() + size
            if kind == b"desc":
                if described or size != 32 or struct.unpack(">d4sIIIII", stream.read(32)) != (RATE, b"lpcm", 2, 2, 1, 1, 16):
                    raise ValueError("Expected mono 16 kHz signed 16-bit PCM CAF.")
                described = True
            elif kind == b"data":
                if not described or audio is not None or size < 4 or (size - 4) % 2:
                    raise ValueError("Invalid CAF audio region.")
                audio = (stream.tell() + 4, size - 4)
            stream.seek(end)
    if audio is None:
        raise ValueError("CAF has no audio data.")
    return audio


class CaptureWriter:
    def __init__(self, directory: Path, meeting_id: str):
        self.directory = require_regular(directory)
        directory.mkdir(parents=True, exist_ok=True)
        if any(directory.iterdir()):
            raise ValueError("Recording folder already contains data.")
        self.meeting_id = identifier(meeting_id)
        self.segments = []
        self.total = 0
        self.current = None
        self.size = 0

    def append(self, pcm: bytes) -> None:
        if len(pcm) % 2:
            raise ValueError("Incomplete PCM sample.")
        offset = 0
        while offset < len(pcm):
            if self.current is None:
                self.current = (self.directory / f"segment-{len(self.segments):06}.caf").open("xb")
                self.current.write(caf_header(-1))
                self.size = 0
            count = min(SEGMENT_BYTES - self.size, len(pcm) - offset)
            self.current.write(pcm[offset:offset + count])
            offset += count
            self.size += count
            self.total += count // 2
            if self.size == SEGMENT_BYTES:
                self.close_segment()

    def close_segment(self) -> None:
        import os
        if self.current is None:
            return
        self.current.seek(56)
        self.current.write(struct.pack(">q", self.size + 4))
        self.current.flush()
        os.fsync(self.current.fileno())
        self.current.close()
        self.current = None
        self.segments.append(dict(relativePath=f"segment-{len(self.segments):06}.caf", startFrame=self.total - self.size // 2, frameCount=self.size // 2))
        atomic_write(self.directory / "capture-manifest.json", json_bytes(self.manifest()))

    def manifest(self) -> dict:
        return dict(schemaVersion=1, sessionID=self.meeting_id, totalFrames=self.total, segments=list(self.segments))

    def finish(self) -> dict:
        self.close_segment()
        return self.manifest()


class Timeline:
    def __init__(self, directory: Path):
        manifest = read_json(safe_path(directory, "capture-manifest.json"))
        if manifest["schemaVersion"] != 1 or type(manifest["totalFrames"]) is not int or manifest["totalFrames"] < 0:
            raise ValueError("Invalid capture manifest.")
        identifier(manifest["sessionID"])
        self.entries = []
        previous = 0
        for segment in manifest["segments"]:
            start, count = segment["startFrame"], segment["frameCount"]
            if type(start) is not int or type(count) is not int or start < previous or not 0 <= count <= 960000:
                raise ValueError("Invalid audio timeline.")
            if not re.fullmatch(r"(?:RecoveryQuarantine/)?segment-\d{6}\.caf", segment["relativePath"]):
                raise ValueError("Invalid recording segment name.")
            path = safe_path(directory, segment["relativePath"])
            offset, size = inspect_caf(path)
            if size != count * 2:
                raise ValueError("Audio sample count does not match its manifest.")
            self.entries.append((start, start + count, path, offset))
            previous = start + count
        if previous != manifest["totalFrames"]:
            raise ValueError("Audio duration does not match its manifest.")
        self.frames = previous

    def chunks(self, start=0):
        position = max(0, min(start, self.frames))
        for begin, end, path, offset in self.entries:
            if end <= position:
                continue
            while position < begin:
                count = min(1600, begin - position)
                yield bytes(count * 2)
                position += count
            with path.open("rb") as stream:
                stream.seek(offset + (position - begin) * 2)
                while position < end:
                    count = min(1600, end - position)
                    data = stream.read(count * 2)
                    if len(data) != count * 2:
                        raise ValueError("Recording changed during playback.")
                    yield data
                    position += count


def open_recognizer(directory: Path, cancel=None, runtime_directory=None):
    from .speech_client import CudaSpeechRecognizer
    return CudaSpeechRecognizer(directory, cancel, runtime_directory)


def recognize(recognizer, pcm: bytes) -> str:
    return recognizer.transcribe(pcm)


def microphone_format(device):
    """Negotiate the device format; Parakeet's rate is not a hardware requirement."""
    info = sd.query_devices(device, "input")
    channels = list(dict.fromkeys((1, min(2, info["max_input_channels"]))))
    rates = list(dict.fromkeys((RATE, int(info["default_samplerate"]), 48000, 44100, 8000)))
    for rate in rates:
        for count in channels:
            if count < 1:
                continue
            try:
                sd.check_input_settings(device=device, channels=count, dtype="int16", samplerate=rate)
                return rate, count
            except sd.PortAudioError:
                continue
    raise ValueError("This microphone has no supported recording format. Select another microphone in Record or check its Windows sound settings.")


class MicrophonePCM:
    """Stateful, band-limited conversion to the shared 16 kHz mono PCM format."""
    def __init__(self, rate, channels):
        self.channels = channels
        self.resampler = soxr.ResampleStream(rate, RATE, 1, dtype="int16", quality="HQ") if rate != RATE else None

    def convert(self, pcm: bytes, *, last=False) -> bytes:
        if len(pcm) % (2 * self.channels):
            raise ValueError("Incomplete microphone frame.")
        samples = np.frombuffer(pcm, dtype="<i2")
        if self.channels > 1:
            samples = np.rint(samples.reshape(-1, self.channels).astype(np.float32).mean(axis=1)).astype(np.int16)
        if self.resampler:
            samples = self.resampler.resample_chunk(samples, last=last)
        return samples.astype("<i2", copy=False).tobytes()


class Recorder:
    def __init__(self, profile, store, models, changed=lambda text: None):
        self.profile, self.store, self.models = profile, store, models
        self.changed = changed
        self.stream = None
        self.worker = None
        self.meeting_id = None
        self.error = None
        self.started = 0.0
        self.frames = 0
        self.user_stopping = False
        self.stopping = threading.Event()

    @property
    def active(self):
        return self.worker is not None

    @staticmethod
    def microphones():
        devices = [(i, device["name"]) for i, device in enumerate(sd.query_devices())
                   if device["max_input_channels"] > 0 and not any(name in device["name"].casefold() for name in ("stereo mix", "loopback", "what u hear"))]
        # Do not default to a system-audio loopback or a disconnected line input.
        return sorted(devices, key=lambda device: (not any(name in device[1].casefold() for name in ("microphone", "headset")), device[0] != sd.default.device[0]))

    def start(self, device: int, cancel=None):
        if self.active:
            raise ValueError("A recording is already active.")
        rate, channels = microphone_format(device)
        converter = MicrophonePCM(rate, channels)
        self.models.verify_speech(cancel)
        recognizer = open_recognizer(self.models.speech_directory, cancel, self.profile.root / "runtime" / "speech")
        check_cancel(cancel)
        meeting = self.store.create("Meeting " + time.strftime("%d %b %H:%M"), "recording")
        self.meeting_id = meeting["id"]
        writer = CaptureWriter(self.profile.meeting_dir(self.meeting_id), self.meeting_id)
        chunks = queue.Queue(maxsize=600)
        self.stopping.clear()
        self.error = None
        self.frames = 0
        self.user_stopping = False

        def finished():
            if not self.user_stopping and not self.stopping.is_set():
                self.error = RuntimeError("The microphone stopped unexpectedly.")
            self.stopping.set()

        def callback(data, frames, timing, status):
            if self.stopping.is_set():
                raise sd.CallbackStop
            if status:
                self.error = RuntimeError("The microphone could not deliver continuous audio.")
                self.stopping.set()
                raise sd.CallbackAbort
            try:
                chunks.put_nowait(bytes(data))
            except queue.Full:
                self.error = RuntimeError("Audio processing could not keep up. Recording stopped.")
                self.stopping.set()
                raise sd.CallbackAbort

        def work():
            window = bytearray()
            sequence = 0
            def decode(data):
                nonlocal sequence
                text = recognize(recognizer, bytes(data))
                if text:
                    self.store.insert("segment", dict(id=identifier(), meetingId=self.meeting_id, sequence=sequence,
                        startSample=writer.total - len(data) // 2, endSample=writer.total, text=text,
                        modelRevision="parakeet-v3-cuda@" + self.models.speech_revision))
                    self.changed(text)
                sequence += 1
            def save(data):
                # Split after resampling so every transcript timestamp uses the
                # same exact sample clock as the saved audio, including the tail.
                offset = 0
                while offset < len(data):
                    count = min(160000 - len(window), len(data) - offset)
                    part = data[offset:offset + count]
                    writer.append(part)
                    self.frames = writer.total
                    window.extend(part)
                    offset += count
                    if len(window) == 160000:
                        if self.error is None:
                            try:
                                decode(window)
                            except Exception as error:
                                self.error = error
                                self.stopping.set()
                        window.clear()
            try:
                while not self.stopping.is_set() or not chunks.empty():
                    try:
                        data = chunks.get(timeout=0.1)
                    except queue.Empty:
                        continue
                    save(converter.convert(data))
                save(converter.convert(b"", last=True))
                if window and self.error is None:
                    decode(window)
            except Exception as error:
                self.error = error
                self.stopping.set()
            finally:
                if hasattr(recognizer, "close"):
                    try:
                        recognizer.close()
                    except Exception as error:
                        self.error = self.error or error
                try:
                    manifest = writer.finish()
                    self.store.finish(self.meeting_id, manifest["totalFrames"], "interrupted" if self.error else "completed")
                except Exception as error:
                    self.error = error
                if self.error:
                    self.changed("Recording interrupted. Saved original audio is retained.")

        try:
            self.stream = sd.RawInputStream(device=device, channels=channels, samplerate=rate, dtype="int16", blocksize=round(rate / 10),
                                            callback=callback, finished_callback=finished, latency="high")
            self.worker = threading.Thread(target=work, name="meeting-capture", daemon=True)
            self.worker.start()
            self.started = time.monotonic()
            self.stream.start()
        except BaseException:
            self.stopping.set()
            if self.worker:
                self.worker.join()
            if self.stream:
                self.stream.close()
            self.stream = self.worker = None
            if hasattr(recognizer, "close"):
                recognizer.close()
            self.store.finish(self.meeting_id, writer.total, "failed")
            raise

    def stop(self):
        if not self.active:
            return
        self.user_stopping = True
        try:
            if self.stream:
                try:
                    self.stream.stop()
                except Exception as error:
                    self.error = self.error or error
            self.stopping.set()
            self.worker.join()
        finally:
            if self.stream:
                self.stream.close()
            self.stream = self.worker = None
        if self.error:
            self.store.finish(self.meeting_id, self.frames, "interrupted")
            raise RuntimeError("Recording saved with an interruption: " + str(self.error))


class Playback:
    def __init__(self):
        self.cancel = threading.Event()
        self.worker = None

    def play(self, directory: Path, start=0, failed=lambda text: None):
        self.stop()
        timeline = Timeline(directory)
        self.cancel.clear()
        def run():
            try:
                with sd.RawOutputStream(samplerate=RATE, channels=1, dtype="int16") as output:
                    for chunk in timeline.chunks(start):
                        if self.cancel.is_set():
                            break
                        output.write(chunk)
            except Exception as error:
                failed(str(error))
        self.worker = threading.Thread(target=run, name="meeting-playback", daemon=True)
        self.worker.start()

    def stop(self):
        self.cancel.set()
        if self.worker:
            self.worker.join()
            self.worker = None


def reconcile_recordings(profile, store):
    for meeting in store.meetings():
        if meeting["recordingState"] == "recording":
            frames = meeting["capturedSampleCount"]
            try:
                frames = max(frames, Timeline(profile.meeting_dir(meeting["id"])).frames)
            except (OSError, ValueError, KeyError):
                pass
            store.finish(meeting["id"], frames, "interrupted")
