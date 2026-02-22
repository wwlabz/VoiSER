$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "apps/windows")
dotnet restore .\VoiSER.Windows.sln
dotnet test .\VoiSER.Windows.sln -c Release --no-restore
