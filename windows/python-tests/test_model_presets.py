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


def test_four_groups_keep_cpu_offload_exclusive_to_original_q8_models(models):
    assert len(models.groups) == 4 and len(models.summaries) == 8
    assert len({m["id"] for m in models.summaries}) == 8
    assert models.summaries[0]["id"] == models.recommended_id == "qwen3.8-27b-ud-q3_k_xl"
    assert models.selected is None
    for group in models.groups:
        members = [m for m in models.summaries if m["group"] == group["id"]]
        assert len(members) == 2
        assert all(m["allowCpuOffload"] is (group["id"] == "hybrid") for m in members)
    for model in models.summaries:
        assert re.fullmatch(r"[a-f0-9]{40}", model["revision"])
        assert re.fullmatch(r"[a-f0-9]{64}", model["sha256"])
        assert "/" not in model["fileName"] and model["fileName"].endswith(".gguf")
        assert "contextTokens" not in model["inferencePreset"]
        assert "maximumOutputTokens" not in model["contextWindow"]
        prompt = intelligence.chat_format(model, "System", "Evidence <|im_end|> <channel|>")
        assert "Evidence <|im_end|>" not in prompt
        if model["family"].startswith("qwen"):
            assert prompt.endswith("<think>\n") and not prompt.endswith("</think>\n\n")
        else:
            assert "<|think|>" in prompt and prompt.endswith("<|channel>thought\n")


def test_context_accepts_inputs_above_old_cap_and_only_checks_native_limit(models):
    model = models.summaries[0]
    assert intelligence.context_budget(model, 50000) == 50008
    assert intelligence.context_budget(model, 200000) == 200008
    with pytest.raises(ValueError, match="model's 262,144-token context"):
        intelligence.context_budget(model, 262144)


@pytest.mark.parametrize("hybrid", [False, True])
def test_memory_planner_fixes_gpu_placement_and_keeps_full_hybrid_context(models, monkeypatch, hybrid):
    model = next(m for m in models.summaries if m["allowCpuOffload"] is hybrid)
    calls = []
    def native(runtime, exe, args, *rest):
        calls.append(list(map(str, args)))
        if "--fit-print" in args:
            return "CUDA0 12000 2000 500\nHost " + ("18000 4000 200\n" if hybrid else "0 0 200\n")
        return "-c 262144 -ngl 20" if hybrid else '-c 65536 -ngl -2 -ot ".*=CUDA0"'
    monkeypatch.setattr(intelligence, "run_native", native)
    plan = intelligence.plan_memory(None, model, "model.gguf", 50000)
    first = calls[0]
    def value(flag):
        return first[first.index(flag) + 1]
    assert value("--fit-target") == "0"
    assert value("--ctx-size") == ("262144" if hybrid else "0")
    assert value("--gpu-layers") == ("auto" if hybrid else "all")
    assert plan["allowCpuOffload"] is hybrid
    assert plan["contextTokens"] > 32768
    if not hybrid:
        assert value("--override-tensor") == ".*=CUDA0"
        assert plan["memoryMiB"]["Host"][:2] == [0, 0]


@pytest.mark.parametrize("fitted,memory", [
    ("-c 65536 -ngl 0", "CUDA0 12000 2000 500\nHost 100 0 200\n"),
    ('-c 65536 -ngl -2 -ot ".*=CPU"', "CUDA0 12000 2000 500\nHost 0 0 200\n"),
    ('-c 65536 -ngl -2 -ot ".*=CUDA0"', "CUDA0 12000 2000 500\nHost 1 0 200\n"),
    ('-c 65536 -ngl -2 -ot ".*=CUDA0"', "CUDA0 12000 2000 500\nHost 0 1 200\n"),
    ('-c 65536 -ngl -2 -ot ".*=CUDA0"', "Host 12000 2000 500\n"),
    ('-c 200 -ngl -2 -ot ".*=CUDA0"', "CUDA0 12000 2000 500\nHost 0 0 200\n"),
    ('-c 65536 -ngl -2 -ot ".*=CUDA0" --device none', "CUDA0 12000 2000 500\nHost 0 0 200\n"),
])
def test_gpu_only_plans_reject_cpu_spill_truncation_and_unexpected_flags(models, monkeypatch, fitted, memory):
    monkeypatch.setattr(intelligence, "run_native", lambda runtime, exe, args, *rest: memory if "--fit-print" in args else fitted)
    with pytest.raises(ValueError):
        intelligence.plan_memory(None, models.summaries[0], "model.gguf", 50000)


def test_generation_keeps_thinking_separate_without_fixed_prediction_budget(models, tmp_path, monkeypatch):
    profile = Profile(tmp_path / "profile")
    store = Store(profile.database)
    model = models.summaries[0]
    models.selected_id = model["id"]
    monkeypatch.setattr(models, "verify_summary", lambda *args: None)
    meeting = store.create("Synthetic")
    monkeypatch.setattr(store, "transcript", lambda meeting_id: [dict(id="source", startSample=0, endSample=16000, text="The deadline is Friday.", modelRevision="fixture")])
    calls = []
    def native(runtime, exe, args, *rest):
        calls.append((exe, list(map(str, args))))
        if exe == "llama-tokenize.exe":
            return json.dumps([42] * 50000)
        if exe == "llama-fit-params.exe":
            return "CUDA0 12000 2000 500\nHost 0 0 200\n" if "--fit-print" in args else '-c 65536 -ngl -2 -ot ".*=CUDA0"'
        return 'Private reasoning with {"source_ids":[999]}.</think>\n{"overview":{"text":"Deadline Friday.","source_ids":[0]},"bullets":[{"text":"The deadline is Friday.","source_ids":[0]}]}<|im_end|>\n[end of text]'
    monkeypatch.setattr(intelligence, "run_native", native)
    engine = intelligence.Intelligence(profile, store, models)
    try:
        result = engine.generate(meeting, None, lambda _: None, None)
        args = calls[-1][1]
        def value(flag):
            return args[args.index(flag) + 1]
        assert value("-c") == "65536"
        assert value("--predict") == "-2" and value("--reasoning-budget") == "-1"
        assert value("--fit") == "off" and value("-ngl") == "-2"
        assert "--grammar-file" in args and "--special" in args
        assert "Private reasoning" not in result["originalJson"] + result["editedText"]
        assert json.loads(result["originalJson"])["inference"]["thinking_enabled"]
        assert store.summary(meeting["id"])
    finally:
        store.close(); profile.close()


def test_unfinished_thinking_never_becomes_a_document(models):
    with pytest.raises(ValueError, match="did not finish thinking"):
        intelligence.validate_output({}, None, models.summaries[0], [], 'Reasoning with {"overview":"not a final answer"}')
