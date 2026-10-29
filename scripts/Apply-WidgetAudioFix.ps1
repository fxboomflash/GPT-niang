param([Parameter(Mandatory=$true)][string]$WidgetInstallation,[switch]$CheckOnly)
$ErrorActionPreference='Stop'
$patchRoot=Join-Path (Split-Path $PSScriptRoot -Parent) 'patches\widget-audio'
$manifest=Get-Content -LiteralPath (Join-Path $patchRoot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$record=Get-Content -LiteralPath $WidgetInstallation -Raw -Encoding UTF8|ConvertFrom-Json
if(-not $record.appDir-or -not $record.dataDir){throw 'The widget installation record has no application/data directory.'}
$appRoot=[IO.Path]::GetFullPath($record.appDir).TrimEnd('\')
$installationRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($WidgetInstallation)).TrimEnd('\')
if($installationRoot-ine $appRoot){throw 'The installation record does not belong to this widget directory.'}
$package=Get-Content -LiteralPath (Join-Path $appRoot 'package.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($package.version-ne $manifest.upstreamVersion){throw 'This audio fix supports GPT-Niang 1.3.5 only. The installed version was left unchanged.'}
function AudioFixHash([string]$Path){
 $hash=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($Path)
 try{return [BitConverter]::ToString($hash.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$hash.Dispose()}
}
$plan=@()
foreach($entry in $manifest.files){
 if($entry.path-notin @('runtime/audio.ps1','runtime/ui-settings.ps1')){throw 'Unexpected audio patch target.'}
 $payload=Join-Path $patchRoot $entry.path;$target=Join-Path $appRoot $entry.path
 if((AudioFixHash $payload)-ine $entry.sha256){throw ('Audio patch payload checksum failed: '+$entry.path)}
 $current=AudioFixHash $target
 if($current-ieq $entry.sha256){continue}
 if($current-notin @($entry.acceptedSha256)){throw ('An unrecognized widget modification was left unchanged: '+$entry.path)}
 $plan+=@{path=$entry.path;payload=$payload;target=$target;original=$current}
}
if($CheckOnly){[ordered]@{ok=$true;readOnly=$true;patch=$manifest.id;filesToUpdate=@($plan|ForEach-Object {$_.path});widgetRestartRequired=($plan.Count-gt 0)}|ConvertTo-Json -Compress;return}
$applied=@();$backupRoot=$null
if($plan.Count){
 $backupRoot=Join-Path ([IO.Path]::GetFullPath($record.dataDir)) ('patch-backups\'+$manifest.id+'-'+[Guid]::NewGuid().ToString('N'))
 foreach($entry in $plan){
  $backup=Join-Path $backupRoot $entry.path
  $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backup))
  [IO.File]::Copy($entry.target,$backup,$false)
 }
 try{
  foreach($entry in $plan){
   if((AudioFixHash $entry.target)-ine $entry.original){throw 'The widget changed during patching. Retry after its update finishes.'}
   $temporary=$entry.target+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
   try{
    [IO.File]::Copy($entry.payload,$temporary,$false)
    [IO.File]::Replace($temporary,$entry.target,[NullString]::Value)
    $applied+=,$entry
    if((AudioFixHash $entry.target)-ine $manifest.files.Where({$_.path-eq $entry.path})[0].sha256){throw 'The installed audio patch checksum did not match.'}
   }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
  }
 }catch{
  foreach($entry in $applied){[IO.File]::Copy((Join-Path $backupRoot $entry.path),$entry.target,$true)}
  throw
 }
}
[ordered]@{ok=$true;patch=$manifest.id;updated=@($applied|ForEach-Object {$_.path});backupDirectory=$backupRoot;widgetRestartRequired=($applied.Count-gt 0);clientRestarted=$false;widgetRestarted=$false}|ConvertTo-Json -Compress
