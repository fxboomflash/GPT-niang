$ErrorActionPreference='Stop'
$verifyRoot=Split-Path $PSScriptRoot -Parent
$verifyErrors=@()
foreach($file in Get-ChildItem -LiteralPath $verifyRoot -Filter '*.ps1' -Recurse -File -Force){
 $tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8),$file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){$verifyErrors+=($file.Name+': '+(($errors|Select-Object -First 3|ForEach-Object { $_.Message.Substring(0,[Math]::Min(160,$_.Message.Length))})-join '; '))}
}
if($verifyErrors.Count){throw ($verifyErrors-join "`n")}
foreach($file in Get-ChildItem -LiteralPath $verifyRoot -Filter '*.json' -Recurse -File -Force){$null=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json}
$required=@('README.md','LICENSE','NOTICE.md','UPSTREAM.json','Install.ps1','Disable.ps1','.agents\plugins\marketplace.json','plugins\codex-right-clearance\native\NativePetGeometry.cs','vendor\GPT-Niang\LICENSE','vendor\GPT-Niang\gpt-niang-usage\assets\CHARACTER-NOTICE.txt')
foreach($relative in $required){if(-not (Test-Path -LiteralPath (Join-Path $verifyRoot $relative) -PathType Leaf)){throw ('Missing required file: '+$relative)}}
foreach($line in Get-Content -LiteralPath (Join-Path $verifyRoot 'UPSTREAM-FILES.sha256') -Encoding UTF8){
 if($line-notmatch '^([0-9A-Fa-f]{64})  (.+)$'){throw 'Invalid upstream file manifest.'}
 $expected=$Matches[1];$relative=$Matches[2]
 if(-not $relative.StartsWith('vendor/GPT-Niang/')){throw 'Unexpected upstream file location.'}
 $file=[IO.Path]::GetFullPath((Join-Path $verifyRoot $relative))
 if(-not $file.StartsWith((Join-Path $verifyRoot 'vendor\GPT-Niang')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Upstream file path escaped its directory.'}
 if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash-ne $expected){throw ('Upstream file was modified: '+$relative)}
}
$forbidden=@(Get-ChildItem -LiteralPath $verifyRoot -Recurse -File -Force|Where-Object {$_.Name-in @('installation.json','settings.json','runtime.json','presence.json','status.json','auth.json','config.toml')-or $_.Extension-in @('.exe','.dll','.log','.jsonl','.bak','.tmp')})
if($forbidden.Count){throw ('Runtime/private/build files must not ship: '+($forbidden.Name-join ', '))}
. (Join-Path $PSScriptRoot 'Bundle.Common.ps1')
$verifyNode=Find-BundleNode
Push-Location $verifyRoot
try{& $verifyNode --test 'tests/geometry.test.cjs';if($LASTEXITCODE-ne 0){throw 'Package regression tests failed.'}}finally{Pop-Location}
[ordered]@{passed=$true;powerShellSyntax=$true;jsonSyntax=$true;requiredNotices=$true;runtimeFilesExcluded=$true;fileCount=@(Get-ChildItem -LiteralPath $verifyRoot -Recurse -File -Force).Count}|ConvertTo-Json -Compress
