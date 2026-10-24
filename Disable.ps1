$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Bundle.Common.ps1')
$bundleHome=Get-BundleHome
$env:CODEX_HOME=$bundleHome
$bundleData=Join-Path $bundleHome 'plugin-data\codex-right-clearance-v3'
$bundleSettingsPath=Join-Path $bundleData 'settings.json'
$bundleSettings=Get-BundleJson $bundleSettingsPath
if(-not $bundleSettings){Write-Output 'Dynamic clearance is not configured.';exit 0}
$bundleSettings|Add-Member NoteProperty enabled $false -Force
$bundleSettings|Add-Member NoteProperty autoRestart $false -Force
Save-BundleJson $bundleSettingsPath $bundleSettings
$bundleManifest=Get-BundleJson (Join-Path $PSScriptRoot 'plugins\codex-right-clearance\plugin.json')
$bundleCache=Join-Path $bundleHome ('plugins\cache\codex-ui-local\codex-right-clearance\'+$bundleManifest.version)
$bundleControl=Join-Path $bundleCache 'scripts\Control.ps1'
if(-not (Test-Path -LiteralPath $bundleControl)){$bundleControl=Join-Path $PSScriptRoot 'plugins\codex-right-clearance\scripts\Control.ps1'}
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File $bundleControl -Action Disable
if($LASTEXITCODE-ne 0){throw 'The plugin was disabled, but startup unregistration needs to be checked.'}
Write-Output 'Dynamic clearance disabled. GPT-Niang and its preferences were kept.'
