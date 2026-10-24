# Detection only. Never close, launch, or restart the client.
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition-eq 'Desktop'){$env:PSModulePath=@((Join-Path $PSHOME 'Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))-join ';'}
$clearanceHome=$env:CODEX_HOME
if(-not $clearanceHome){$clearanceHome=Join-Path $env:USERPROFILE '.codex'}
$settingsPath=Join-Path $clearanceHome 'plugin-data\codex-right-clearance-v3\settings.json'
$settings=Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8|ConvertFrom-Json
if($settings.enabled-ne $true){[ordered]@{state='disabled';clientRestartAllowed=$false}|ConvertTo-Json -Compress;exit 0}
$package=Get-AppxPackage -Name OpenAI.Codex|Sort-Object Version -Descending|Select-Object -First 1
if(-not $package -or $package.PackageFamilyName-ne 'OpenAI.Codex_2p2nqsd0c76g0'){throw 'The registered Codex installation was not found.'}
$exe=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
$main=Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe'"|Where-Object {$_.ExecutablePath-eq $exe-and $_.CommandLine-notmatch '(?:^|\s)--type='}|Select-Object -First 1
if(-not $main){[ordered]@{state='not-running';clientRestartAllowed=$false}|ConvertTo-Json -Compress;exit 0}
$port=if($settings.debugPort){[int]$settings.debugPort}else{19327}
$configuredPort=[regex]::Match($main.CommandLine,'(?:^|\s)--remote-debugging-port=(\d+)(?:\s|$)')
if($configuredPort.Success){$port=[int]$configuredPort.Groups[1].Value}
if($port-lt 19327-or $port-gt 19426){throw 'Invalid loopback port.'}
$listeners=@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
$owned=$listeners.Count-gt 0
foreach($listener in $listeners){
 $owner=Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
 if($listener.LocalAddress-notin @('127.0.0.1','::1')-or -not $owner -or $owner.Path-ne $exe){$owned=$false}
}
if($owned){
 if($settings.debugPort-ne $port){$settings|Add-Member -NotePropertyName debugPort -NotePropertyValue $port -Force;$settings|Add-Member -NotePropertyName autoRestart -NotePropertyValue $false -Force;[IO.File]::WriteAllText($settingsPath,($settings|ConvertTo-Json -Depth 5))}
 [ordered]@{state='connected';version=[string]$package.Version;port=$port;clientRestartAllowed=$false}|ConvertTo-Json -Compress;exit 0
}
$reason=if($configuredPort.Success){'Configured connection is not ready; leaving the client running.'}else{'This client was opened without a debug connection; leaving its layout unchanged.'}
[ordered]@{state='connection-unavailable';pid=$main.ProcessId;reason=$reason;clientRestartAllowed=$false}|ConvertTo-Json -Compress
