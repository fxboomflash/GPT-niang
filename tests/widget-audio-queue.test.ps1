$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'patches\widget-audio\runtime\audio.ps1')
Add-Type -TypeDefinition @'
using System;using System.Threading;
public sealed class PendingAudioProbe {
 public ManualResetEvent Entered=new ManualResetEvent(false),Continue=new ManualResetEvent(false);
 public bool Play(IntPtr wave,uint flags){if(wave!=IntPtr.Zero){Entered.Set();Continue.WaitOne();}return true;}
 public Func<IntPtr,uint,bool> Callback{get{return Play;}}
}
'@
$probe=[PendingAudioProbe]::new();$queue=[GptClickAudioQueue]::new($probe.Callback)
try{
 $queue.Play([byte[]]@(1))
 if(-not $probe.Entered.WaitOne(2000)){throw 'Worker did not start'}
 if(-not $queue.IsPlaying){throw 'Pending first press was reported as finished'}
 foreach($i in 1..120){$queue.Play([byte[]]@(2));if(-not $queue.IsPlaying){throw 'Pending state was lost'}}
 $null=$probe.Continue.Set();$limit=[DateTime]::UtcNow.AddSeconds(2)
 do{Start-Sleep -Milliseconds 5}while($queue.IsPlaying-and [DateTime]::UtcNow-lt $limit)
 if($queue.IsPlaying-or $queue.Error){throw 'Pending requests did not settle'}
 Write-Output 'PASS: first-press submission stays busy and bounded rapid requests settle'
}finally{$null=$probe.Continue.Set();$queue.Dispose();$queue.Wait(2000)}
