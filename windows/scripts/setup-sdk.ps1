$ErrorActionPreference='Stop'
$repositoryRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sdkRoot=Join-Path $repositoryRoot '.agent-local/dotnet'
$archive=Join-Path $repositoryRoot '.agent-local/dotnet-sdk-10.0.403-win-x64.zip'
New-Item -ItemType Directory -Force -Path $sdkRoot | Out-Null
if(-not(Test-Path -LiteralPath $archive)) {Invoke-WebRequest -UseBasicParsing -Uri 'https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/dotnet-sdk-10.0.403-win-x64.zip' -OutFile $archive}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash.ToLowerInvariant() -ne '7a114c318fa7f1d9822991b534b2814d0e78386ceda816b371f5141acefe741d87ccb606ede06cadac8f9ac5070e32b708a67bbd1619ff5e5a7858a27874ef48'){throw 'SDK checksum mismatch.'}
Expand-Archive -LiteralPath $archive -DestinationPath $sdkRoot -Force
& (Join-Path $sdkRoot 'dotnet.exe') --version
