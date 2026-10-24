using System;
using System.IO;
using System.Collections.Generic;
using System.Diagnostics;
using System.Management;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;

// Read-only geometry adapter. Never moves, activates, closes, or opens any window.
public static class NativePetGeometry {
 [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)] struct Point {public int X,Y;}
 [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref Point p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int attribute,out int value,int size);
 [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h,int attribute,out Rect value,int size);
 static JavaScriptSerializer json=new JavaScriptSerializer();
 static int verifiedPid; static long verifiedStarted; static string verifiedScript;
 static double Number(Dictionary<string,object> request,string key){return Convert.ToDouble(request[key]);}
 static object Box(Rect r){return new{left=r.Left,top=r.Top,right=r.Right,bottom=r.Bottom,width=r.Right-r.Left,height=r.Bottom-r.Top};}
 static bool Visible(IntPtr h){int cloaked;return IsWindowVisible(h)&&!IsIconic(h)&&(DwmGetWindowAttribute(h,14,out cloaked,4)!=0||cloaked==0);}
 static object Sample(Dictionary<string,object> request){
  var widget=new IntPtr(Convert.ToInt64(request["widget"]));var host=new IntPtr(Convert.ToInt64(request["host"]));
  int expectedPid=Convert.ToInt32(request["pid"]),hostPid=Convert.ToInt32(request["hostPid"]);
  uint pid,hpid;GetWindowThreadProcessId(widget,out pid);GetWindowThreadProcessId(host,out hpid);
  if(!IsWindow(widget)||pid!=expectedPid||!IsWindow(host)||hpid!=hostPid)throw new Exception("Window ownership changed.");
  string widgetScript=Path.GetFullPath((string)request["widgetScript"]);
  using(var process=Process.GetProcessById(expectedPid)){
   if(process.ProcessName!="powershell"||process.SessionId!=Process.GetCurrentProcess().SessionId)throw new Exception("Unexpected widget process.");
   if(verifiedPid!=expectedPid||verifiedStarted!=process.StartTime.Ticks||verifiedScript!=widgetScript){
    using(var entry=new ManagementObject("Win32_Process.Handle='"+expectedPid+"'")){
     string command=Convert.ToString(entry["CommandLine"]);
     if(command.IndexOf("\""+widgetScript+"\"",StringComparison.OrdinalIgnoreCase)<0)throw new Exception("Widget command identity did not match.");
    }
    verifiedPid=expectedPid;verifiedStarted=process.StartTime.Ticks;verifiedScript=widgetScript;
   }
  }
  Rect wr,client,frame;var point=new Point();
  if(!GetWindowRect(widget,out wr)||!GetClientRect(host,out client)||!ClientToScreen(host,ref point))throw new Exception("Window geometry unavailable.");
  if(DwmGetWindowAttribute(host,9,out frame,16)!=0&&!GetWindowRect(host,out frame))throw new Exception("Host frame unavailable.");
  client.Left+=point.X;client.Right+=point.X;client.Top+=point.Y;client.Bottom+=point.Y;
  uint dpi=GetDpiForWindow(host);
  return new{status=Visible(widget)&&Visible(host)?"visible":"hidden",widgetVisible=Visible(widget),hostVisible=Visible(host),widget=Box(wr),hostClient=Box(client),hostFrame=Box(frame),hostDpi=dpi,hostPid=hostPid};
 }
 public static void Main(){
  try{SetThreadDpiAwarenessContext(new IntPtr(-4));}catch{}
  string line;while((line=Console.ReadLine())!=null){try{
   if(line.Length>8192)throw new Exception("Request too large.");
   Console.WriteLine(json.Serialize(Sample(json.Deserialize<Dictionary<string,object>>(line))));
  }catch(Exception error){Console.WriteLine(json.Serialize(new{status="unavailable",reason=error.Message}));}}
 }
}
