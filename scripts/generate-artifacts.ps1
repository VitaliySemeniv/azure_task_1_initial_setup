param(
  [Parameter(Mandatory = $true)]
  [string]$ArtifactsStorageAccountName
)

$ErrorActionPreference = 'Stop'

# 0) PS7 guard
if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "This script requires PowerShell 7+. Please run it in pwsh (PowerShell 7)."
}

# 0.1) Az module presence
if (-not (Get-Command Get-AzContext -ErrorAction SilentlyContinue)) {
  throw "Az module not found. Install with: Install-Module -Name Az -Repository PSGallery -Force"
}

Write-Host "Running initial validation"

# 1) Azure context
$ctxAzure = Get-AzContext
if (-not $ctxAzure) {
  throw "Not connected to Azure. Run Connect-AzAccount (use -UseDeviceAuthentication when over SSH)."
}
Write-Host "Azure module available, account is connected."

# 2) Task constants
$resourceGroup = "mate-resources"
$containerName = "task-artifacts"
$taskFolder    = "task1"

# 3) Storage account + container
Write-Host "Checking if storage account exists"
$sa = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $ArtifactsStorageAccountName -ErrorAction Stop
Write-Host "Storage account found"

Write-Host "Checking if artifacts storage container exists"
$ctx = $sa.Context
$container = Get-AzStorageContainer -Context $ctx -Name $containerName -ErrorAction SilentlyContinue
if (-not $container) {
  throw "Unable to find a storage container '$containerName' in storage account '$ArtifactsStorageAccountName'. Please create it first."
}
Write-Host "Storage container for artifacts found!"

# 4) repo root / temp
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tempPath = Join-Path $repoRoot "temp"
if (-not (Test-Path $tempPath)) { New-Item -Path $tempPath -ItemType Directory | Out-Null }

# 5) generate artifact (demo JSON)
$artifactLocalPath = Join-Path $tempPath "exported-template.json"
$payload = [ordered]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  subscriptionId = $ctxAzure.Subscription.Id
  tenantId       = $ctxAzure.Tenant.Id
  storageAccount = $ArtifactsStorageAccountName
  resourceGroup  = $resourceGroup
  note           = "Mate Academy Azure Lab Setup artifact"
} | ConvertTo-Json -Depth 5
$payload | Set-Content -Path $artifactLocalPath -Encoding UTF8
Write-Host "Exported artifact at: $artifactLocalPath"

# 6) upload artifact
$blobPath = "$taskFolder/exported-template.json"
Set-AzStorageBlobContent -Context $ctx -File $artifactLocalPath -Container $containerName -Blob $blobPath -Force | Out-Null
Write-Host "Uploaded blob: $containerName/$blobPath"

# 7) SAS generation with fallback
$expiry = (Get-Date).ToUniversalTime().AddDays(30)
$sasUrl = $null
Write-Host "Generating SAS token..."
try {
  $sasUrl = New-AzStorageBlobSASToken -Context $ctx -Container $containerName -Blob $blobPath -Permission r -ExpiryTime $expiry -FullUri
} catch {
  Write-Warning "Implicit context SAS failed. Trying with account key..."
  try {
    $acctKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroup -Name $ArtifactsStorageAccountName | Select-Object -First 1).Value
    if (-not $acctKey) { throw "No storage account key returned." }
    $ctxWithKey = New-AzStorageContext -StorageAccountName $ArtifactsStorageAccountName -StorageAccountKey $acctKey
    $sasUrl = New-AzStorageBlobSASToken -Context $ctxWithKey -Container $containerName -Blob $blobPath -Permission r -ExpiryTime $expiry -FullUri
  } catch {
    throw "Unable to generate SAS URL. Ensure permissions to read storage keys. Details: $($_.Exception.Message)"
  }
}
Write-Host "SAS URL generated."

# 8) update artifacts.json in-place
$artifactsPath = Join-Path $repoRoot "artifacts.json"
$artifactsObj = [ordered]@{ resourcesTemplate = $sasUrl }
($artifactsObj | ConvertTo-Json) | Set-Content -Path $artifactsPath -Encoding UTF8
Write-Host "Updated artifacts.json"

# 9) robust git commit
Push-Location $repoRoot
try {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning "git not found. Skipping commit. Please commit artifacts.json manually."
  } elseif (-not (& git rev-parse --is-inside-work-tree 2>$null)) {
    Write-Warning "Not inside a git repository. Skipping commit. Please commit manually."
  } else {
    & git add artifacts.json | Out-Null
    $dirty = & git status --porcelain | Select-String "artifacts.json"
    if ($dirty) {
      try {
        & git -c user.useConfigOnly=true commit -m "chore: generate artifacts for task1 via script" | Out-Null
        Write-Host "Committed artifacts.json"
      } catch {
        Write-Warning "Git commit failed: $($_.Exception.Message). Please commit manually."
      }
    } else {
      Write-Host "No changes to commit in artifacts.json"
    }
  }
} finally {
  Pop-Location
}

Write-Host "Done."
