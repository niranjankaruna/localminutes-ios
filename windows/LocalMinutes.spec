# PyInstaller specification: one executable, no separately installed Python or .NET.
from pathlib import Path
import os
from PyInstaller.utils.hooks import collect_dynamic_libs, copy_metadata

root = Path(SPECPATH)
native = root / '.native' / 'llama-cuda'
names = {'llama.dll', 'llama-common.dll', 'llama-completion-impl.dll', 'mtmd.dll', 'libomp.dll',
         'llama-completion.exe', 'llama-tokenize.exe'}
prefixes = ('ggml', 'cudart', 'cublas', 'msvcp', 'vcruntime', 'concrt')
binaries = [(str(path), 'runtime/llama') for path in native.iterdir()
            if path.is_file() and (path.name in names or (path.suffix == '.dll' and path.name.startswith(prefixes))) and path.name != 'ggml-rpc.dll']
if not any(Path(path).name == 'ggml-cuda.dll' for path, _ in binaries):
    raise ValueError('Run scripts/prepare-native.ps1 before building the CUDA EXE.')
binaries += [(str(path), '.') for path in (root / '.native' / 'vc-runtime').glob('*.dll')]
binaries += collect_dynamic_libs('sherpa_onnx')
datas = [(str(root / 'localminutes' / 'resources'), 'localminutes/resources'),
         (str(root / 'licenses'), 'licenses'), (str(root / 'README.md'), '.')]
for package in ('sherpa-onnx', 'sherpa-onnx-core', 'sounddevice', 'soxr', 'qrcode', 'zeroconf', 'cryptography'):
    datas += copy_metadata(package)

a = Analysis([str(root / 'launch.py')], pathex=[str(root)], binaries=binaries, datas=datas,
             hiddenimports=['sherpa_onnx.lib._sherpa_onnx'], hookspath=[], hooksconfig={}, runtime_hooks=[],
             excludes=['tkinter', 'pytest', 'PySide6.QtWebEngineCore', 'PySide6.QtWebEngineWidgets'], noarchive=False)
# Dependency analysis also finds CLI dependencies at the bundle root. Keep one copy
# beside the native tools; Python itself does not load llama/cuBLAS through ctypes.
native_sources = {Path(source).resolve() for destination, source, kind in a.binaries
                  if destination.replace('\\', '/').startswith('runtime/llama/')}
a.binaries = [entry for entry in a.binaries if not (
    '/' not in entry[0].replace('\\', '/') and entry[0].lower().startswith(('cublas', 'cudart', 'llama', 'ggml'))
    and Path(entry[1]).resolve() in native_sources)]
pyz = PYZ(a.pure)
onefile = os.environ.get('LOCALMINUTES_BUILD_MODE', 'onefile') == 'onefile'
options = dict(name='LocalMinutes-CUDA', debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
               console=False, disable_windowed_traceback=False,
               runtime_tmpdir=r'%APPDATA%\LocalMinutes\runtime', uac_admin=False)
if onefile:
    exe = EXE(pyz, a.scripts, a.binaries, a.datas, [], **options)
else:
    exe = EXE(pyz, a.scripts, [], exclude_binaries=True, **options)
    bundle = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='LocalMinutes-CUDA')
