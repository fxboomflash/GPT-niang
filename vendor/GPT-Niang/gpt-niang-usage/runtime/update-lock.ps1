param([Parameter(Mandatory=$true)][string]$AgentDir,[Parameter(Mandatory=$true)][int]$OwnerPid)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'supervisor-task.ps1')
. (Join-Path $PSScriptRoot 'update-common.ps1')
try {
  # The short-lived bridge only claims the record for its Node caller. It never
  # installs anything, and the caller releases the persistent task lock later.
  $lock=Enter-WidgetUpdateLock -AgentDir $AgentDir -OwnerPid $OwnerPid
  Read-WidgetUpdateJson (Join-Path $lock.Directory 'owner.json')|ConvertTo-Json -Compress
} catch {
  if($_.Exception.Message-match 'already running|reclamation is busy' -or $_.FullyQualifiedErrorId-match 'DirectoryExist'){exit 2}
  exit 3
}
