$ErrorActionPreference='Stop'
$windowsRoot=Split-Path -Parent $PSScriptRoot
$repositoryRoot=Split-Path -Parent $windowsRoot
$archive=Join-Path $repositoryRoot '.agent-local/vc_redist.x64.exe'
$work=Join-Path $repositoryRoot '.agent-local/vc-runtime-extraction'
$runtime=Join-Path $windowsRoot '.native/vc-runtime'
$cabinets=Join-Path $work 'cabinets'
$payload=Join-Path $work 'payload'
$minimum=Join-Path $work 'minimum'
New-Item -ItemType Directory -Force -Path $cabinets,$payload,$minimum,$runtime | Out-Null
if(-not(Test-Path -LiteralPath $archive)) {
  Invoke-WebRequest -UseBasicParsing -Uri 'https://download.visualstudio.microsoft.com/download/pr/990c720a-46ce-4dc7-87b9-c2eb615d34b9/CC0FF0EB1DC3F5188AE6300FAEF32BF5BEEBA4BDD6E8E445A9184072096B713B/VC_redist.x64.exe' -OutFile $archive
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'cc0ff0eb1dc3f5188ae6300faef32bf5beeba4bdd6e8e445a9184072096b713b'){throw 'VC runtime checksum mismatch.'}
$signature=Get-AuthenticodeSignature -LiteralPath $archive
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw 'VC runtime Microsoft signature was not verified.'}
& node (Join-Path $PSScriptRoot 'extract-cabinets.mjs') $archive $cabinets
if($LASTEXITCODE -ne 0){throw 'Cabinet validation failed.'}
& expand.exe (Join-Path $cabinets 'container-0.cab') '-F:0' $payload | Out-Null
if($LASTEXITCODE -ne 0){throw 'Manifest extraction failed.'}
& expand.exe (Join-Path $cabinets 'container-0.cab') '-F:u4' $payload | Out-Null
& expand.exe (Join-Path $cabinets 'container-1.cab') '-F:a12' $payload | Out-Null
if($LASTEXITCODE -ne 0){throw 'Runtime cabinet extraction failed.'}
[xml]$manifest=Get-Content -LiteralPath (Join-Path $payload '0') -Raw
if(-not($manifest.BurnManifest.Payload | Where-Object {$_.SourcePath -eq 'a12' -and $_.FilePath -eq 'packages\vcRuntimeMinimum_amd64\cab1.cab'})){throw 'Pinned runtime payload layout changed.'}
& expand.exe (Join-Path $payload 'a12') '-F:*' $minimum | Out-Null
if($LASTEXITCODE -ne 0){throw 'Runtime extraction failed.'}
$names=@('msvcp140.dll','msvcp140_1.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','msvcp140_codecvt_ids.dll','vcruntime140.dll','vcruntime140_1.dll','vcruntime140_threads.dll','concrt140.dll')
foreach($name in $names){Copy-Item -LiteralPath (Join-Path $minimum ($name+'_amd64')) -Destination (Join-Path $runtime $name)}
Copy-Item -LiteralPath (Join-Path $payload 'u4') -Destination (Join-Path $windowsRoot 'licenses/Microsoft-Visual-Cpp-Runtime.rtf')
'Prepared app-local Microsoft VC++ runtime 14.44.35211. No installer was executed.'
