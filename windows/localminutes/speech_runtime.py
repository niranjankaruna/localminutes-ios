"""Load app-local CUDA speech libraries; model placement is audited in the worker."""
from pathlib import Path
import ctypes
import os
import sys
import threading

from .files import atomic_write

_handles = []
_lock = threading.Lock()


def prepare_cuda(config_directory: Path) -> str:
    with _lock:
        if not _handles:
            import sherpa_onnx
            package = Path(sherpa_onnx.__file__).parent
            base = Path(sys._MEIPASS) if getattr(sys, "frozen", False) else package.parent
            directories = [base / "nvidia" / name / "bin" for name in ("cuda_runtime", "cuda_nvrtc", "cublas", "cufft", "cudnn")]
            directories.append(package / "lib")
            handles = []
            previous_path = os.environ.get("PATH", "")
            try:
                # cuDNN's internal component loader uses legacy LoadLibrary,
                # which also needs the app-local directories on this process PATH.
                os.environ["PATH"] = os.pathsep.join(map(str, directories)) + os.pathsep + os.environ.get("PATH", "")
                for directory in directories:
                    handles.append(os.add_dll_directory(str(directory)))
                driver = ctypes.WinDLL("nvcuda.dll")
                if driver.cuInit(0) != 0:
                    raise OSError("NVIDIA CUDA could not initialize.")
                handles.append(driver)
                for directory, name in ((directories[0], "cudart64_12.dll"),
                                        (directories[2], "cublasLt64_12.dll"), (directories[2], "cublas64_12.dll"),
                                        (directories[3], "cufft64_11.dll"), (directories[4], "cudnn64_9.dll")):
                    handles.append(ctypes.WinDLL(str(directory / name)))
                # ORT must initialize its provider host before loading the CUDA EP.
                # Preload NVIDIA dependencies only; ORT loads its own provider DLLs.
                for name in ("onnxruntime_providers_shared.dll", "onnxruntime_providers_cuda.dll"):
                    if not (directories[5] / name).is_file():
                        raise OSError("CUDA execution provider is missing.")
            except OSError as error:
                os.environ["PATH"] = previous_path
                for handle in handles:
                    if hasattr(handle, "close"):
                        handle.close()
                raise RuntimeError("CUDA speech could not start. Check the NVIDIA driver and use the complete CUDA executable. CPU fallback is disabled.") from error
            _handles.extend(handles)
    config = config_directory / "parakeet-cuda.config"
    # ORT requires CPU shape/index bookkeeping for this export. The worker
    # checks every CPU-assigned node against the audited metadata-only allowlist.
    atomic_write(config, b"LogSeverityLevel=0\n")
    return "cuda:" + str(config)
