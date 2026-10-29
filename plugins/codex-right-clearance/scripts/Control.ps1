param(
  [ValidateSet('Bootstrap','BootstrapWorker','SelfCheck','Watch','Serve','Status','Enable','Disable','Reapply')]
  [string]$Action = 'Status'
)
$ErrorActionPreference = 'Stop'
if($PSVersionTable.PSEdition-eq 'Desktop'){
  $clearanceModuleRoots=@((Join-Path $PSHOME 'Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))
  $env:PSModulePath=$clearanceModuleRoots-join ';'
}
$clearanceNodeCandidates = @(
  $env:CODEX_CLEARANCE_NODE,
  (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe')
)
$clearanceNodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($clearanceNodeCommand) { $clearanceNodeCandidates += $clearanceNodeCommand.Source }
$clearanceNode = $null
foreach ($candidate in $clearanceNodeCandidates) {
  if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    $nodeMajor = & $candidate -p 'parseInt(process.versions.node)'
    if ($LASTEXITCODE -eq 0 -and [int]$nodeMajor -ge 22) { $clearanceNode = $candidate; break }
  }
}
if (-not $clearanceNode) { throw 'Node.js 22 or newer is required. No runtime was installed.' }
$clearanceWorker = Join-Path $PSScriptRoot 'service.cjs'
if($Action-in @('Serve','Bootstrap','Enable')){
  try { & powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File (Join-Path $PSScriptRoot 'RegisterStartup.ps1') -Action Ensure | Out-Null }
  catch { [Console]::Error.WriteLine('Local startup registration was skipped: '+$_.Exception.Message) }
}
if ($Action -in @('Bootstrap','BootstrapWorker')) {
  $clearanceHome=$env:CODEX_HOME
  if(-not $clearanceHome){$clearanceHome=Join-Path $env:USERPROFILE '.codex'}
  $command='"'+$clearanceNode+'" "'+$clearanceWorker+'" watch --home "'+$clearanceHome+'"'
  $startup=([wmiclass]'Win32_ProcessStartup').CreateInstance()
  $startup.ShowWindow=0
  $launched=([wmiclass]'Win32_Process').Create($command,$PSScriptRoot,$startup)
  if($launched.ReturnValue-ne 0){throw 'Independent plugin worker could not start.'}
  $selfCheckPid=$null
  if($Action-eq 'Bootstrap'){
    $checker=Join-Path $PSScriptRoot 'startup-self-check.cjs'
    $checkerCommand='"'+$clearanceNode+'" "'+$checker+'" run --home "'+$clearanceHome+'"'
    $checkStarted=([wmiclass]'Win32_Process').Create($checkerCommand,$PSScriptRoot,$startup)
    if($checkStarted.ReturnValue-ne 0){throw 'Startup self-check could not start; layout worker was left running.'}
    $selfCheckPid=$checkStarted.ProcessId
  }
  [ordered]@{started=$true;pid=$launched.ProcessId;selfCheckPid=$selfCheckPid}|ConvertTo-Json -Compress
  exit 0
}
if($Action-eq 'SelfCheck'){
  & $clearanceNode (Join-Path $PSScriptRoot 'startup-self-check.cjs') run
  exit $LASTEXITCODE
}
& $clearanceNode $clearanceWorker $Action.ToLowerInvariant()
exit $LASTEXITCODE
