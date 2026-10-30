$ErrorActionPreference='Stop'
$nativeSource=Join-Path $PSScriptRoot '..\plugins\codex-right-clearance\native\PersistentStartupRegistration.cs'
Add-Type -TypeDefinition ("#define REGISTRATION_TEST`n"+(Get-Content -LiteralPath $nativeSource -Raw -Encoding UTF8))
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
public static class ClearanceTestHive {
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegLoadAppKey(string file,out IntPtr result,uint access,uint options,uint reserved);
 public static RegistryKey Open(string file){IntPtr key;int code=RegLoadAppKey(file,out key,0xf003f,1,0);if(code!=0)throw new System.ComponentModel.Win32Exception(code);return RegistryKey.FromHandle(new SafeRegistryHandle(key,true));}
}
'@
$testHome=Join-Path ([IO.Path]::GetTempPath()) ('clearance-registration-hives-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testHome -Force
$parentPath='Software\Microsoft\Windows\CurrentVersion'
$rootPath=$parentPath+'\PackagedAppXDebug'
$package='OpenAI.Codex_26.1023.6621.0_x64__2p2nqsd0c76g0'
$old='"C:\Fixture\OldLoader.exe"';$new='"C:\Fixture\NewLoader.exe"'
$allowedPackages=[string[]]@($package);$allowedDebuggers=[string[]]@($old,$new)
$cases=@()
function Assert($condition,$message){if(-not $condition){throw $message}}
function CreateLegacy($hive){
 $parent=$hive.CreateSubKey($parentPath);$parent.Dispose()
 $root=$hive.CreateSubKey($rootPath,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[Microsoft.Win32.RegistryOptions]::Volatile)
 $key=$root.CreateSubKey($package,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[Microsoft.Win32.RegistryOptions]::Volatile)
 $key.SetValue('',$old);$key.Dispose();$root.Dispose()
}
function Ensure($hive){return [ClearancePersistentRegistration]::Ensure($hive,$rootPath,$package,$new,$allowedPackages,$allowedDebuggers)}
function ValueOf($hive,$path){$key=$hive.OpenSubKey($path);if($key){try{return $key.GetValue('')}finally{$key.Dispose()}}}

# Actual Windows hive unload reproduces the old registration loss without a reboot.
$file=Join-Path $testHome 'legacy.hive';$hive=[ClearanceTestHive]::Open($file)
try{CreateLegacy $hive;$key=$hive.OpenSubKey($rootPath);try{Assert ([ClearancePersistentRegistration]::IsVolatile($key)) 'Legacy fixture must be volatile'}finally{$key.Dispose()};$hive.Flush()}finally{$hive.Dispose()}
$hive=[ClearanceTestHive]::Open($file)
try{$missing=$null-eq (ValueOf $hive ($rootPath+'\'+$package));Assert $missing 'Old volatile registration unexpectedly survived hive unload';$cases+=@{name='legacy-registration-lost-after-real-hive-unload';passed=$true}}finally{$hive.Dispose()}

$file=Join-Path $testHome 'migrated.hive';$hive=[ClearanceTestHive]::Open($file)
try{
 CreateLegacy $hive;$result=Ensure $hive
 Assert ($result.RootWasVolatile-and $result.PackageWasVolatile-and $result.RootNonVolatile-and $result.PackageNonVolatile-and $result.Migrated) 'Root migration did not verify'
 Assert ((ValueOf $hive ($rootPath+'\'+$package))-eq $new) 'Loader changed incorrectly'
 $cases+=@{name='migrate-owned-volatile-root-and-package';passed=$true;result=$result}
 $again=Ensure $hive;Assert (-not $again.Migrated) 'Repeated ensure must be idempotent'
 $cases+=@{name='repeated-registration-is-idempotent';passed=$true};$hive.Flush()
}finally{$hive.Dispose()}
$hive=[ClearanceTestHive]::Open($file)
try{
 Assert ((ValueOf $hive ($rootPath+'\'+$package))-eq $new) 'Persistent registration was lost after real hive unload'
 $key=$hive.OpenSubKey($rootPath);try{Assert (-not [ClearancePersistentRegistration]::IsVolatile($key)) 'Reloaded root must remain persistent'}finally{$key.Dispose()}
 $cases+=@{name='migrated-registration-survives-real-hive-unload-reload';passed=$true}
}finally{$hive.Dispose()}

$file=Join-Path $testHome 'package-only.hive';$hive=[ClearanceTestHive]::Open($file)
try{
 $root=$hive.CreateSubKey($rootPath);$key=$root.CreateSubKey($package,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[Microsoft.Win32.RegistryOptions]::Volatile);$key.SetValue('',$old);$key.Dispose()
 $foreign=$root.CreateSubKey('Another.Application');$foreign.SetValue('','untouched');$foreign.Dispose();$root.Dispose()
 $result=Ensure $hive;Assert ($result.Migration-eq 'owned-package'-and $result.PackageNonVolatile) 'Package-only migration failed'
 Assert ((ValueOf $hive ($rootPath+'\Another.Application'))-eq 'untouched') 'Foreign persistent sibling was changed'
 $cases+=@{name='migrate-only-owned-package-preserves-foreign-sibling';passed=$true}
}finally{$hive.Dispose()}

foreach($kind in @('foreign-root-package','foreign-debugger','unexpected-root-values','unexpected-package-values')){
 $hive=[ClearanceTestHive]::Open((Join-Path $testHome ($kind+'.hive')))
 try{
  CreateLegacy $hive;$root=$hive.OpenSubKey($rootPath,$true)
  try{
   switch($kind){
    'foreign-root-package' {$key=$root.CreateSubKey('Another.Application',[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[Microsoft.Win32.RegistryOptions]::Volatile);$key.SetValue('','foreign');$key.Dispose()}
    'foreign-debugger' {$key=$root.OpenSubKey($package,$true);$key.SetValue('','foreign');$key.Dispose()}
    'unexpected-root-values' {$root.SetValue('foreign-setting','keep')}
    'unexpected-package-values' {$key=$root.OpenSubKey($package,$true);$key.SetValue('foreign-setting','keep');$key.Dispose()}
   }
  }finally{$root.Dispose()}
  $rejected=$false;try{$null=Ensure $hive}catch{$rejected=$true};Assert $rejected ($kind+' must be rejected')
  $root=$hive.OpenSubKey($rootPath);try{Assert ([ClearancePersistentRegistration]::IsVolatile($root)) 'Rejected original root changed';Assert (-not @($root.GetSubKeyNames()|Where-Object {$_-like 'CodexClearance*'}).Count) 'Rejected migration left staging artifacts'}finally{$root.Dispose()}
  if($kind-eq 'foreign-debugger'){Assert ((ValueOf $hive ($rootPath+'\'+$package))-eq 'foreign') 'Foreign debugger overwritten'}
  $cases+=@{name=('refuse-'+$kind);passed=$true}
 }finally{$hive.Dispose()}
}

foreach($step in @('backup','activation')){
 $hive=[ClearanceTestHive]::Open((Join-Path $testHome ('rollback-'+$step+'.hive')))
 try{
  CreateLegacy $hive
  [ClearancePersistentRegistration]::FailAfterBackupRenameForTest=$step-eq 'backup'
  [ClearancePersistentRegistration]::FailAfterActivationForTest=$step-eq 'activation'
  $failed=$false;try{$null=Ensure $hive}catch{$failed=$true}
  Assert $failed 'Injected migration failure must propagate'
  Assert ((ValueOf $hive ($rootPath+'\'+$package))-eq $old) 'Original debugger not restored'
  $root=$hive.OpenSubKey($rootPath);try{Assert ([ClearancePersistentRegistration]::IsVolatile($root)) 'Original volatile key not restored'}finally{$root.Dispose()}
  $parent=$hive.OpenSubKey($parentPath);try{Assert (-not @($parent.GetSubKeyNames()|Where-Object {$_-like 'CodexClearance*'}).Count) 'Rollback left temporary registry keys'}finally{$parent.Dispose()}
  $cases+=@{name=('rollback-after-'+$step);passed=$true}
 }finally{[ClearancePersistentRegistration]::FailAfterBackupRenameForTest=$false;[ClearancePersistentRegistration]::FailAfterActivationForTest=$false;$hive.Dispose()}
}

$file=Join-Path $testHome 'new.hive';$hive=[ClearanceTestHive]::Open($file)
try{$result=Ensure $hive;Assert ($result.RootNonVolatile-and $result.PackageNonVolatile) 'New registration not persistent';$cases+=@{name='new-registration-created-persistent';passed=$true}}finally{$hive.Dispose()}
$report=[ordered]@{time=[DateTime]::UtcNow.ToString('o');passed=$true;actualWindowsRegistryHives=$true;realHiveUnloadReload=$true;sourceSha256=(Get-FileHash -LiteralPath $nativeSource -Algorithm SHA256).Hash;cases=$cases;clientTouched=$false;windowsRegistryNamespaceTouched=$false;testDirectory=$testHome;windowsRebootPerformed=$false}
$report|ConvertTo-Json -Depth 8
