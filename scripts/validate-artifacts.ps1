$ErrorActionPreference = 'Stop'

# PS7 guard (для узгодженості)
if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "This script requires PowerShell 7+. Please run it in pwsh (PowerShell 7)."
}

Write-Host "Reading config"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactsPath = Join-Path $repoRoot "artifacts.json"
if (-not (Test-Path $artifactsPath)) {
  throw "artifacts.json not found at $artifactsPath"
}

$config = Get-Content -Raw -Path $artifactsPath | ConvertFrom-Json
if (-not $config.resourcesTemplate) {
  throw "resourcesTemplate field is missing in artifacts.json"
}

$uri = $config.resourcesTemplate

# (optional) SAS expiry sanity check
try {
  $u = [System.Uri]$uri
  $qs = [System.Web.HttpUtility]::ParseQueryString($u.Query)
  $se = $qs["se"]
  if ($se) {
    $exp = [DateTime]::Parse($se, $null, [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
    if ($exp -lt (Get-Date).ToUniversalTime()) { throw "SAS token expired at $exp UTC." }
  }
} catch {
  Write-Warning "Could not parse SAS expiry: $($_.Exception.Message)"
}

Write-Host "Validating artifact URL reachability (HEAD)..."
try {
  $resp = Invoke-WebRequest -Method Head -Uri $uri -TimeoutSec 60 -ErrorAction Stop
} catch {
  throw "Failed to access artifact URL. $_"
}

if ($resp.StatusCode -ne 200) {
  throw "Artifact not accessible, status code: $($resp.StatusCode)"
}

Write-Host "Artifact URL is reachable - OK."
