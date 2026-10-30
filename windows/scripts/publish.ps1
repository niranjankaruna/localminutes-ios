param([ValidateSet('cpu','cuda')][string]$Backend='cpu')
$ErrorActionPreference='Stop'
$windowsRoot=Split-Path -Parent $PSScriptRoot
$repositoryRoot=Split-Path -Parent $windowsRoot
$runtime=Join-Path $windowsRoot ('.native/llama-'+$Backend)
if(-not(Test-Path -LiteralPath (Join-Path $runtime 'llama-completion.exe'))){throw 'Run scripts/prepare-native.ps1 first.'}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare-native.ps1') -Backend $Backend
if($LASTEXITCODE -ne 0){throw 'Pinned native dependency preparation failed.'}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$name='LocalMinutes-Windows-x64-'+$Backend+'-'+$stamp
$destination=Join-Path $windowsRoot ('dist/'+$name)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'dotnet.ps1') publish src/LocalMinutes.Desktop/LocalMinutes.Desktop.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:NativeBackend=$Backend -o $destination
if($LASTEXITCODE -ne 0){throw 'Publish failed.'}
Copy-Item -LiteralPath (Join-Path $windowsRoot 'README.md') -Destination (Join-Path $destination 'README.md')
New-Item -ItemType Directory -Force -Path (Join-Path $destination 'licenses') | Out-Null
Copy-Item -Path (Join-Path $windowsRoot 'licenses/*') -Destination (Join-Path $destination 'licenses')
& node (Join-Path $PSScriptRoot 'audit-portable.mjs') $destination
if($LASTEXITCODE -ne 0){throw 'Portable package audit failed.'}
& node (Join-Path $PSScriptRoot 'audit-native-imports.mjs') $destination
if($LASTEXITCODE -ne 0){throw 'Native runtime dependency audit failed.'}
$zip=$destination+'.zip'
Compress-Archive -LiteralPath $destination -DestinationPath $zip -CompressionLevel Optimal
$digest=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($zip+'.sha256',$digest+'  '+[IO.Path]::GetFileName($zip)+[Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))
Write-Output ('Portable application: '+$destination)
Write-Output ('ZIP: '+$zip)
Write-Output ('SHA256: '+$digest)
