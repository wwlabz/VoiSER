$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

dotnet restore .\VoiSER.Windows.sln
dotnet build .\VoiSER.Windows.sln -c Release
