using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32;

// This module changes only the owned debugger registration. It never opens or
// controls an application process. Callers validate the package and helper first.
public static class ClearancePersistentRegistration {
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegCreateKeyEx(IntPtr key,string subkey,uint reserved,string cls,uint options,uint access,IntPtr security,out IntPtr opened,out uint disposition);
 [DllImport("advapi32.dll")] static extern int RegCloseKey(IntPtr key);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegDeleteKey(IntPtr key,string subkey);
 [DllImport("advapi32.dll",CharSet=CharSet.Unicode)] static extern int RegRenameKey(IntPtr key,string subkey,string newName);
 public sealed class Result {public bool RootWasVolatile;public bool PackageWasVolatile;public bool RootNonVolatile;public bool PackageNonVolatile;public bool Migrated;public string Migration;}
#if REGISTRATION_TEST
 public static bool FailAfterBackupRenameForTest;
 public static bool FailAfterActivationForTest;
#endif
 public static bool IsVolatile(RegistryKey key){
  string probe="ClearancePersistenceProbe-"+Guid.NewGuid().ToString("N");IntPtr opened;uint disposition;
  int code=RegCreateKeyEx(key.Handle.DangerousGetHandle(),probe,0,null,0,0x20019,IntPtr.Zero,out opened,out disposition);
  if(code==1021)return true;
  if(code!=0)throw new Win32Exception(code,"Cannot verify startup registry persistence");
  RegCloseKey(opened);
  if(disposition!=1)throw new InvalidOperationException("Unexpected existing persistence probe");
  code=RegDeleteKey(key.Handle.DangerousGetHandle(),probe);if(code!=0)throw new Win32Exception(code,"Cannot remove persistence probe");
  return false;
 }
 static bool Contains(string[] values,string value){foreach(string item in values)if(string.Equals(item,value,StringComparison.OrdinalIgnoreCase))return true;return false;}
 static string ReadOwnedPackage(RegistryKey key,string[] allowedDebuggers){
  string[] names=key.GetValueNames();
  if(key.SubKeyCount!=0||names.Length!=1||names[0]!=""||key.GetValueKind("")!=RegistryValueKind.String)throw new InvalidOperationException("Unexpected data in debugger registration; left unchanged");
  string debugger=key.GetValue("") as string;
  if(!Contains(allowedDebuggers,debugger))throw new InvalidOperationException("Another debugger owns this package; left unchanged");
  return debugger;
 }
 static Dictionary<string,string> ReadOwnedRoot(RegistryKey root,string[] allowedPackages,string[] allowedDebuggers){
  if(root.ValueCount!=0)throw new InvalidOperationException("Unexpected values in debugger root; left unchanged");
  var result=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  foreach(string name in root.GetSubKeyNames()){
   if(!Contains(allowedPackages,name))throw new InvalidOperationException("Volatile debugger root contains another package; left unchanged");
   using(var key=root.OpenSubKey(name))result.Add(name,ReadOwnedPackage(key,allowedDebuggers));
  }
  return result;
 }
 static bool Same(Dictionary<string,string> first,Dictionary<string,string> second){
  if(first.Count!=second.Count)return false;
  foreach(var item in first){string value;if(!second.TryGetValue(item.Key,out value)||value!=item.Value)return false;}
  return true;
 }
 static void Rename(RegistryKey parent,string from,string to){int code=RegRenameKey(parent.Handle.DangerousGetHandle(),from,to);if(code!=0)throw new Win32Exception(code,"Cannot commit startup registration migration");}
 static void Replace(RegistryKey parent,string name,Action<RegistryKey> populate,Func<RegistryKey,bool> originalUnchanged,Action<RegistryKey> validate){
  string id=Guid.NewGuid().ToString("N"),stage="CodexClearanceStage-"+id,backup="CodexClearanceBackup-"+id;
  bool moved=false,activated=false;
  try{
   using(var key=parent.CreateSubKey(stage,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None)){populate(key);validate(key);key.Flush();}
   using(var key=parent.OpenSubKey(name)){if(key==null||!originalUnchanged(key))throw new InvalidOperationException("Startup registration changed during migration; original retained");}
   Rename(parent,name,backup);moved=true;
#if REGISTRATION_TEST
   if(FailAfterBackupRenameForTest)throw new InvalidOperationException("Injected migration failure");
#endif
   Rename(parent,stage,name);activated=true;
#if REGISTRATION_TEST
   if(FailAfterActivationForTest)throw new InvalidOperationException("Injected post-activation failure");
#endif
   using(var key=parent.OpenSubKey(name,true)){validate(key);key.Flush();}
   using(var old=parent.OpenSubKey(backup)){if(old==null||!originalUnchanged(old))throw new InvalidOperationException("Backup changed during migration; retained for review");}
   parent.DeleteSubKeyTree(backup);moved=false;
  }catch{
   // A concurrently created foreign key is never removed to make rollback fit.
   if(moved&&activated){
    try{
     using(var current=parent.OpenSubKey(name)){if(current==null)throw new InvalidOperationException();validate(current);}
     using(var old=parent.OpenSubKey(backup)){if(old==null||!originalUnchanged(old))throw new InvalidOperationException();}
     Rename(parent,name,stage);activated=false;
    }catch{}
   }
   if(moved&&!activated){using(var current=parent.OpenSubKey(name)){if(current==null){Rename(parent,backup,name);moved=false;}}}
   throw;
  }finally{
   if(!activated){using(var pending=parent.OpenSubKey(stage)){if(pending!=null){pending.Close();parent.DeleteSubKeyTree(stage);}}}
  }
 }
 static void ValidatePersistentPackage(RegistryKey key,string debugger){
  if(IsVolatile(key)||ReadOwnedPackage(key,new[]{debugger})!=debugger)throw new InvalidOperationException("Persistent package registration did not verify");
 }
 public static Result Ensure(RegistryKey hive,string rootPath,string package,string debugger,string[] allowedPackages,string[] allowedDebuggers){
  if(hive==null||string.IsNullOrEmpty(rootPath)||!Contains(allowedPackages,package)||!Contains(allowedDebuggers,debugger))throw new ArgumentException("Explicit owned registration scope is required");
  int slash=rootPath.LastIndexOf('\\');if(slash<1||slash==rootPath.Length-1)throw new ArgumentException("Registry root parent is required");
  string parentPath=rootPath.Substring(0,slash),rootName=rootPath.Substring(slash+1);
  var result=new Result();
  using(var parent=hive.CreateSubKey(parentPath,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None)){
   using(var root=parent.OpenSubKey(rootName,true)){
    if(root!=null){
     result.RootWasVolatile=IsVolatile(root);
     using(var key=root.OpenSubKey(package,true)){if(key!=null){ReadOwnedPackage(key,allowedDebuggers);result.PackageWasVolatile=IsVolatile(key);}}
     if(result.RootWasVolatile){
      var original=ReadOwnedRoot(root,allowedPackages,allowedDebuggers);
      var desired=new Dictionary<string,string>(original,StringComparer.OrdinalIgnoreCase);desired[package]=debugger;
      Replace(parent,rootName,staged=>{
       foreach(var item in desired)using(var key=staged.CreateSubKey(item.Key,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None))key.SetValue("",item.Value,RegistryValueKind.String);
      },key=>Same(ReadOwnedRoot(key,allowedPackages,allowedDebuggers),original),key=>{
       if(IsVolatile(key)||!Same(ReadOwnedRoot(key,allowedPackages,allowedDebuggers),desired))throw new InvalidOperationException("Persistent root did not verify");
       foreach(var item in desired)using(var child=key.OpenSubKey(item.Key,true))ValidatePersistentPackage(child,item.Value);
      });
      result.Migrated=true;result.Migration="root-and-owned-packages";
     }else{
      if(result.PackageWasVolatile){
       string oldDebugger;using(var key=root.OpenSubKey(package))oldDebugger=ReadOwnedPackage(key,allowedDebuggers);
       Replace(root,package,staged=>staged.SetValue("",debugger,RegistryValueKind.String),key=>ReadOwnedPackage(key,allowedDebuggers)==oldDebugger,key=>ValidatePersistentPackage(key,debugger));
       result.Migrated=true;result.Migration="owned-package";
      }else using(var key=root.CreateSubKey(package,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None)){
       if(key.ValueCount!=0||key.SubKeyCount!=0)ReadOwnedPackage(key,allowedDebuggers);
       key.SetValue("",debugger,RegistryValueKind.String);key.Flush();
      }
     }
    }else using(var created=parent.CreateSubKey(rootName,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None))using(var key=created.CreateSubKey(package,RegistryKeyPermissionCheck.ReadWriteSubTree,RegistryOptions.None)){
     key.SetValue("",debugger,RegistryValueKind.String);key.Flush();created.Flush();result.Migration="created-persistent";
    }
   }
   using(var root=parent.OpenSubKey(rootName,true))using(var key=root.OpenSubKey(package,true)){
    result.RootNonVolatile=!IsVolatile(root);ValidatePersistentPackage(key,debugger);result.PackageNonVolatile=true;root.Flush();
   }
  }
  return result;
 }
}
