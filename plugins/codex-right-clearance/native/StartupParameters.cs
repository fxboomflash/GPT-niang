using System;
using System.Text;
using System.Runtime.InteropServices;

// Used only while Windows has the application's initial thread suspended.
// No executable code, imports, installed files or signatures are changed.
public static class StartupParameters {
 [StructLayout(LayoutKind.Sequential)] struct BasicInfo { public IntPtr reserved,peb,reserved1,reserved2,pid,reserved3; }
 [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr process,int kind,out BasicInfo info,int length,out int returned);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process,IntPtr address,byte[] buffer,int length,out IntPtr read);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process,IntPtr address,byte[] buffer,int length,out IntPtr written);
 [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr process,IntPtr address,UIntPtr size,uint type,uint protection);
 static byte[] Read(IntPtr process,IntPtr at,int count){byte[] bytes=new byte[count];IntPtr done;if(!ReadProcessMemory(process,at,bytes,count,out done)||done.ToInt64()!=count)throw new InvalidOperationException("Startup parameter read failed");return bytes;}
 static void Write(IntPtr process,IntPtr at,byte[] bytes){IntPtr done;if(!WriteProcessMemory(process,at,bytes,bytes.Length,out done)||done.ToInt64()!=bytes.Length)throw new InvalidOperationException("Startup parameter write failed");}
 public static string ReadCommand(IntPtr process) {BasicInfo info;int returned;if(IntPtr.Size!=8||NtQueryInformationProcess(process,0,out info,Marshal.SizeOf(typeof(BasicInfo)),out returned)!=0)throw new InvalidOperationException("Unsupported startup process");IntPtr block=new IntPtr(BitConverter.ToInt64(Read(process,IntPtr.Add(info.peb,0x20),8),0));return ReadCommandAt(process,block);}
 static string ReadCommandAt(IntPtr process,IntPtr block){byte[] descriptor=Read(process,IntPtr.Add(block,0x70),16);int length=BitConverter.ToUInt16(descriptor,0);if(length<2||length>30000||length%2!=0)throw new InvalidOperationException("Unexpected startup command length");return Encoding.Unicode.GetString(Read(process,new IntPtr(BitConverter.ToInt64(descriptor,8)),length));}
 public static void Append(IntPtr process,string switches){
  BasicInfo info;int returned;
  if(IntPtr.Size!=8||NtQueryInformationProcess(process,0,out info,Marshal.SizeOf(typeof(BasicInfo)),out returned)!=0)throw new InvalidOperationException("Unsupported startup process");
  IntPtr pointerSlot=IntPtr.Add(info.peb,0x20),originalBlock=new IntPtr(BitConverter.ToInt64(Read(process,pointerSlot,8),0));
  byte[] header=Read(process,originalBlock,16);int maximum=BitConverter.ToInt32(header,0),length=BitConverter.ToInt32(header,4),flags=BitConverter.ToInt32(header,8);
  if(maximum<0x100||maximum>1024*1024||length<0x100||length>maximum||(flags&1)!=1)throw new InvalidOperationException("Unsupported startup parameter layout");
  string command=ReadCommandAt(process,originalBlock),next=command+switches;
  byte[] text=Encoding.Unicode.GetBytes(next+"\0");if(text.Length>32766)throw new InvalidOperationException("Startup arguments too long");
  byte[] copy=new byte[maximum+text.Length];Array.Copy(Read(process,originalBlock,maximum),copy,maximum);
  IntPtr allocation=VirtualAllocEx(process,IntPtr.Zero,(UIntPtr)copy.Length,0x3000,4);if(allocation==IntPtr.Zero)throw new InvalidOperationException("Startup parameter allocation failed");
  // All strings must remain within the complete block when the loader relocates it.
  for(int at=0;at+8<=maximum;at+=8){long value=BitConverter.ToInt64(copy,at);if(value>=originalBlock.ToInt64()&&value<originalBlock.ToInt64()+maximum)Array.Copy(BitConverter.GetBytes(allocation.ToInt64()+value-originalBlock.ToInt64()),0,copy,at,8);}
  Array.Copy(BitConverter.GetBytes(copy.Length),0,copy,0,4);Array.Copy(BitConverter.GetBytes(copy.Length),0,copy,4,4);
  Array.Copy(text,0,copy,maximum,text.Length);Array.Copy(BitConverter.GetBytes((ushort)(text.Length-2)),0,copy,0x70,2);Array.Copy(BitConverter.GetBytes((ushort)text.Length),0,copy,0x72,2);Array.Copy(BitConverter.GetBytes(allocation.ToInt64()+maximum),0,copy,0x78,8);
  Write(process,allocation,copy);
  try{Write(process,pointerSlot,BitConverter.GetBytes(allocation.ToInt64()));}catch{Write(process,pointerSlot,BitConverter.GetBytes(originalBlock.ToInt64()));throw;}
 }
}
