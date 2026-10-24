param([ValidateSet('Ensure','Remove','Status')][string]$Action='Status',[string]$HomeDirectory)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition-eq 'Desktop'){$env:PSModulePath=@((Join-Path $PSHOME 'Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))-join ';'}
Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -Force -ErrorAction Stop
if(-not $HomeDirectory){$HomeDirectory=$env:CODEX_HOME}
if(-not $HomeDirectory){$HomeDirectory=Join-Path $env:USERPROFILE '.codex'}
$homePath=(Resolve-Path -LiteralPath $HomeDirectory).ProviderPath
for($linkDepth=0;$linkDepth-lt 8;$linkDepth++){
 $homeItem=Get-Item -LiteralPath $homePath
 if(-not $homeItem.LinkType-or -not $homeItem.Target){break}
 $homeTarget=@($homeItem.Target)[0]
 if(-not [IO.Path]::IsPathRooted($homeTarget)){$homeTarget=Join-Path (Split-Path -Parent $homePath) $homeTarget}
 $homePath=(Resolve-Path -LiteralPath $homeTarget).ProviderPath
}
$data=Join-Path $homePath 'plugin-data\codex-right-clearance-v3'
$recordPath=Join-Path $data 'startup-registration.json'
$utf8=[Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $data -Force|Out-Null
function ReadRecord {if(Test-Path -LiteralPath $recordPath){Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8|ConvertFrom-Json}}
function SaveRecord($record){[IO.File]::WriteAllText($recordPath,($record|ConvertTo-Json -Depth 8),$utf8)}
function DebugRegistry([string]$name){
 $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\PackagedAppXDebug\'+$name
 if(Test-Path -LiteralPath $key){$item=Get-Item -LiteralPath $key;$values=[ordered]@{};foreach($property in $item.GetValueNames()){$values[$property]=$item.GetValue($property)};return $values}
 return @{}
}
$previous=ReadRecord
if($Action-eq 'Status'){[ordered]@{registration=$previous;registry=$(if($previous){DebugRegistry $previous.packageFullName})}|ConvertTo-Json -Depth 8 -Compress;exit 0}
if(-not ('ClearancePackageDebug' -as [type])){
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[ComImport,Guid("F27C3930-8029-4AD1-94E3-3DBA417810C1"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IClearancePackageDebug {
 [PreserveSig] int EnableDebugging([MarshalAs(UnmanagedType.LPWStr)] string package,[MarshalAs(UnmanagedType.LPWStr)] string debugger,IntPtr environment);
 [PreserveSig] int DisableDebugging([MarshalAs(UnmanagedType.LPWStr)] string package);
}
public static class ClearancePackageDebug {
 [StructLayout(LayoutKind.Sequential)] struct FileIdentity {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr file,out FileIdentity identity);
 public static bool SameFile(string first,string second){try{using(var a=System.IO.File.OpenRead(first))using(var b=System.IO.File.OpenRead(second)){FileIdentity x,y;return GetFileInformationByHandle(a.SafeFileHandle.DangerousGetHandle(),out x)&&GetFileInformationByHandle(b.SafeFileHandle.DangerousGetHandle(),out y)&&x.volume==y.volume&&x.indexHigh==y.indexHigh&&x.indexLow==y.indexLow;}}catch{return false;}}
 public static int Set(string package,string debugger,bool enable){object instance=Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("B1AEC16F-2383-4852-B0E9-8F0B1DC66B4D")));try{var settings=(IClearancePackageDebug)instance;return enable?settings.EnableDebugging(package,debugger,IntPtr.Zero):settings.DisableDebugging(package);}finally{Marshal.FinalReleaseComObject(instance);}}
}
'@
}
function CurrentDebuggerPath($values){
 $value=[string]$values['']
 if($value-match '^"([^"\r\n]+\.exe)"$'){return $Matches[1]}
 if($value-match '^[^"\r\n]+\.exe$'){return $value}
 return $null
}
function OwnDebugger($values){
 $current=CurrentDebuggerPath $values
 return ($previous-and $previous.helper-and $current-and [ClearancePackageDebug]::SameFile($current,$previous.helper))
}
if($Action-eq 'Remove'){
 if(-not $previous-or -not $previous.enabled){[ordered]@{state='not-registered'}|ConvertTo-Json -Compress;exit 0}
 $existing=DebugRegistry $previous.packageFullName
 if($existing.Count-and -not (OwnDebugger $existing)){throw 'A different debugger is now registered; it was left unchanged.'}
 $result=[ClearancePackageDebug]::Set($previous.packageFullName,$null,$false)
 if($result-lt 0){throw ('Windows startup registration removal failed: 0x'+$result.ToString('X8'))}
 $previous.enabled=$false;$previous.time=[DateTime]::UtcNow.ToString('o');SaveRecord $previous
 [ordered]@{state='removed';clientClosed=$false}|ConvertTo-Json -Compress;exit 0
}
$settings=Get-Content -LiteralPath (Join-Path $data 'settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($settings.enabled-ne $true){[ordered]@{state='plugin-disabled'}|ConvertTo-Json -Compress;exit 0}
$package=Get-AppxPackage -Name OpenAI.Codex|Sort-Object Version -Descending|Select-Object -First 1
if(-not $package-or $package.PackageFamilyName-ne 'OpenAI.Codex_2p2nqsd0c76g0'){throw 'The registered Codex package was not found.'}
$target=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if((Get-AuthenticodeSignature -LiteralPath $target).Status-ne 'Valid'){throw 'The original client signature did not pass validation.'}
$native=Join-Path (Split-Path -Parent $PSScriptRoot) 'native'
$sources=@((Join-Path $native 'StartupParameters.cs'),(Join-Path $native 'StartupLoader.cs'))
$sourceHashes=@($sources|ForEach-Object {(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash})
$sourceId=($sourceHashes-join '').Substring(0,12)+'-'+$sourceHashes[1].Substring(0,12)
$nativeHome=Join-Path $data ('startup-loader\'+$sourceId)
New-Item -ItemType Directory -Path $nativeHome -Force|Out-Null
$helper=Join-Path $nativeHome 'StartupLoader.exe'
if(-not (Test-Path -LiteralPath $helper)){
 $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 if(-not (Test-Path -LiteralPath $compiler)){throw 'The existing Windows .NET compiler was not found.'}
 $compilerOutput=& $compiler /nologo /target:winexe /platform:x64 /r:System.Web.Extensions.dll ('/out:'+$helper) @sources 2>&1
 if($LASTEXITCODE-ne 0){throw ('Local startup helper compilation failed: '+($compilerOutput|Out-String))}
}
$config=[ordered]@{targetExecutable=$target;targetSha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash;dataDirectory=$data;codexConfigFile=(Join-Path $homePath 'config.toml')}
[IO.File]::WriteAllText((Join-Path $nativeHome 'loader-config.json'),($config|ConvertTo-Json),$utf8)
$existing=DebugRegistry $package.PackageFullName
if($existing.Count){
 if(-not (OwnDebugger $existing)){throw 'This package already has another startup debugger; it was left unchanged.'}
}
if($previous-and $previous.enabled-and $previous.packageFullName-eq $package.PackageFullName-and $existing.Count-and [ClearancePackageDebug]::SameFile((CurrentDebuggerPath $existing),$helper)){
 $previous.helper=CurrentDebuggerPath $existing;$previous.helperSha256=(Get-FileHash -LiteralPath $previous.helper -Algorithm SHA256).Hash;SaveRecord $previous
 [ordered]@{state='already-registered';helper=$previous.helper}|ConvertTo-Json -Compress;exit 0
}
$result=[ClearancePackageDebug]::Set($package.PackageFullName,('"'+$helper+'"'),$true)
if($result-lt 0){throw ('Windows startup registration failed: 0x'+$result.ToString('X8'))}
$record=[ordered]@{time=[DateTime]::UtcNow.ToString('o');enabled=$true;packageFullName=$package.PackageFullName;helper=$helper;helperSha256=(Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash;registryKey=('HKCU:\Software\Microsoft\Windows\CurrentVersion\PackagedAppXDebug\'+$package.PackageFullName);clientFilesModified=$false;clientClosed=$false;actualCodexColdStartVerified=$false;mechanism='Windows per-package startup debugger; resumes the original process after configuring startup arguments.'}
SaveRecord $record
[ordered]@{state='registered';registration=$record;registry=(DebugRegistry $package.PackageFullName)}|ConvertTo-Json -Depth 8 -Compress
