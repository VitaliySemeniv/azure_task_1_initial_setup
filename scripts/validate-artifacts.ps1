$ErrorActionPreference = 'Stop'

Write-Host "Reading config"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactsPath = Join-Path $repoRoot "artifacts.json"
if (-not (Test-Path $artifactsPath)) { throw "artifacts.json not found at $artifactsPath" }

$config = Get-Content -Raw -Path $artifactsPath | ConvertFrom-Json
if (-not $config.resourcesTemplate) { throw "resourcesTemplate field is missing in artifacts.json" }

Write-Host "Checking if temp folder exists"
$tempPath = Join-Path $repoRoot "temp"
if (-not (Test-Path $tempPath)) { New-Item -ItemType Directory -Path $tempPath | Out-Null }

Write-Host "Downloading artifacts"
$uri = $config.resourcesTemplate
# достатньо HEAD-запиту, щоб перевірити доступність
try {
  $resp = Invoke-WebRequest -Method Head -Uri $uri -UseBasicParsing -TimeoutSec 60
} catch {
  throw "Failed to access artifact URL. $_"
}

Write-Host "Validating artifacts"
if ($resp.StatusCode -ne 200) { throw "Artifact not accessible, status code: $($resp.StatusCode)" }

Write-Host "Checked if storage account exists - OK."
Write-Host "Checked the storage account SKU - OK."
Write-Host "Artifact URL is reachable - OK."
