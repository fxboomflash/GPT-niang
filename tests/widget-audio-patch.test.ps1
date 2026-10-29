$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$apply=Join-Path $root 'scripts\Apply-WidgetAudioFix.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('niang-patch-'+[Guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app';$data=Join-Path $fixture 'data';$installation=Join-Path $app 'installation.json'
$null=[IO.Directory]::CreateDirectory((Join-Path $app 'runtime'));$null=[IO.Directory]::CreateDirectory($data)
try{
 Copy-Item -LiteralPath (Join-Path $root 'vendor\GPT-Niang\gpt-niang-usage\package.json') -Destination $app
 foreach($name in @('audio.ps1','ui-settings.ps1')){Copy-Item -LiteralPath (Join-Path $root ('vendor\GPT-Niang\gpt-niang-usage\runtime\'+$name)) -Destination (Join-Path $app 'runtime')}
 [IO.File]::WriteAllText($installation,(@{appDir=$app;dataDir=$data}|ConvertTo-Json))
 $preferences='{"soundVolume":0.37,"followHost":true}'
 [IO.File]::WriteAllText((Join-Path $data 'settings.json'),$preferences)
 $plan=& $apply -WidgetInstallation $installation -CheckOnly|ConvertFrom-Json
 if($plan.filesToUpdate.Count-ne 2-or -not $plan.widgetRestartRequired-or (Test-Path (Join-Path $data 'patch-backups'))){throw 'Read-only patch planning failed'}
 # Validate all targets before writing either of them.
 $ui=Join-Path $app 'runtime\ui-settings.ps1';$originalUi=[IO.File]::ReadAllBytes($ui)
 [IO.File]::AppendAllText($ui,"`n# unknown modification")
 $before=(Get-FileHash (Join-Path $app 'runtime\audio.ps1')).Hash
 $rejected=$false;try{& $apply -WidgetInstallation $installation|Out-Null}catch{$rejected=$true}
 if(-not $rejected-or (Get-FileHash (Join-Path $app 'runtime\audio.ps1')).Hash-ne $before){throw 'Unknown modifications were overwritten'}
 [IO.File]::WriteAllBytes($ui,$originalUi)
 $result=& $apply -WidgetInstallation $installation|ConvertFrom-Json
 if($result.updated.Count-ne 2-or -not $result.widgetRestartRequired){throw 'Known widget files were not patched'}
 if((Get-FileHash (Join-Path $result.backupDirectory 'runtime\audio.ps1')).Hash-ne $before){throw 'Original audio was not backed up'}
 if([IO.File]::ReadAllText((Join-Path $data 'settings.json'))-ne $preferences){throw 'Personal preferences changed'}
 $again=& $apply -WidgetInstallation $installation|ConvertFrom-Json
 if($again.updated.Count-ne 0-or $again.widgetRestartRequired){throw 'Reapplying the patch was not a no-op'}
 Write-Output 'PASS: read-only planning, all-target validation, unknown-change protection, backup, exact payload installation, preserved preferences and idempotency'
}finally{
 $absolute=[IO.Path]::GetFullPath($fixture);$allowed=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
 if(-not $absolute.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)-or [IO.Path]::GetFileName($absolute)-notlike 'niang-patch-*'){throw 'Unsafe fixture cleanup path'}
 Remove-Item -LiteralPath $absolute -Recurse -Force
}
