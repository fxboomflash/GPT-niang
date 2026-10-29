param([ValidateRange(19327,19426)][int]$Port=19327)
$ErrorActionPreference = 'Stop'
if($PSVersionTable.PSEdition-eq 'Desktop'){$env:PSModulePath=@((Join-Path $PSHOME 'Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))-join ';'}
$clearancePackage = Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1
if (-not $clearancePackage) { throw 'Codex package not found.' }
if ($clearancePackage.PackageFamilyName -ne 'OpenAI.Codex_2p2nqsd0c76g0') { throw 'Unexpected package identity.' }
$clearanceExe = Join-Path $clearancePackage.InstallLocation 'app\ChatGPT.exe'
$clearanceListeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
if (-not $clearanceListeners.Count) { throw 'The local Codex debug connection is not available yet.' }
$clientSessions=@{}
foreach ($listener in $clearanceListeners) {
  if ($listener.LocalAddress -notin @('127.0.0.1','::1')) { throw 'The debug connection must listen only on loopback.' }
  $clearanceProcess = Get-Process -Id $listener.OwningProcess -ErrorAction Stop
  if (-not [string]::Equals($clearanceProcess.Path, $clearanceExe, [StringComparison]::OrdinalIgnoreCase)) { throw 'The debug endpoint is not owned by the verified Codex installation.' }
  $clientSessions[[string]$clearanceProcess.Id]=[ordered]@{pid=$clearanceProcess.Id;startedAt=$clearanceProcess.StartTime.ToUniversalTime().ToString('o')}
}
[ordered]@{ verified = $true; version = [string]$clearancePackage.Version; ownerPids = @($clearanceListeners.OwningProcess | Select-Object -Unique);clientSessions=@($clientSessions.Values) } | ConvertTo-Json -Depth 5 -Compress
