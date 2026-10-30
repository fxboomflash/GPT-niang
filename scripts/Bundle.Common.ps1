function Get-BundleJson([string]$Path) {
 if(Test-Path -LiteralPath $Path -PathType Leaf){return Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json}
 return $null
}
function Find-BundleNode {
 $candidates=@($env:CODEX_CLEARANCE_NODE,(Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'))
 $command=Get-Command node.exe -ErrorAction SilentlyContinue
 if($command){$candidates+=$command.Source}
 foreach($candidate in $candidates){if($candidate-and (Test-Path -LiteralPath $candidate -PathType Leaf)){
  $major=& $candidate -p 'parseInt(process.versions.node)'
  if($LASTEXITCODE-eq 0-and [int]$major-ge 22){return (Resolve-Path -LiteralPath $candidate).ProviderPath}
 }}
 throw 'Node.js 22 or newer was not found. Install Node.js or set CODEX_CLEARANCE_NODE.'
}
function Find-BundleCli {
 $command=Get-Command codex.exe -ErrorAction SilentlyContinue
 if($command){return $command.Source}
 $dir=Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
 if(Test-Path -LiteralPath $dir){$item=Get-ChildItem -LiteralPath $dir -Filter codex.exe -Recurse -File|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1;if($item){return $item.FullName}}
 throw 'Codex CLI was not found. Install and open the Codex desktop app first.'
}
function Find-BundleWidget([string]$Explicit,[string]$Root) {
 if($Explicit){if(-not (Test-Path -LiteralPath $Explicit -PathType Leaf)){throw 'The specified GPT-Niang installation.json does not exist.'};return (Resolve-Path -LiteralPath $Explicit).ProviderPath}
 $binding=Get-BundleJson (Join-Path $env:LOCALAPPDATA 'GPTNiangUsage\update-agent\binding.json')
 $candidates=@()
 if($binding.appDir){$candidates+=Join-Path $binding.appDir 'installation.json'}
 $candidates+=Join-Path $Root 'vendor\GPT-Niang\gpt-niang-usage\installation.json'
 foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate -PathType Leaf){return (Resolve-Path -LiteralPath $candidate).ProviderPath}}
 return $null
}
function Get-BundleHome {
 if($env:CODEX_HOME){return [IO.Path]::GetFullPath($env:CODEX_HOME)}
 return (Join-Path $env:USERPROFILE '.codex')
}
function Save-BundleJson([string]$Path,$Value) {
 New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force|Out-Null
 $temp=$Path+'.'+$PID+'.tmp'
 [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Test-BundleCache([string]$Source,[string]$Cache) {
 if(-not (Test-Path -LiteralPath $Cache -PathType Container)){return $false}
 foreach($file in Get-ChildItem -LiteralPath $Source -Recurse -File -Force){
  $relative=$file.FullName.Substring($Source.Length).TrimStart('\')
  $cached=Join-Path $Cache $relative
  if(-not (Test-Path -LiteralPath $cached -PathType Leaf)){return $false}
  if((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash-ne (Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash){return $false}
 }
 return $true
}
function Assert-BundleStartupRegistration([string[]]$Output,[int]$ExitCode) {
 if($ExitCode-ne 0){throw 'The startup registration could not be configured. The client was left running.'}
 try{$result=($Output-join "`n")|ConvertFrom-Json}catch{throw 'The startup registration returned an invalid result.'}
 if($result.state-eq 'registered'){$persistence=$result.registration.registryPersistence}
 elseif($result.state-eq 'persistent-registration-verified'){$persistence=$result.registryPersistence}
 else{throw 'The startup registration could not be verified.'}
 if($persistence.rootNonVolatile-ne $true-or $persistence.packageNonVolatile-ne $true){throw 'The startup registration is not persistent.'}
 return $result.state
}
