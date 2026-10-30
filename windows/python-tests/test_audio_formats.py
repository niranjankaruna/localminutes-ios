from types import SimpleNamespace

import numpy as np
import pytest
import sounddevice as sd

from localminutes import audio
from localminutes.files import Profile
from localminutes.store import Store


@pytest.mark.parametrize("rate,channels", [(44100, 1), (48000, 2), (8000, 1), (16000, 1)])
def test_microphone_conversion_preserves_duration_and_speech_band(rate, channels):
    samples = np.rint(12000 * np.sin(2 * np.pi * 1000 * np.arange(int(rate * 1.137)) / rate)).astype("<i2")
    source = np.repeat(samples[:, None], channels, axis=1).tobytes()
    converter = audio.MicrophonePCM(rate, channels)
    width = 137 * 2 * channels  # Deliberately not a whole resampling ratio.
    output = b"".join(converter.convert(source[i:i + width]) for i in range(0, len(source), width))
    output += converter.convert(b"", last=True)
    result = np.frombuffer(output, dtype="<i2").astype(np.float64)
    assert abs(len(result) - len(samples) * audio.RATE / rate) <= 1
    expected = 12000 * np.sin(2 * np.pi * 1000 * np.arange(len(result)) / audio.RATE)
    assert np.sqrt(np.mean((result[100:-100] - expected[100:-100]) ** 2)) < 30


def test_downsampling_filters_frequencies_that_would_alias_into_speech():
    samples = np.rint(12000 * np.sin(2 * np.pi * 14000 * np.arange(48000) / 48000)).astype("<i2")
    result = np.frombuffer(audio.MicrophonePCM(48000, 1).convert(samples.tobytes(), last=True), dtype="<i2").astype(float)
    assert np.sqrt(np.mean(result[100:-100] ** 2)) < 30


def test_recording_negotiates_stereo_48k_and_drains_resampler_tail(tmp_path, monkeypatch):
    monkeypatch.setattr(sd, "query_devices", lambda *args: {"max_input_channels": 2, "default_samplerate": 48000})
    def check(**kwargs):
        if kwargs["samplerate"] != 48000 or kwargs["channels"] != 2:
            raise sd.PortAudioError("Invalid sample rate", -9997)
    monkeypatch.setattr(sd, "check_input_settings", check)
    monkeypatch.setattr(audio, "open_recognizer", lambda *args: object())
    monkeypatch.setattr(audio, "recognize", lambda recognizer, pcm: "Synthetic speech")
    source = np.full((300000, 2), 1234, dtype="<i2").tobytes()  # 6.25 seconds
    opened = {}
    class Microphone:
        def __init__(self, **kwargs):
            opened.update(kwargs)
        def start(self):
            for i in range(0, len(source), 4800 * 4):
                opened["callback"](source[i:i + 4800 * 4], min(4800, (len(source) - i) // 4), None, None)
        def stop(self):
            opened["finished_callback"]()
        def close(self):
            opened["closed"] = True
    monkeypatch.setattr(sd, "RawInputStream", Microphone)
    profile = Profile(tmp_path / "profile")
    store = Store(profile.database)
    recorder = audio.Recorder(profile, store, SimpleNamespace(verify_speech=lambda cancel: None, speech_directory=tmp_path, speech_revision="fixture"))
    try:
        recorder.start(7)
        recorder.stop()
        meeting = store.get("meeting", recorder.meeting_id)
        timeline = audio.Timeline(profile.meeting_dir(recorder.meeting_id))
        assert opened["samplerate"] == 48000 and opened["channels"] == 2 and opened["closed"]
        assert meeting["recordingState"] == "completed"
        assert meeting["capturedSampleCount"] == timeline.frames == 100000
        assert len(b"".join(timeline.chunks())) == 200000
        assert [(s["startSample"], s["endSample"]) for s in store.transcript(recorder.meeting_id)] == [(0, 80000), (80000, 100000)]
    finally:
        if recorder.active:
            recorder.stop()
        store.close(); profile.close()


def test_microphone_list_prefers_microphone_and_excludes_system_loopback(monkeypatch):
    monkeypatch.setattr(sd, "query_devices", lambda: [dict(name=name, max_input_channels=2) for name in ("Stereo Mix", "Line In", "Microphone", "Headset")])
    devices = audio.Recorder.microphones()
    assert {name for _, name in devices} == {"Line In", "Microphone", "Headset"}
    assert devices[0][1] in {"Microphone", "Headset"}
