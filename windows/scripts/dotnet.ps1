[string[]]$dotnetArguments = $args
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
$localSdk = Join-Path $repositoryRoot '.agent-local/dotnet/dotnet.exe'
$env:DOTNET_CLI_HOME = Join-Path $repositoryRoot '.agent-local/dotnet-home'
$env:NUGET_PACKAGES = Join-Path $repositoryRoot '.agent-local/nuget'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO = '1'
$sdk = if (Test-Path -LiteralPath $localSdk) { $localSdk } else { 'dotnet' }
Push-Location $windowsRoot
try { & $sdk @dotnetArguments; $resultCode = $LASTEXITCODE }
finally { Pop-Location }
exit $resultCode
