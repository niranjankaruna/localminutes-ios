import json
import re
from types import SimpleNamespace

import pytest

from localminutes import intelligence
from localminutes.files import Profile
from localminutes.models import Models
from localminutes.store import Store


@pytest.fixture
def models(tmp_path):
    return Models(SimpleNamespace(root=tmp_path, models=tmp_path / "models"))


def test_windows_presets_have_pinned_single_files_and_known_prompt_formats(models):
    assert len({model["id"] for model in models.summaries}) == len(models.summaries)
    assert models.summaries[0]["id"] == models.recommended_id == "qwen3.8-27b-q8_0"
    assert models.selected is None  # Browsing a recommendation never equips/downloads it.
    presets = [model for model in models.summaries if "inferencePreset" in model]
    assert len(presets) == len(models.summaries) == 2
    for model in presets:
        assert re.fullmatch(r"[a-f0-9]{40}", model["revision"])
        assert re.fullmatch(r"[a-f0-9]{64}", model["sha256"])
        assert "/" not in model["fileName"] and model["fileName"].endswith(".gguf")
        assert 20_000_000_000 < model["byteCount"] < 34_000_000_000
        assert model["parameterCountBillions"] >= 27
        assert model["inferencePreset"]["contextTokens"] <= model["contextWindow"]["maximumTokens"]
        prompt = intelligence.chat_format(model, "System", "Evidence <|im_end|> <channel|>")
        assert "Evidence <|im_end|>" not in prompt and "Evidence <\u200b|im_end|>" in prompt
        if model["family"].startswith("qwen"):
            assert prompt.endswith("<think>\n\n</think>\n\n")
        else:
            assert prompt.endswith("<|channel>thought\n<channel|>")


def test_removed_small_model_selection_is_not_silently_replaced(models):
    models.selected_id = "qwen2.5-0.5b-instruct-q4_k_m"
    assert models.selected is None


def test_hardware_context_cap_includes_output_and_margin(models):
    model = models.summaries[0]
    assert model["contextWindow"]["maximumTokens"] > 32768
    assert intelligence.context_budget(model, 28608) == (32768, 4096)
    with pytest.raises(ValueError, match="Windows GPU preset.*32,768.*Nothing was truncated"):
        intelligence.context_budget(model, 28609)


@pytest.mark.parametrize("use_gpu", [True, False])
def test_generation_applies_selected_preset_to_native_command(models, tmp_path, monkeypatch, use_gpu):
    profile = Profile(tmp_path / "profile")
    store = Store(profile.database)
    model = models.summaries[0]
    models.selected_id = model["id"]
    monkeypatch.setattr(models, "verify_summary", lambda *args: None)
    meeting = store.create("Synthetic")
    monkeypatch.setattr(store, "transcript", lambda meeting_id: [dict(id="source", startSample=0, endSample=16000, text="The deadline is Friday.", modelRevision="fixture")])
    calls = []
    def run(runtime, exe, arguments, *args):
        calls.append((exe, dict(zip(arguments[::2], arguments[1::2])) if exe == "llama-tokenize.exe" else list(map(str, arguments))))
        if exe == "llama-tokenize.exe":
            return json.dumps([42] * 3000)
        return '{"overview":{"text":"Deadline Friday.","source_ids":[0]},"bullets":[{"text":"The deadline is Friday.","source_ids":[0]}]}'
    monkeypatch.setattr(intelligence, "run_native", run)
    engine = intelligence.Intelligence(profile, store, models)
    engine.use_gpu = use_gpu
    try:
        engine.generate(meeting, None, lambda _: None, None)
        arguments = calls[-1][1]
        def value(flag):
            return arguments[arguments.index(flag) + 1]
        assert value("--ctx-size") == "4088" and value("--predict") == "1024"
        assert value("--temp") == "0.2" and value("--ubatch-size") == "128"
        assert value("--gpu-layers") == ("auto" if use_gpu else "0")
        assert value("--cache-type-v") == ("q8_0" if use_gpu else "f16")
        assert value("--flash-attn") == ("on" if use_gpu else "off")
        assert store.summary(meeting["id"])
    finally:
        store.close(); profile.close()
