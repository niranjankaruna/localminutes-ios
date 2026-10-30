param([ValidateSet('cpu','cuda')][string]$Backend='cpu')
$ErrorActionPreference='Stop'
$windowsRoot=Split-Path -Parent $PSScriptRoot
$artifactRoot=Join-Path $windowsRoot ('.native/llama-'+$Backend)
$cacheRoot=Join-Path (Split-Path -Parent $windowsRoot) '.agent-local/native-downloads'
New-Item -ItemType Directory -Force -Path $artifactRoot,$cacheRoot | Out-Null
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'prepare-vc-runtime.ps1')
if($LASTEXITCODE -ne 0){throw 'App-local VC runtime preparation failed.'}
$artifacts=if($Backend -eq 'cpu') {
  @(@{Name='llama-b11900-bin-win-cpu-x64.zip';Hash='d3bbbbb7d1b4979b72052fd73cdeeb5a4d5a4e6a3f52aeb40abd6f116558e323'})
} else {
  @(@{Name='llama-b11900-bin-win-cuda-13.4-x64.zip';Hash='0d75ad36367da00622c146a97e82fac3dcfcbe960afc2f0234eef026886b16f6'},
    @{Name='cudart-llama-bin-win-cuda-13.4-x64.zip';Hash='738f8c251ac22b70c3ae6f83a10cf222725df0395246a2cf58f32bdb85fbe668'})
}
foreach($artifact in $artifacts) {
  $archive=Join-Path $cacheRoot $artifact.Name
  if(-not(Test-Path -LiteralPath $archive)) { Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/ggml-org/llama.cpp/releases/download/b11900/'+$artifact.Name) -OutFile $archive }
  if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $artifact.Hash) { throw 'Native runtime checksum mismatch.' }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($archive)
  try {
    foreach($entry in $zip.Entries) {
      $resolved=[IO.Path]::GetFullPath((Join-Path $artifactRoot $entry.FullName))
      if(-not $resolved.StartsWith([IO.Path]::GetFullPath($artifactRoot)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Native archive path escaped its destination.' }
    }
  } finally {$zip.Dispose()}
  Expand-Archive -LiteralPath $archive -DestinationPath $artifactRoot -Force
}
Copy-Item -Path (Join-Path $windowsRoot '.native/vc-runtime/*.dll') -Destination $artifactRoot
& (Join-Path $artifactRoot 'llama-completion.exe') --version
if($LASTEXITCODE -ne 0){throw 'Native runtime did not start.'}
