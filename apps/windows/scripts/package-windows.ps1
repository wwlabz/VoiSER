$ErrorActionPreference = "Stop"
trap {
  $msg = $_.Exception.Message.Replace("`r", " ").Replace("`n", " ")
  Write-Host "::error title=Windows package fatal::$msg"
  exit 1
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$out = Join-Path $root "artifacts"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

$buildPayloadDir = Join-Path $out "portable-build"
$packageDir = Join-Path $out "portable"
$appDir = Join-Path $packageDir "app"
New-Item -ItemType Directory -Path $buildPayloadDir | Out-Null
New-Item -ItemType Directory -Path $packageDir | Out-Null
New-Item -ItemType Directory -Path $appDir | Out-Null

$project = ".\\src\\VoiSER.Windows.App\\VoiSER.Windows.App.csproj"
$exeName = "VoiSER.Windows.App.exe"
$buildExePath = Join-Path $buildPayloadDir $exeName

function Resolve-MSBuildPath {
  $cmd = Get-Command msbuild -ErrorAction SilentlyContinue
  if ($null -ne $cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
    return $cmd.Source
  }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path $vswhere) {
    $found = & $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild\\**\\Bin\\MSBuild.exe" 2>$null | Select-Object -First 1
    if (-not [string]::IsNullOrWhiteSpace($found)) {
      return $found
    }
  }

  throw "MSBuild.exe not found. Ensure microsoft/setup-msbuild action ran before package script."
}

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(Mandatory = $true)]
    [string[]]$Args
  )

  try {
    $output = & $Command @Args 2>&1
    $exitCode = $LASTEXITCODE
  }
  catch {
    $output = @($_.Exception.Message)
    $exitCode = 1
  }

  if ($null -ne $output) {
    $output | ForEach-Object { Write-Host $_ }
  }

  if ($exitCode -ne 0) {
    $interesting = @()

    if ($null -ne $output) {
      $interesting = $output |
        Select-String -Pattern 'error|failed|MSB[0-9]{4}|NU[0-9]{4}' -CaseSensitive:$false |
        Select-Object -ExpandProperty Line -First 60

      $tail = $output | Select-Object -Last 60
      if ($tail) {
        $interesting += $tail
      }
    }

    if ($null -eq $interesting -or $interesting.Count -eq 0) {
      $interesting = @("$Command failed without output")
    }

    $interesting = $interesting | Select-Object -Unique

    foreach ($line in $interesting) {
      $msg = $line.ToString().Replace("`r", " ").Replace("`n", " ")
      Write-Host "::error title=Windows package::$msg"
    }

    throw "command failed (exit $exitCode): $Command $($Args -join ' ')"
  }
}

$msbuildPath = Resolve-MSBuildPath
Write-Host "Using MSBuild: $msbuildPath"

Invoke-Checked -Command $msbuildPath -Args @(
  $project,
  "/restore",
  "/p:Configuration=Release",
  "/p:Platform=x64",
  "/p:RuntimeIdentifier=win-x64",
  "/p:SelfContained=true",
  "/p:WindowsAppSDKSelfContained=true",
  "/p:WindowsPackageType=None",
  "/p:EnableMsixTooling=false",
  "/p:GenerateAppxPackageOnBuild=false",
  "/p:UapAppxPackageBuildMode=None",
  "/p:AppxBundle=Never",
  "/p:PublishSingleFile=false",
  "/p:PublishTrimmed=false"
)

$buildOutputRoot = Join-Path $root "src/VoiSER.Windows.App/bin"
$buildExe = Get-ChildItem -Path $buildOutputRoot -Recurse -Filter $exeName -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "win-x64" } |
  Select-Object -First 1

if ($null -eq $buildExe) {
  $buildExe = Get-ChildItem -Path $buildOutputRoot -Recurse -Filter $exeName -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
}

if ($null -eq $buildExe) {
  throw "Portable package build failed: could not find $exeName under $buildOutputRoot"
}

Copy-Item -Path (Join-Path $buildExe.Directory.FullName "*") -Destination $buildPayloadDir -Recurse -Force

if (-not (Test-Path $buildExePath)) {
  throw "Portable self-contained build failed: $buildExePath was not produced."
}

Copy-Item -Path (Join-Path $buildPayloadDir "*") -Destination $appDir -Recurse -Force

$launcherPath = Join-Path $packageDir "VoiSER.cmd"
@"
@echo off
setlocal
set "ROOT=%~dp0"
start "" "%ROOT%app\VoiSER.Windows.App.exe" %*
"@ | Out-File -FilePath $launcherPath -Encoding ascii

$readmePath = Join-Path $packageDir "README-portable.txt"
@"
VoiSER Windows Portable

1. Extract this ZIP to any folder.
2. Launch VoiSER using VoiSER.cmd
   (or run app\VoiSER.Windows.App.exe directly).
"@ | Out-File -FilePath $readmePath -Encoding utf8

Compress-Archive -Path "$packageDir\*" -DestinationPath (Join-Path $out "VoiSER-Windows-portable.zip")
Write-Host "Portable ZIP created: $(Join-Path $out 'VoiSER-Windows-portable.zip')"

# MSIX package is built in a dedicated release workflow step.
