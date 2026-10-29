param([switch]$CheckOnly,[string]$WidgetInstallation)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scripts\Bundle.Common.ps1')
$bundleRoot=$PSScriptRoot
$bundleNode=Find-BundleNode
$bundleCli=Find-BundleCli
$bundleWidget=Find-BundleWidget $WidgetInstallation $bundleRoot
$bundleHome=Get-BundleHome
$bundlePackage=Get-AppxPackage -Name OpenAI.Codex|Sort-Object Version -Descending|Select-Object -First 1
if(-not $bundlePackage-or $bundlePackage.PackageFamilyName-ne 'OpenAI.Codex_2p2nqsd0c76g0'){throw 'The supported Microsoft Store Codex package was not found.'}
$bundleManifest=Get-BundleJson (Join-Path $bundleRoot 'plugins\codex-right-clearance\plugin.json')
$bundleVersion=$bundleManifest.version
$bundleCache=Join-Path $bundleHome ('plugins\cache\codex-ui-local\codex-right-clearance\'+$bundleVersion)
if($CheckOnly){
 $bundleAudioPlan=if($bundleWidget){& (Join-Path $bundleRoot 'scripts\Apply-WidgetAudioFix.ps1') -WidgetInstallation $bundleWidget -CheckOnly|ConvertFrom-Json}else{@{ok=$true;wouldApplyAfterWidgetInstall=$true}}
 [ordered]@{ok=$true;readOnly=$true;audioPatch=$bundleAudioPlan;bundleVersion=(Get-BundleJson (Join-Path $bundleRoot 'package.json')).version;clearanceVersion=$bundleVersion;nodeMajor=[int](& $bundleNode -p 'parseInt(process.versions.node)');codexPackageVersion=[string]$bundlePackage.Version;existingWidgetFound=[bool]$bundleWidget;wouldInstallUpstreamWidget=(-not [bool]$bundleWidget);existingClearanceFilesMatch=(Test-BundleCache (Join-Path $bundleRoot 'plugins\codex-right-clearance') $bundleCache);clientWouldBeRestarted=$false}|ConvertTo-Json -Compress
 exit 0
}
$env:CODEX_HOME=$bundleHome
$env:PATH=(Split-Path $bundleNode -Parent)+';'+$env:PATH
$env:CODEX_CLEARANCE_NODE=$bundleNode
if(-not $bundleWidget){
 & powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File (Join-Path $bundleRoot 'vendor\GPT-Niang\gpt-niang-usage\Install.ps1')
 if($LASTEXITCODE-ne 0){throw 'Original GPT-Niang installer failed. Clearance was not installed.'}
 $bundleWidget=Find-BundleWidget $null $bundleRoot
 if(-not $bundleWidget){throw 'Original GPT-Niang installation record was not created.'}
}
$bundleWidgetConfig=Get-BundleJson $bundleWidget
if(-not $bundleWidgetConfig.appDir-or -not $bundleWidgetConfig.dataDir-or -not (Test-Path -LiteralPath (Join-Path $bundleWidgetConfig.appDir 'widget.ps1'))){throw 'The GPT-Niang installation record is invalid.'}
& (Join-Path $bundleRoot 'scripts\Apply-WidgetAudioFix.ps1') -WidgetInstallation $bundleWidget
if(-not $?){throw 'The audio patch could not be installed. Clearance was not updated.'}
$bundleData=Join-Path $bundleHome 'plugin-data\codex-right-clearance-v3'
$bundleSettingsPath=Join-Path $bundleData 'settings.json'
$bundleSettings=Get-BundleJson $bundleSettingsPath
if(-not $bundleSettings){$bundleSettings=[pscustomobject]@{debugPort=19328}}
$bundlePrevious=$bundleSettings|ConvertTo-Json -Depth 12
try {
 $bundleSettings|Add-Member NoteProperty enabled $false -Force
 $bundleSettings|Add-Member NoteProperty autoRestart $false -Force
 Save-BundleJson $bundleSettingsPath $bundleSettings
 $bundleDeadline=[DateTime]::UtcNow.AddSeconds(20)
 do{
  $bundleWorkers=@(Get-CimInstance Win32_Process -Filter "Name='node.exe'"|Where-Object {$_.CommandLine-match '[\\/]codex-right-clearance[\\/].*[\\/]scripts[\\/]service\.cjs"?\s+watch(?:\s|$)'})
  if(-not $bundleWorkers.Count){break};Start-Sleep -Milliseconds 300
 }while([DateTime]::UtcNow-lt $bundleDeadline)
 if($bundleWorkers.Count){throw 'Previous clearance worker has not stopped gracefully. No client or widget was closed.'}
 $bundleCatalog=(& $bundleCli plugin list --json)|ConvertFrom-Json
 if($LASTEXITCODE-ne 0){throw 'Cannot inspect installed plugins.'}
 $bundleInstalled=@($bundleCatalog.installed|Where-Object {$_.pluginId-eq 'codex-right-clearance@codex-ui-local'-and $_.installed})
 $bundleMatches=Test-BundleCache (Join-Path $bundleRoot 'plugins\codex-right-clearance') $bundleCache
 if($bundleInstalled.Count-ne 1-or $bundleInstalled[0].version-ne $bundleVersion-or -not $bundleMatches-or -not $bundleInstalled[0].enabled){
  $bundleOther=@($bundleCatalog.installed|Where-Object {$_.marketplaceName-eq 'codex-ui-local'-and $_.pluginId-ne 'codex-right-clearance@codex-ui-local'})
  if($bundleOther.Count){throw 'The local marketplace also contains other plugins; it was left unchanged.'}
  if($bundleInstalled.Count){& $bundleCli plugin marketplace remove 'codex-ui-local'|Out-Null;if($LASTEXITCODE-ne 0){throw 'Cannot refresh the clearance marketplace.'}}
  & $bundleCli plugin marketplace add $bundleRoot --json|Out-Null
  if($LASTEXITCODE-ne 0){throw 'Cannot register the bundled clearance marketplace.'}
  & $bundleCli plugin add 'codex-right-clearance@codex-ui-local' --json|Out-Null
  if($LASTEXITCODE-ne 0){throw 'Cannot install the clearance plugin.'}
 }
 $bundleSettings|Add-Member NoteProperty nativePetInstallation $bundleWidget -Force
 $bundleSettings.enabled=$true
 Save-BundleJson $bundleSettingsPath $bundleSettings
 $bundleControl=Join-Path $bundleCache 'scripts\Control.ps1'
 & powershell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File $bundleControl -Action Bootstrap
 if($LASTEXITCODE-ne 0){throw 'Cannot start the clearance worker.'}
 Write-Output 'GPT-Niang dynamic clearance installed. The original client and widget were left running. If this client has no local connection yet, it will take effect the next time you normally reopen Codex.'
} catch {
 $bundleFailure=$_.Exception.Message
 Save-BundleJson $bundleSettingsPath ($bundlePrevious|ConvertFrom-Json)
 throw $bundleFailure
}
