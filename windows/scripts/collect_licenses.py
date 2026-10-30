"""Include dependency licenses from the exact wheels used for this build."""
from importlib import metadata
from pathlib import Path
import shutil
import sys


root = Path(__file__).resolve().parents[1]
destination = root / "licenses" / "python"
destination.mkdir(parents=True, exist_ok=True)
packages = ["PySide6-Essentials", "shiboken6", "sherpa-onnx", "sherpa-onnx-core", "sounddevice", "numpy", "cryptography",
            "zeroconf", "qrcode", "ifaddr", "cffi", "pycparser", "colorama", "PyInstaller", "pywin32-ctypes"]
for name in packages:
    package = metadata.distribution(name)
    folder = destination / f"{package.metadata['Name']}-{package.version}"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "METADATA.txt").write_text(package.read_text("METADATA") or "", encoding="utf-8")
    for relative in package.files or []:
        path = Path(str(relative))
        if any(token in path.name.upper() for token in ("LICENSE", "COPYING", "NOTICE")):
            source = Path(package.locate_file(relative))
            if source.is_file():
                target = folder.joinpath(*[part for part in path.parts if part not in ("..", ".")])
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
shutil.copyfile(Path(sys.base_prefix) / "LICENSE.txt", destination / "Python-LICENSE.txt")
for source in (root / ".native" / "llama-cuda").glob("LICENSE*"):
    shutil.copyfile(source, root / "licenses" / source.name)
print("Collected licenses from the pinned Python build environment.")
