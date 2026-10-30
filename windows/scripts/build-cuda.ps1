param([string]$PythonPath='python')
$ErrorActionPreference='Stop'
$windowsRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$repositoryRoot=Split-Path -Parent $windowsRoot
$workRoot=Join-Path $windowsRoot '.python-build'
$distRoot=Join-Path $windowsRoot 'dist'
$environmentRoot=Join-Path $windowsRoot '.venv'
$python=Join-Path $environmentRoot 'Scripts/python.exe'

function Assert-OwnedPath([string]$Path,[string]$Owner) {
    $resolved=[IO.Path]::GetFullPath($Path)
    $boundary=[IO.Path]::GetFullPath($Owner).TrimEnd('\')+'\'
    if(-not $resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)){throw 'Build path escaped its owner.'}
    $cursor=$resolved
    while($cursor.Length -ge $boundary.TrimEnd('\').Length) {
        if(Test-Path -LiteralPath $cursor) {
            if(((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Linked build directories are not supported.'}
        }
        $cursor=Split-Path -Parent $cursor
        if(-not $cursor){break}
    }
    return $resolved
}

Assert-OwnedPath $workRoot $windowsRoot | Out-Null
Assert-OwnedPath $distRoot $windowsRoot | Out-Null
New-Item -ItemType Directory -Force -Path $workRoot,$distRoot | Out-Null
$buildLock=[IO.File]::Open((Join-Path $workRoot 'build.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$stage=Assert-OwnedPath (Join-Path $workRoot ([guid]::NewGuid().ToString('N'))) $workRoot
$previousAppData=$env:APPDATA
$previousBuildMode=$env:LOCALMINUTES_BUILD_MODE
$previousCache=$env:PYINSTALLER_CONFIG_DIR
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    if(-not(Test-Path -LiteralPath $python)) {
        & $PythonPath -m venv $environmentRoot
        if($LASTEXITCODE -ne 0){throw 'Install Python 3.12 or newer, or pass -PythonPath with its full path.'}
    }
    & $python -m pip install --disable-pip-version-check --only-binary=:all: --cache-dir (Join-Path $repositoryRoot '.agent-local/pip-cache') -r (Join-Path $windowsRoot 'requirements-build.txt')
    if($LASTEXITCODE -ne 0){throw 'Python dependency installation failed.'}
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare-native.ps1')
    if($LASTEXITCODE -ne 0){throw 'Pinned CUDA runtime preparation failed.'}
    & $python (Join-Path $PSScriptRoot 'collect_licenses.py')
    if($LASTEXITCODE -ne 0){throw 'Dependency license collection failed.'}
    $env:PYINSTALLER_CONFIG_DIR=Join-Path $workRoot 'pyinstaller-cache'
    $env:LOCALMINUTES_BUILD_MODE='onefile'
    $output=Join-Path $stage 'output'
    & $python -m PyInstaller --noconfirm --distpath $output --workpath (Join-Path $stage 'build') (Join-Path $windowsRoot 'LocalMinutes.spec')
    if($LASTEXITCODE -ne 0){throw 'CUDA executable packaging failed.'}
    $executable=Join-Path $output 'LocalMinutes-CUDA.exe'
    $outputs=@(Get-ChildItem -LiteralPath $output -Force)
    if($outputs.Count -ne 1 -or $outputs[0].Name -ne 'LocalMinutes-CUDA.exe'){throw 'Packaging did not produce exactly one EXE.'}
    & $python (Join-Path $PSScriptRoot 'audit_single_exe.py') $executable
    if($LASTEXITCODE -ne 0){throw 'Single-EXE audit failed.'}
    $env:APPDATA=Join-Path $stage 'appdata-test'
    New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
    $resultPath=Join-Path $stage 'self-check.json'
    $profilePath=Join-Path $env:APPDATA 'LocalMinutes'
    $arguments=@('--self-check',('"'+$resultPath+'"'),'--data-directory',('"'+$profilePath+'"'))
    $process=Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    $null=$process.Handle
    if(-not $process.WaitForExit(180000)){$process.Kill();throw 'Packaged EXE self-check timed out.'}
    $checkExitCode=$process.ExitCode
    $process.Dispose()
    if($checkExitCode -ne 0){throw ('Packaged EXE self-check failed. Details: '+$resultPath)}
    $report=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if(-not $report.passed -or -not $report.frozen -or -not $report.cudaBundled){throw 'Packaged Python/CUDA self-check failed.'}
    Assert-OwnedPath $report.runtimeRoot (Join-Path $profilePath 'runtime') | Out-Null
    $env:APPDATA=$previousAppData
    $target=Join-Path $distRoot 'LocalMinutes-CUDA.exe'
    for($attempt=0; ; $attempt++) {
        try {
            if(Test-Path -LiteralPath $target){[IO.File]::Replace($executable,$target,(Join-Path $stage 'previous.exe'))}else{[IO.File]::Move($executable,$target)}
            break
        } catch [IO.IOException] {
            $code=$_.Exception.HResult -band 0xffff
            if($attempt -ge 20 -or $code -notin @(32,33)){throw}
            Start-Sleep -Milliseconds 500
        }
    }
    $digest=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output ('Ready: '+$target)
    Write-Output ('SHA256: '+$digest)
    Write-Output 'One portable CUDA EXE. User data and runtime files stay in %APPDATA%\LocalMinutes.'
} finally {
    $env:APPDATA=$previousAppData
    $env:LOCALMINUTES_BUILD_MODE=$previousBuildMode
    $env:PYINSTALLER_CONFIG_DIR=$previousCache
    $buildLock.Dispose()
    # Failed build evidence is retained outside dist; a successful build removes only this owned staging directory.
    if(Test-Path -LiteralPath (Join-Path $stage 'self-check.json')) {
        $report=Get-Content -LiteralPath (Join-Path $stage 'self-check.json') -Raw | ConvertFrom-Json
        if($report.passed -and -not(Test-Path -LiteralPath (Join-Path $stage 'output/LocalMinutes-CUDA.exe'))) {
            $checkedStage=Assert-OwnedPath $stage $workRoot
            $pending=New-Object 'System.Collections.Generic.Stack[string]';$pending.Push($checkedStage)
            while($pending.Count -gt 0){foreach($entry in Get-ChildItem -LiteralPath $pending.Pop() -Force){if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Unsafe build cleanup entry.'};if($entry.PSIsContainer){$pending.Push($entry.FullName)}}}
            Remove-Item -LiteralPath $checkedStage -Recurse -Force
        }
    }
}
