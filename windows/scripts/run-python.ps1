[string[]]$pythonArguments=$args
$ErrorActionPreference='Stop'
$windowsRoot=Split-Path -Parent $PSScriptRoot
$python=Join-Path $windowsRoot '.venv/Scripts/python.exe'
if(-not(Test-Path -LiteralPath $python)){throw 'Run windows/scripts/build-cuda.ps1 to prepare the Python environment first.'}
Push-Location $windowsRoot
try { & $python @pythonArguments; $resultCode=$LASTEXITCODE }
finally { Pop-Location }
exit $resultCode
