$ErrorActionPreference = "Stop"
trap {
  $msg = $_.Exception.Message.Replace("`r", " ").Replace("`n", " ")
  Write-Host "::error title=Windows MSIX::$msg"
  exit 1
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

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
        Select-String -Pattern 'error|failed|MSB[0-9]{4}|APPX[0-9]{4}' -CaseSensitive:$false |
        Select-Object -ExpandProperty Line -First 80

      $tail = $output | Select-Object -Last 80
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
      Write-Host "::error title=Windows MSIX::$msg"
    }

    throw "command failed (exit $exitCode): $Command $($Args -join ' ')"
  }
}

$artifactsRoot = Join-Path $root "artifacts"
$msixOutDir = Join-Path $artifactsRoot "msix"
$zipPayloadDir = Join-Path $artifactsRoot "msix-payload"

if (Test-Path $msixOutDir) { Remove-Item $msixOutDir -Recurse -Force }
if (Test-Path $zipPayloadDir) { Remove-Item $zipPayloadDir -Recurse -Force }
New-Item -ItemType Directory -Path $msixOutDir | Out-Null
New-Item -ItemType Directory -Path $zipPayloadDir | Out-Null

$project = ".\\src\\VoiSER.Windows.App\\VoiSER.Windows.App.csproj"
$pfxPath = Join-Path $msixOutDir "voiser-signing.pfx"
$cerPath = Join-Path $msixOutDir "VoiSER-signing.cer"
$signingThumbprint = $null
$certStoreThumbprintsToCleanup = @()

$certPassword = $env:WINDOWS_PFX_PASSWORD
$usingProvidedPfx = -not [string]::IsNullOrWhiteSpace($env:WINDOWS_PFX_BASE64)
$signingCertSubject = $null

if ($usingProvidedPfx) {
  if ([string]::IsNullOrWhiteSpace($certPassword)) {
    throw "WINDOWS_PFX_PASSWORD is required when WINDOWS_PFX_BASE64 is provided."
  }

  Write-Host "Using signing certificate from repository secret WINDOWS_PFX_BASE64."
  [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:WINDOWS_PFX_BASE64))

  $securePassword = ConvertTo-SecureString -AsPlainText $certPassword -Force
  $importedCert = Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation "Cert:\CurrentUser\My" -Password $securePassword
  if ($null -eq $importedCert) {
    throw "Could not import certificate from WINDOWS_PFX_BASE64."
  }
  $signingThumbprint = $importedCert.Thumbprint
  $signingCertSubject = $importedCert.Subject
  $certStoreThumbprintsToCleanup += $signingThumbprint
  Export-Certificate -Cert $importedCert -FilePath $cerPath | Out-Null
}
else {
  Write-Warning "WINDOWS_PFX_BASE64 is not set. Generating temporary self-signed certificate for this build."
  $cert = New-SelfSignedCertificate `
    -Type Custom `
    -Subject "CN=wwlabz" `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -KeyUsage DigitalSignature `
    -KeyExportPolicy Exportable `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3") `
    -NotAfter (Get-Date).AddYears(2)

  $signingThumbprint = $cert.Thumbprint
  $signingCertSubject = $cert.Subject
  $certStoreThumbprintsToCleanup += $signingThumbprint
  Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
}

if ([string]::IsNullOrWhiteSpace($signingThumbprint)) {
  throw "Signing certificate thumbprint is empty."
}

if ($null -eq $signingCertSubject -or $signingCertSubject -notmatch "CN=wwlabz") {
  throw "Signing certificate subject '$signingCertSubject' does not match manifest publisher 'CN=wwlabz'."
}

$msbuildPath = Resolve-MSBuildPath
Write-Host "Using MSBuild: $msbuildPath"

Invoke-Checked -Command $msbuildPath -Args @(
  $project,
  "/restore",
  "/p:Configuration=Release",
  "/p:Platform=x64",
  "/p:RuntimeIdentifier=win-x64",
  "/p:GenerateAppxPackageOnBuild=true",
  "/p:AppxBundle=Never",
  "/p:UapAppxPackageBuildMode=SideloadOnly",
  "/p:AppxPackageDir=$($msixOutDir)\",
  "/p:AppxPackageSigningEnabled=true",
  "/p:PackageCertificateThumbprint=$signingThumbprint",
  "/p:PackageCertificateKeyFile=",
  "/p:PackageCertificatePassword="
)

$msixFile = Get-ChildItem -Path $msixOutDir -Recurse -Include *.msix,*.appx,*.msixbundle -File -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if ($null -eq $msixFile) {
  throw "MSIX build completed but package file was not found in $msixOutDir"
}

Copy-Item $msixFile.FullName -Destination (Join-Path $zipPayloadDir $msixFile.Name) -Force
if (Test-Path $cerPath) {
  Copy-Item $cerPath -Destination (Join-Path $zipPayloadDir "VoiSER-signing.cer") -Force
}

$installInfoPath = Join-Path $zipPayloadDir "README-install-msix.txt"
@"
VoiSER Windows MSIX package

1. If Windows blocks installation due untrusted publisher, install `VoiSER-signing.cer`:
   - Open the CER file
   - Install Certificate
   - Store Location: Local Machine
   - Place in store: Trusted People
2. Run the .msix package and install VoiSER.

Tip:
- For production trusted installs, provide `WINDOWS_PFX_BASE64` + `WINDOWS_PFX_PASSWORD` secrets in GitHub.
"@ | Out-File -FilePath $installInfoPath -Encoding utf8

$msixZipPath = Join-Path $artifactsRoot "VoiSER-Windows-msix.zip"
if (Test-Path $msixZipPath) { Remove-Item $msixZipPath -Force }
Compress-Archive -Path "$zipPayloadDir\*" -DestinationPath $msixZipPath -Force
Write-Host "MSIX ZIP created: $msixZipPath"

foreach ($thumbprint in $certStoreThumbprintsToCleanup) {
  if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
    $certStorePath = "Cert:\CurrentUser\My\$thumbprint"
    if (Test-Path $certStorePath) {
      Remove-Item $certStorePath -Force
    }
  }
}

if (Test-Path $pfxPath) {
  Remove-Item $pfxPath -Force
}
