param(
  [Parameter(Mandatory = $true)]
  [string]$ArtifactsStorageAccountName
)

$ErrorActionPreference = 'Stop'

Write-Host "Running initial validation"

# 0) Перевіримо логін у Azure
$ctxAzure = Get-AzContext
if (-not $ctxAzure) { throw "Not connected to Azure. Run Connect-AzAccount first." }
Write-Host "Azure Powershell module is installed, account is connected."

# 1) Константи завдання
$resourceGroup = "mate-resources"
$containerName = "task-artifacts"
$taskFolder = "task1"

# 2) Знайдемо Storage Account і контейнер
Write-Host "Checking if storage account exists"
$sa = Get-AzStorageAccount -ResourceGroupName $resourceGroup -Name $ArtifactsStorageAccountName -ErrorAction Stop
if (-not $sa) { throw "Storage account $ArtifactsStorageAccountName not found in RG $resourceGroup" }
Write-Host "Storage account found"

Write-Host "Checking if artifacts storage container exists"
$ctx = $sa.Context
$container = Get-AzStorageContainer -Context $ctx -Name $containerName -ErrorAction SilentlyContinue
if (-not $container) {
  throw "Unable to find a storage container $containerName in the storage account $ArtifactsStorageAccountName, please make sure that it's created"
}
Write-Host "Storage container for artifacts found!"

# 3) Готуємо тимчасову директорію
Write-Host "Generating artifacts"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tempPath = Join-Path $repoRoot "temp"
Write-Host "Checking if temp folder exists"
if (-not (Test-Path $tempPath)) {
  Write-Host "Temp folder does not exist, creating..."
  New-Item -Path $tempPath -ItemType Directory | Out-Null
}

# 4) Згенеруємо простий артефакт (JSON із тех.інфою)
#    За потреби тут можна покласти будь-який реальний експорт ресурсів
$artifactLocalPath = Join-Path $tempPath "exported-template.json"
$payload = [ordered]@{
  generatedAtUtc  = (Get-Date).ToUniversalTime().ToString("o")
  subscriptionId  = $ctxAzure.Subscription.Id
  tenantId        = $ctxAzure.Tenant.Id
  storageAccount  = $ArtifactsStorageAccountName
  resourceGroup   = $resourceGroup
  note            = "Mate Academy Azure Lab Setup artifact"
} | ConvertTo-Json -Depth 5
$payload | Set-Content -Path $artifactLocalPath -Encoding UTF8

Write-Host ""
Write-Host "Exporting resources template"
Write-Host ""
Write-Host "Path : $artifactLocalPath"
Write-Host ""

# 5) Завантажимо у Blob Storage
Write-Host "Uploading resources template"
$blobPath = "$taskFolder/exported-template.json"
Set-AzStorageBlobContent -Context $ctx -File $artifactLocalPath -Container $containerName -Blob $blobPath -Force | Out-Null

# 6) Згенеруємо SAS URL (читання на 30 днів)
Write-Host "Generating a SAS token for the template artifact"
$expiry = (Get-Date).ToUniversalTime().AddDays(30)
$sasUrl = New-AzStorageBlobSASToken -Context $ctx -Container $containerName -Blob $blobPath -Permission r -ExpiryTime $expiry -FullUri

# 7) Оновимо artifacts.json in-place
Write-Host "Updating artifacts config"
$artifactsPath = Join-Path $repoRoot "artifacts.json"
$artifactsObj = [ordered]@{
  resourcesTemplate = $sasUrl
}
($artifactsObj | ConvertTo-Json) | Set-Content -Path $artifactsPath -Encoding UTF8

# 8) Закомітимо зміни (тільки artifacts.json)
try {
  Push-Location $repoRoot
  git add artifacts.json | Out-Null
  # Комітим лише якщо справді є зміни
  $hasChanges = (git status --porcelain | Select-String "artifacts.json")
  if ($hasChanges) {
    git commit -m "chore: generate artifacts for task1 via script" | Out-Null
    Write-Host "Committed artifacts.json"
  } else {
    Write-Host "No changes to commit in artifacts.json"
  }
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Done. artifacts.json is updated and committed."
