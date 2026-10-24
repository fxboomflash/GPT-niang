param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$buildRoot=Split-Path $PSScriptRoot -Parent
if(-not $OutputDirectory){$OutputDirectory=Join-Path (Split-Path $buildRoot -Parent) 'GPT-Niang-Dynamic-Clearance-release'}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if($OutputDirectory-eq $buildRoot-or $OutputDirectory.StartsWith($buildRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Place build output outside the source package.'}
& (Join-Path $PSScriptRoot 'Verify-Package.ps1')
if(-not $?){throw 'Package verification failed.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
$version=(Get-Content -LiteralPath (Join-Path $buildRoot 'package.json') -Raw|ConvertFrom-Json).version
$archive=Join-Path $OutputDirectory ('GPT-Niang-Dynamic-Clearance-v'+$version+'-windows.zip')
if(Test-Path -LiteralPath $archive){throw 'Release archive already exists; choose a new output directory.'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in Get-ChildItem -LiteralPath $buildRoot -File -Recurse -Force){
  $relative=$file.FullName.Substring($buildRoot.Length).TrimStart('\').Replace([char]92,[char]47)
  if($relative-match '(^|/)(\.git|node_modules|test-results|dist)(/|$)'){continue}
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.FullName,('GPT-Niang-Dynamic-Clearance/'+$relative),[IO.Compression.CompressionLevel]::Optimal)|Out-Null
 }
}finally{$zip.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'),($hash+'  '+[IO.Path]::GetFileName($archive)+"`n"),[Text.UTF8Encoding]::new($false))
[ordered]@{archive=$archive;sha256=$hash;upstream='T7moris/GPT-Niang';bundleVersion=$version}|ConvertTo-Json -Compress
