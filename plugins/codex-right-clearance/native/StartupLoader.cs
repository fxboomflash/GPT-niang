using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

public static class StartupLoader {
 const string Family="OpenAI.Codex_2p2nqsd0c76g0";
 static readonly JavaScriptSerializer Json=new JavaScriptSerializer();
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenThread(uint access,bool inherit,int tid);
 [DllImport("kernel32.dll")] static extern int GetProcessIdOfThread(IntPtr thread);
 [DllImport("kernel32.dll")] static extern uint ResumeThread(IntPtr thread);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr process,int flags,StringBuilder name,ref int size);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] static extern int GetPackageFamilyName(IntPtr process,ref int size,StringBuilder name);
 [StructLayout(LayoutKind.Sequential)] struct FileIdentity {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow;}
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr file,out FileIdentity identity);
 static string BaseDir { get{return Path.GetDirectoryName(typeof(StartupLoader).Assembly.Location);} }
 static Dictionary<string,object> Load(string file){return Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(file,Encoding.UTF8));}
 static void Log(string data,string state,int pid,int port,string reason){try{File.AppendAllText(Path.Combine(data,"startup-events.jsonl"),Json.Serialize(new{time=DateTime.UtcNow.ToString("o"),state=state,pid=pid,port=port,reason=reason})+"\n",Encoding.UTF8);}catch{}}
 static bool Resume(int pid,int tid){IntPtr thread=OpenThread(0x42,false,tid);if(thread==IntPtr.Zero)return false;try{return GetProcessIdOfThread(thread)==pid&&ResumeThread(thread)!=uint.MaxValue;}finally{CloseHandle(thread);}}
 static int Number(string[] args,string flag){int at=Array.IndexOf(args,flag),value;return at>=0&&at+1<args.Length&&int.TryParse(args[at+1],out value)&&value>0?value:0;}
 static string FileHash(string file){using(var stream=File.OpenRead(file))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");}
 // Store packages can be junctions onto another drive. Compare the actual file, not the spelling of its path.
 static bool SameFile(string first,string second){
  if(string.Equals(Path.GetFullPath(first),Path.GetFullPath(second),StringComparison.OrdinalIgnoreCase))return true;
  using(var a=File.Open(first,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
  using(var b=File.Open(second,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
   FileIdentity x,y;if(!GetFileInformationByHandle(a.SafeFileHandle.DangerousGetHandle(),out x)||!GetFileInformationByHandle(b.SafeFileHandle.DangerousGetHandle(),out y))throw new InvalidOperationException("Cannot verify the startup file identity");
   return x.volume==y.volume&&x.indexHigh==y.indexHigh&&x.indexLow==y.indexLow;
  }
 }
 static void WriteSettings(string file,Dictionary<string,object> value){string temp=file+"."+Process.GetCurrentProcess().Id+".tmp";File.WriteAllText(temp,Json.Serialize(value),new UTF8Encoding(false));if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);}
 static void Watchdog(int pid,int tid,string signal){try{using(EventWaitHandle done=EventWaitHandle.OpenExisting(signal)){if(done.WaitOne(6000))return;}}catch{}Resume(pid,tid);}
 public static int Main(string[] args){
  // No argument-less execution may create another process.
  if(args.Length==4&&args[0]=="--watchdog"){int pid,tid;if(int.TryParse(args[1],out pid)&&int.TryParse(args[2],out tid))Watchdog(pid,tid,args[3]);return 0;}
  int targetPid=Number(args,"-p"),targetTid=Number(args,"-tid");if(targetPid==0||targetTid==0)return 2;
  string data=null,signal="Local\\CodexClearanceStartup-"+Guid.NewGuid().ToString("N");EventWaitHandle finished=null;IntPtr process=IntPtr.Zero;int port=0;
  try{
   finished=new EventWaitHandle(false,EventResetMode.ManualReset,signal);
   var guard=new ProcessStartInfo(typeof(StartupLoader).Assembly.Location,"--watchdog "+targetPid+" "+targetTid+" "+signal){UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden};Process.Start(guard);
   IntPtr startingThread=OpenThread(0x40,false,targetTid);if(startingThread==IntPtr.Zero)throw new InvalidOperationException("Cannot verify the startup thread");try{if(GetProcessIdOfThread(startingThread)!=targetPid)throw new InvalidOperationException("Startup thread belongs to a different process");}finally{CloseHandle(startingThread);}
   process=OpenProcess(0x1038,false,targetPid);if(process==IntPtr.Zero)throw new InvalidOperationException("Cannot inspect the new app process");
   int size=32768;var image=new StringBuilder(size);if(!QueryFullProcessImageName(process,0,image,ref size))throw new InvalidOperationException("Cannot verify startup image");
   var config=Load(Path.Combine(BaseDir,"loader-config.json"));data=Convert.ToString(config["dataDirectory"]);
   string expected=Convert.ToString(config["targetExecutable"]);
   if(!SameFile(image.ToString(),expected)){Log(data,"skipped-other-image",targetPid,0,null);return 0;}
#if !TEST_TARGET
   int familySize=256;var family=new StringBuilder(familySize);if(GetPackageFamilyName(process,ref familySize,family)!=0||family.ToString()!=Family)throw new InvalidOperationException("Unexpected startup package");
#endif
   if(!string.Equals(FileHash(expected),Convert.ToString(config["targetSha256"]),StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Startup executable changed; re-register the plugin");
   using(var target=Process.GetProcessById(targetPid)){if((DateTime.UtcNow-target.StartTime.ToUniversalTime()).TotalSeconds>20)throw new InvalidOperationException("Only a newly starting process may be configured");}
   string clientConfig=File.ReadAllText(Convert.ToString(config["codexConfigFile"]),Encoding.UTF8);
   var plugin=Regex.Match(clientConfig,@"(?m)^\[plugins\.""codex-right-clearance@codex-ui-local""\][ \t]*\r?\n(?<body>[\s\S]*?)(?=^\[|\z)");
   if(!plugin.Success||!Regex.IsMatch(plugin.Groups["body"].Value,@"(?m)^enabled\s*=\s*true\s*(?:#.*)?$")){Log(data,"plugin-not-loaded",targetPid,0,null);return 0;}
   string settingsFile=Path.Combine(data,"settings.json");var settings=Load(settingsFile);
   if(!settings.ContainsKey("enabled")||!Convert.ToBoolean(settings["enabled"])){Log(data,"plugin-disabled",targetPid,0,null);return 0;}
   string command=StartupParameters.ReadCommand(process);
   if(Regex.IsMatch(command,@"(?:^|\s)--type(?:=|\s)")){Log(data,"skipped-child",targetPid,0,null);return 0;}
   if(Regex.IsMatch(command,@"(?:^|\s)--remote-debugging-port=\d+")){Log(data,"already-configured",targetPid,0,null);return 0;}
   port=settings.ContainsKey("debugPort")?Convert.ToInt32(settings["debugPort"]):19328;if(port<19327||port>19426)throw new InvalidOperationException("Invalid loopback port");
   var occupied=new HashSet<int>();foreach(var endpoint in IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners())occupied.Add(endpoint.Port);
   if(occupied.Contains(port)){port=0;for(int candidate=19327;candidate<=19426;candidate++)if(!occupied.Contains(candidate)){port=candidate;break;}if(port==0)throw new InvalidOperationException("No loopback port available");}
   settings["debugPort"]=port;settings["autoRestart"]=false;WriteSettings(settingsFile,settings);
   StartupParameters.Append(process," --remote-debugging-address=127.0.0.1 --remote-debugging-port="+port);
   Log(data,"startup-configured",targetPid,port,null);return 0;
  }catch(Exception error){if(data!=null)Log(data,"startup-skipped",targetPid,port,error.Message);return 1;}
  finally{if(process!=IntPtr.Zero)CloseHandle(process);if(Resume(targetPid,targetTid)&&finished!=null)finished.Set();if(finished!=null)finished.Dispose();}
 }
}
