"""Inspect the actual PyInstaller executable before promoting it to dist."""
from pathlib import Path, PurePosixPath
import re
import sys

from PyInstaller.archive.readers import CArchiveReader


executable = Path(sys.argv[1])
archive = CArchiveReader(str(executable))
names = {name.replace("\\", "/") for name in archive.toc}
for name in names:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or ":" in name:
        raise ValueError("Unsafe archive entry: " + name)
    if re.search(r"\.(?:gguf|onnx|weights|sqlite|sqlite3|db|caf|wav|m4a|pfx|pem|key|p12|pdb)$", name, re.I):
        raise ValueError("Model, personal data or debug file in executable: " + name)
    if any(part.casefold() in {"localminutes.data", "identity", "test-data", "sync-incoming", "sync-outgoing", "rollback", "models"} for part in path.parts):
        raise ValueError("Private data directory in executable: " + name)
    if re.search(r"llama-server|rpc-server|System\.Private\.CoreLib|hostfxr|coreclr|\.csproj$|\.xaml$", name, re.I):
        raise ValueError("Unexpected server or retired .NET payload: " + name)
    if "/" not in name and name.lower().startswith(("cublas", "cudart", "cudnn", "cufft", "nvrtc", "onnxruntime", "llama", "ggml")):
        raise ValueError("Duplicated native tool dependency at the bundle root: " + name)
for expected in ("runtime/llama/llama-completion.exe", "runtime/llama/llama-tokenize.exe", "runtime/llama/llama-fit-params.exe", "runtime/llama/llama-fit-params-impl.dll", "runtime/llama/ggml-cuda.dll",
                 "runtime/llama/llama.dll", "runtime/llama/cudart64_13.dll", "runtime/llama/cublas64_13.dll",
                 "localminutes/resources/SummaryCatalog.json", "localminutes/resources/schema.sql", "licenses/NOTICE.txt",
                 "licenses/NVIDIA-CUDA-EULA.html", "licenses/Qt-LGPL-3.0-only.txt", "licenses/python/Python-LICENSE.txt"):
    if expected not in names:
        raise ValueError("Missing bundled dependency: " + expected)
if not any(re.fullmatch(r"python3\d+\.dll", name) for name in names):
    raise ValueError("Python interpreter is missing.")
if not any(name.endswith("sherpa_onnx/lib/onnxruntime.dll") for name in names):
    raise ValueError("Speech runtime is missing.")
for expected in ("sherpa_onnx/lib/onnxruntime_providers_cuda.dll", "sherpa_onnx/lib/onnxruntime_providers_shared.dll",
                 "nvidia/cuda_runtime/bin/cudart64_12.dll", "nvidia/cublas/bin/cublas64_12.dll", "nvidia/cublas/bin/cublasLt64_12.dll",
                 "nvidia/cufft/bin/cufft64_11.dll", "nvidia/cudnn/bin/cudnn64_9.dll", "nvidia/cuda_nvrtc/bin/nvrtc64_120_0.dll"):
    if expected not in names:
        raise ValueError("CUDA speech dependency is missing: " + expected)
if not any(name.startswith("soxr/") and name.endswith(".pyd") for name in names):
    raise ValueError("Microphone resampling runtime is missing.")
if not any(name.endswith("PySide6/Qt6Widgets.dll") for name in names):
    raise ValueError("Desktop wrapper is missing.")
if not any("pyi-runtime-tmpdir %APPDATA%\\LocalMinutes\\runtime" == option for option in archive.options):
    raise ValueError("Runtime extraction must stay under APPDATA/LocalMinutes/runtime.")
print(f"PASS: {executable.name} embeds {len(names)} Python/UI/CUDA/runtime/license entries; no model weights, meeting data or .NET application.")
