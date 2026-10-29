# Preloaded, volume-scaled PCM; native playback stays on one audio worker.
if ($null -eq (Get-Variable -Name gptNiangAudio -Scope Script -ErrorAction SilentlyContinue)) {
    $script:gptNiangAudio = $null
}

function Get-WidgetAudioEnabled {
    $setting = Get-Variable -Name soundOn -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $setting) { return $true }
    return ($setting.Value -ne $false)
}

function Get-WidgetAudioVolume {
    $setting = Get-Variable -Name soundVolume -Scope Script -ErrorAction SilentlyContinue
    $value = 0.9
    if ($null -ne $setting) {
        try { $value = [double]$setting.Value } catch { $value = 0.9 }
    }
    if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { $value = 0.9 }
    return [Math]::Min(1.0, [Math]::Max(0.0, $value))
}

if(!('GptNiangPcm' -as [type])){
    Add-Type -TypeDefinition @'
using System;
public static class GptNiangPcm {
 public static byte[] Scale(byte[] source,int offset,int length,double volume){
  var output=(byte[])source.Clone();
  for(int i=offset;i<offset+length;i+=2){
   int value=(short)(source[i]|(source[i+1]<<8));
   int scaled=(int)Math.Round(value*volume,MidpointRounding.AwayFromZero);
   short sample=(short)Math.Max(-32768,Math.Min(32767,scaled));
   output[i]=(byte)(sample&255);output[i+1]=(byte)((sample>>8)&255);
  }
  return output;
 }
}
'@
}
if(!('GptClickAudioQueue' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;
public sealed class GptWaveOutput : IDisposable {
 [StructLayout(LayoutKind.Sequential,Pack=2)] struct Format {
  public ushort Tag,Channels;public uint Rate,Bytes;public ushort Block,Bits,Extra;
 }
 [StructLayout(LayoutKind.Sequential)] struct Header {
  public IntPtr Data;public uint Length,Recorded;public UIntPtr User;
  public uint Flags,Loops;public IntPtr Next;public UIntPtr Reserved;
 }
 [DllImport("winmm.dll")] static extern uint waveOutOpen(out IntPtr device,uint id,ref Format format,IntPtr callback,IntPtr instance,uint flags);
 [DllImport("winmm.dll")] static extern uint waveOutPrepareHeader(IntPtr device,IntPtr header,uint size);
 [DllImport("winmm.dll")] static extern uint waveOutUnprepareHeader(IntPtr device,IntPtr header,uint size);
 [DllImport("winmm.dll")] static extern uint waveOutWrite(IntPtr device,IntPtr header,uint size);
 [DllImport("winmm.dll")] static extern uint waveOutReset(IntPtr device);
 [DllImport("winmm.dll")] static extern uint waveOutClose(IntPtr device);
 IntPtr device,header,idleHeader,idleData;Format format;bool prepared,idlePrepared;
 public volatile bool KeepWarm=true;
 public bool IsWarm {get{return idleHeader!=IntPtr.Zero && (Marshal.ReadInt32(idleHeader,(int)Marshal.OffsetOf(typeof(Header),"Flags"))&16)!=0;}}
 // An open handle alone does not keep the render endpoint running. Queue
 // exact-zero PCM after every clip so the next click never wakes an idle stream.
 public void Idle(){
  if(!KeepWarm||device==IntPtr.Zero||idleHeader!=IntPtr.Zero)return;
  int length=checked((int)(format.Rate/10)*format.Block);
  byte[] silence=new byte[length];idleData=Marshal.AllocHGlobal(length);
  Marshal.Copy(silence,0,idleData,length);idleHeader=Marshal.AllocHGlobal((int)headerSize);
  Marshal.StructureToPtr(new Header{Data=idleData,Length=(uint)length,Flags=12,Loops=uint.MaxValue},idleHeader,false);
  Check(waveOutPrepareHeader(device,idleHeader,headerSize));idlePrepared=true;
  Check(waveOutWrite(device,idleHeader,headerSize));
 }
 public bool IsPlaying {get{return header!=IntPtr.Zero && (Marshal.ReadInt32(header,(int)Marshal.OffsetOf(typeof(Header),"Flags"))&1)==0;}}
 static readonly uint headerSize=(uint)Marshal.SizeOf(typeof(Header));
 static void Check(uint result){if(result!=0)throw new InvalidOperationException("waveOut error "+result);}
 Format ReadFormat(IntPtr wave,out IntPtr data,out uint length){
  int total=checked(Marshal.ReadInt32(wave,4)+8),offset=12;Format found=new Format();data=IntPtr.Zero;length=0;
  if(total<12||total>10*1024*1024)throw new InvalidOperationException("Invalid PCM buffer");
  while(offset+8<=total){
   int tag=Marshal.ReadInt32(wave,offset),count=Marshal.ReadInt32(wave,offset+4);
   if(count<0||count>total-offset-8)throw new InvalidOperationException("Invalid PCM chunk");
   IntPtr body=IntPtr.Add(wave,offset+8);
   if(tag==0x20746d66&&count>=16){found.Tag=(ushort)Marshal.ReadInt16(body);found.Channels=(ushort)Marshal.ReadInt16(body,2);found.Rate=(uint)Marshal.ReadInt32(body,4);found.Bytes=(uint)Marshal.ReadInt32(body,8);found.Block=(ushort)Marshal.ReadInt16(body,12);found.Bits=(ushort)Marshal.ReadInt16(body,14);}
   if(tag==0x61746164){data=body;length=(uint)count;}
   offset=checked(offset+8+count+(count&1));
  }
  if(found.Tag!=1||found.Bits!=16||data==IntPtr.Zero||length==0)throw new InvalidOperationException("Unsupported PCM buffer");
  return found;
 }
 public void WarmUp(IntPtr wave){IntPtr data;uint length;Open(ReadFormat(wave,out data,out length));Idle();}
 void Open(Format next){
  if(device!=IntPtr.Zero&&format.Channels==next.Channels&&format.Rate==next.Rate&&format.Bits==next.Bits)return;
  Dispose();Check(waveOutOpen(out device,0xffffffff,ref next,IntPtr.Zero,IntPtr.Zero,0));format=next;
 }
 public bool Play(IntPtr wave,uint flags){
  if(wave==IntPtr.Zero){Reset();return true;}
  IntPtr data;uint length;Format next=ReadFormat(wave,out data,out length);Open(next);Reset();
  header=Marshal.AllocHGlobal((int)headerSize);
  Marshal.StructureToPtr(new Header{Data=data,Length=length},header,false);
  Check(waveOutPrepareHeader(device,header,headerSize));prepared=true;
  Check(waveOutWrite(device,header,headerSize));Idle();return true;
 }
 void Reset(){
  if(device==IntPtr.Zero)return;
  Check(waveOutReset(device));
  // Reset returns both the audible header and the looping silence to us.
  // Never release a header or PCM allocation while the driver owns it.
  if(idleHeader!=IntPtr.Zero){if(idlePrepared)Check(waveOutUnprepareHeader(device,idleHeader,headerSize));Marshal.FreeHGlobal(idleHeader);idleHeader=IntPtr.Zero;idlePrepared=false;}
  if(idleData!=IntPtr.Zero){Marshal.FreeHGlobal(idleData);idleData=IntPtr.Zero;}
  if(header!=IntPtr.Zero){if(prepared)Check(waveOutUnprepareHeader(device,header,headerSize));Marshal.FreeHGlobal(header);header=IntPtr.Zero;prepared=false;}
 }
 public void Dispose(){Reset();if(device!=IntPtr.Zero){Check(waveOutClose(device));device=IntPtr.Zero;}}
}

public sealed class GptClickAudioQueue : IDisposable {
 [DllImport("winmm.dll", EntryPoint="PlaySoundW")]
 [return: MarshalAs(UnmanagedType.Bool)]
 private static extern bool PlaySound(IntPtr sound, IntPtr module, uint flags);
 // One pending command: a blocked driver must not accumulate stale clicks.
 private sealed class Command {public byte[] Wave;public long Id;}
 private readonly BlockingCollection<Command> queue=new BlockingCollection<Command>(1);
 private long requested,processed;
 private readonly Thread worker;
 private readonly Func<IntPtr,uint,bool> play;
 private GptWaveOutput native;
 private static readonly object gate=new object();
 private static GptClickAudioQueue owner;
 private GCHandle current;
 private bool closed;
 private volatile string error;
 public string Error { get { return error; } }
 public bool IsPlaying {get{if(Interlocked.Read(ref requested)>Interlocked.Read(ref processed))return true;if(native==null)return false;if(!Monitor.TryEnter(gate))return true;try{return native.IsPlaying;}finally{Monitor.Exit(gate);}}}
 public bool IsRunning { get { return worker.IsAlive; } }
 public bool KeepWarm {get{return native!=null&&native.KeepWarm;}set{if(native!=null&&native.KeepWarm!=value){native.KeepWarm=value;Stop();}}}
 public bool IsWarm {get{if(native==null||!Monitor.TryEnter(gate))return false;try{return native.IsWarm;}finally{Monitor.Exit(gate);}}}
 public GptClickAudioQueue() : this(new GptWaveOutput()) {}
 private GptClickAudioQueue(GptWaveOutput output) : this(output.Play) {native=output;}
 public void WarmUp(byte[] wave){if(native==null||wave==null)return;lock(gate){GCHandle pin=GCHandle.Alloc(wave,GCHandleType.Pinned);try{native.WarmUp(pin.AddrOfPinnedObject());}catch(Exception ex){error=ex.Message;}finally{pin.Free();}}}
 public GptClickAudioQueue(Func<IntPtr,uint,bool> playback){
  play=playback;
  worker=new Thread(Loop);worker.IsBackground=true;worker.Name="gpt-click-audio";worker.Start();
 }
 private static void Reset(){
  if(owner==null)return;
  // Keep asynchronous PCM memory pinned until native playback really stops.
  if(!owner.play(IntPtr.Zero,0))throw new InvalidOperationException("Audio stop failed");
  if(owner.current.IsAllocated)owner.current.Free();
  owner=null;
 }
 private void Run(byte[] wave){
  lock(gate){
   for(int attempt=0;attempt<2;attempt++){
    try{
     Reset();
     if(wave==null){if(native!=null){native.Play(IntPtr.Zero,0);native.Idle();}error=null;return;}
     current=GCHandle.Alloc(wave,GCHandleType.Pinned);owner=this;
     // SoundPlayer discards this BOOL; inspect it and reset/retry once instead.
     if(play(current.AddrOfPinnedObject(),0x0007)){error=null;return;}
     error="Audio playback failed";
    }catch(Exception ex){error=ex.Message;}
   }
  }
 }
 private void Loop(){
  try{foreach(Command command in queue.GetConsumingEnumerable()){
   if(queue.IsAddingCompleted)break;
   Run(command.Wave);Interlocked.Exchange(ref processed,command.Id);
  }}finally{
   lock(gate){if(owner==this){try{Reset();}catch(Exception ex){error=ex.Message;}}}
   if(native!=null){try{native.Dispose();}catch(Exception ex){error=ex.Message;}}
   lock(queue){closed=true;queue.Dispose();}
  }
 }
 public void Play(byte[] wave){
  lock(queue){
   if(closed)return;
   Command command=new Command{Wave=wave,Id=Interlocked.Increment(ref requested)};
   if(!queue.TryAdd(command)){Command stale;queue.TryTake(out stale);queue.TryAdd(command);}
  }
 }
 public void Stop(){Play(null);}
 public void Dispose(){lock(queue){if(!closed){closed=true;queue.CompleteAdding();}}}
 public void Wait(int milliseconds){worker.Join(milliseconds);}
}
'@
}
function Read-WidgetPcmWave([string]$Path) {
    $file=[IO.File]::OpenRead($Path)
    try{
        if($file.Length-gt 10MB){throw '音效文件超过10MiB。'}
        $bytes=[byte[]]::new([int]$file.Length);$read=0
        while($read-lt $bytes.Length){$n=$file.Read($bytes,$read,$bytes.Length-$read);if(!$n){throw 'WAV文件不完整。'};$read+=$n}
        if($file.Length-ne $bytes.Length){throw '音效读取期间发生变化，请重试。'}
    }finally{$file.Dispose()}
    if($bytes.Length-lt 12 -or [Text.Encoding]::ASCII.GetString($bytes,0,4)-ne 'RIFF' -or [Text.Encoding]::ASCII.GetString($bytes,8,4)-ne 'WAVE' -or [long][BitConverter]::ToUInt32($bytes,4)+8-ne $bytes.Length){throw 'WAV文件损坏或不完整。'}
    $formatSeen=$false;$dataSeen=$false;$offset=12;$dataOffset=0;$dataLength=0;$rate=0;$align=0
    while($offset-lt $bytes.Length){
        if($offset+8-gt $bytes.Length){throw 'WAV文件不完整。'}
        $tag=[Text.Encoding]::ASCII.GetString($bytes,$offset,4);$size=[long][BitConverter]::ToUInt32($bytes,$offset+4);$body=$offset+8
        if($size+($size%2)-gt $bytes.Length-$body){throw 'WAV数据块不完整。'}
        if($tag-eq 'fmt '){
            if($formatSeen -or $size-lt 16){throw 'WAV格式块无效。'};$formatSeen=$true
            $channels=[BitConverter]::ToUInt16($bytes,$body+2);$rate=[BitConverter]::ToUInt32($bytes,$body+4);$align=[BitConverter]::ToUInt16($bytes,$body+12)
            if([BitConverter]::ToUInt16($bytes,$body)-ne 1 -or [BitConverter]::ToUInt16($bytes,$body+14)-ne 16 -or $channels-notin @(1,2) -or $rate-lt 8000 -or $rate-gt 192000 -or $align-ne $channels*2 -or [BitConverter]::ToUInt32($bytes,$body+8)-ne [long]$rate*$align){throw '缓存不是有效的16位PCM WAV。'}
        }elseif($tag-eq 'data'){
            if($dataSeen){throw 'WAV文件有重复音频块。'};$dataSeen=$true;$dataOffset=$body;$dataLength=[int]$size
        }
        $offset=$body+$size+($size%2)
    }
    if(!$formatSeen -or !$dataSeen -or $dataLength-le 0 -or $dataLength%$align-ne 0){throw 'WAV音频数据无效。'}
    if([long]$dataLength-gt [long]$rate*$align*5){throw '音效超过5秒，请选择不超过5秒的文件。'}
    return @{Bytes=$bytes;Offset=$dataOffset;Length=$dataLength;Duration=([double]$dataLength/$align/$rate)}
}
function Get-WidgetWaveSeconds([string]$Path){return (Read-WidgetPcmWave $Path).Duration}
function New-WidgetAudioClip([string]$Path,[double]$Volume) {
    $wave=Read-WidgetPcmWave $Path
    return ,([GptNiangPcm]::Scale($wave.Bytes,$wave.Offset,$wave.Length,$Volume))
}

function Read-WidgetAudioPreferences([string]$DataDir) {
    $prefs=@{version=1;mode='builtin';press=$null;release=$null}
    if(!$DataDir){return $prefs}
    $file=Join-Path $DataDir 'audio-preferences.json'
    if(![IO.File]::Exists($file)){return $prefs}
    try{
        if((Get-Item -LiteralPath $file).Length-gt 16KB){throw 'Invalid audio preferences'}
        $saved=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json
        if($saved.version-ne 1 -or $saved.mode-notin @('builtin','custom')){throw 'Invalid audio preferences'}
        $prefs.mode=[string]$saved.mode
        foreach($slot in @('press','release')){
            $entry=$saved.$slot
            if($null-eq $entry){continue}
            if($entry.file-isnot [string] -or $entry.file-cnotmatch '^[a-f0-9]{32}\.wav$' -or $entry.name-isnot [string] -or $entry.name.Length-gt 255){throw 'Invalid audio entry'}
            $prefs[$slot]=@{file=$entry.file;name=$entry.name}
        }
    }catch{$prefs=@{version=1;mode='custom';press=$null;release=$null;loadError='音效设置无法读取，请重新选择音效。'}}
    return $prefs
}
function Copy-WidgetAudioPreferences($Preferences) {
    $copy=@{version=1;mode=$Preferences.mode;press=$null;release=$null}
    foreach($slot in @('press','release')){if($Preferences[$slot]){$copy[$slot]=@{file=$Preferences[$slot].file;name=$Preferences[$slot].name}}}
    return $copy
}
function Write-WidgetAudioPreferences([string]$DataDir,$Preferences) {
    if(!$DataDir){throw '个人音效目录不可用。'}
    $file=Join-Path $DataDir 'audio-preferences.json';$temporary=$file+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,($Preferences|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        if([IO.File]::Exists($file)){[IO.File]::Replace($temporary,$file,($file+'.bak'),$true)}else{[IO.File]::Move($temporary,$file)}
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
}
function Get-WidgetCustomAudioPath($Audio,[string]$Slot) {
    $entry=$Audio.Preferences[$Slot]
    if(!$entry -or !$Audio.DataDir){return $null}
    return Join-Path (Join-Path $Audio.DataDir 'sounds') $entry.file
}
function Close-WidgetAudioState($Audio) {
    if(!$Audio){return}
    $Audio.Timer.Stop()
    if($Audio.Queue){try{$Audio.Queue.Dispose();$Audio.Queue.Wait(500)}catch{}}
    $Audio.Press=$null;$Audio.Release=$null
}
function New-WidgetAudioState([string]$AppDir,[string]$DataDir,$Preferences) {
    $timer=[Windows.Threading.DispatcherTimer]::new()
    $audio=@{AppDir=$AppDir;DataDir=$DataDir;Preferences=$Preferences;Errors=@{}
        Press=$null;Release=$null;PressPath=$null;ReleasePath=$null
        Volume=(Get-WidgetAudioVolume);Timer=$timer;Clock=[Diagnostics.Stopwatch]::new()
        Queue=[GptClickAudioQueue]::new()
        Duration=0.0;Pressing=$false;PressEnded=$true;PendingRelease=$false;ReleasePlayed=$true}
    try{
        foreach($slot in @('press','release')){
            $source=if($Preferences.mode-eq 'builtin'){Join-Path $AppDir ('assets/'+$slot+'.wav')}else{Get-WidgetCustomAudioPath $audio $slot}
            $audio[$slot+'Path']=$source
            if(!$source){continue}
            try{
                $duration=Get-WidgetWaveSeconds $source
                $loaded=New-WidgetAudioClip $source $audio.Volume
                $audio[$slot]=$loaded
                if($slot-eq 'press'){$audio.Duration=$duration}
            }catch{
                if($Preferences.mode-eq 'builtin'){throw}
                $audio.Errors[$slot]='文件不可用，请重新选择。'
            }
        }
        $audio.Queue.KeepWarm=((Get-WidgetAudioEnabled) -and $audio.Volume-gt 0 -and ($audio.Press -or $audio.Release))
        if($audio.Press){$audio.Queue.WarmUp($audio.Press)}elseif($audio.Release){$audio.Queue.WarmUp($audio.Release)}
        $audio.Queue.Stop() # Start the worker/JIT before the first user click.
        $timer.Add_Tick({
            param($sender,$event)
            $audio=$script:gptNiangAudio
            if(!$audio -or ![object]::ReferenceEquals($sender,$audio.Timer)){return}
            $audio.Timer.Stop()
            if(!$audio.PendingRelease -or $audio.Pressing){return}
            $remaining=$audio.Duration+0.005-$audio.Clock.Elapsed.TotalSeconds
            if($remaining-gt 0.002){$audio.Timer.Interval=[TimeSpan]::FromSeconds($remaining);$audio.Timer.Start();return}
            $audio.PressEnded=$true;Invoke-WidgetReleaseNow
        })
        return $audio
    }catch{Close-WidgetAudioState $audio;throw}
}
function Set-WidgetAudioVolume {
    param([double]$Volume=-1)
    if($Volume-ge 0 -and ![double]::IsNaN($Volume) -and ![double]::IsInfinity($Volume)){$script:soundVolume=[Math]::Min(1.0,[Math]::Max(0.0,$Volume))}
    $value=Get-WidgetAudioVolume;$audio=$script:gptNiangAudio
    if(!$audio){return}
    $audio.Queue.KeepWarm=((Get-WidgetAudioEnabled) -and $value-gt 0 -and ($audio.Press -or $audio.Release))
    if([Math]::Abs($audio.Volume-$value)-lt 0.000001){return}
    $clips=@{}
    try{
        foreach($slot in @('press','release')){if($audio[$slot]){$clips[$slot]=New-WidgetAudioClip $audio[$slot+'Path'] $value}}
        foreach($slot in @('press','release')){
            if(!$clips[$slot]){continue}
            $audio[$slot]=$clips[$slot]
        }
        $audio.Volume=$value
        $audio.Queue.Stop()
    }catch{
        $script:soundVolume=$audio.Volume
    }
}
function Invoke-WidgetReleaseNow {
    $audio=$script:gptNiangAudio
    if(!$audio -or !$audio.PendingRelease -or $audio.ReleasePlayed){return}
    # Wait for driver completion instead of cutting off the press clip using a guessed delay.
    if($audio.Queue -and $audio.Queue.IsPlaying -and $audio.Clock.Elapsed.TotalSeconds-lt $audio.Duration+0.5){
        $audio.Timer.Interval=[TimeSpan]::FromMilliseconds(5);$audio.Timer.Start();return
    }
    $audio.Timer.Stop();$audio.PendingRelease=$false;$audio.ReleasePlayed=$true
    if(!(Get-WidgetAudioEnabled) -or (Get-WidgetAudioVolume)-le 0 -or !$audio.Release){return}
    Set-WidgetAudioVolume
    # Native stop/play and recovery stay on the audio worker, away from dragging.
    if($audio.Queue){try{$audio.Queue.Play($audio.Release)}catch{}}
}
function Stop-WidgetAudio {
    $audio=$script:gptNiangAudio
    if(!$audio){return}
    $audio.Timer.Stop();$audio.PendingRelease=$false;$audio.ReleasePlayed=$true;$audio.Pressing=$false;$audio.PressEnded=$true;$audio.Clock.Reset()
    if($audio.Queue){try{$audio.Queue.KeepWarm=((Get-WidgetAudioEnabled) -and (Get-WidgetAudioVolume)-gt 0 -and ($audio.Press -or $audio.Release));$audio.Queue.Stop()}catch{}}
}
function Initialize-WidgetAudio {
    param([Parameter(Mandatory=$true)][string]$AppDir,[string]$DataDir)
    Close-WidgetAudio
    try{
        Add-Type -AssemblyName PresentationCore,WindowsBase,System
        $prefs=Read-WidgetAudioPreferences $DataDir
        $script:gptNiangAudio=New-WidgetAudioState $AppDir $DataDir $prefs
    }catch{$script:gptNiangAudio=$null}
}
function Close-WidgetAudio {
    if(!$script:gptNiangAudio){return}
    Stop-WidgetAudio;Close-WidgetAudioState $script:gptNiangAudio;$script:gptNiangAudio=$null
}
function Play-WidgetPressSound {
    $audio=$script:gptNiangAudio
    if(!$audio){return}
    $audio.Timer.Stop();$audio.PendingRelease=$false;$audio.PressEnded=$true;$audio.Clock.Reset()
    if(!(Get-WidgetAudioEnabled) -or (Get-WidgetAudioVolume)-le 0 -or (!$audio.Press -and !$audio.Release)){$audio.Pressing=$false;return}
    $audio.Pressing=$true;$audio.PressEnded=(!$audio.Press);$audio.ReleasePlayed=$false;$audio.Clock.Restart()
    Set-WidgetAudioVolume
    # Keep the original stop-then-play sequence without waiting on the UI thread.
    if($audio.Press -and $audio.Queue){try{$audio.Queue.Play($audio.Press)}catch{$audio.PressEnded=$true}}
}
function Play-WidgetReleaseSound {
    $audio=$script:gptNiangAudio
    if(!$audio -or !$audio.Pressing){return}
    $audio.Pressing=$false
    if(!(Get-WidgetAudioEnabled) -or (Get-WidgetAudioVolume)-le 0){Stop-WidgetAudio;return}
    if(!$audio.Release){$audio.ReleasePlayed=$true;return}
    $audio.PendingRelease=$true
    if(!$audio.Press -or $audio.PressEnded){Invoke-WidgetReleaseNow;return}
    $remaining=$audio.Duration+0.005-$audio.Clock.Elapsed.TotalSeconds
    if($remaining-le 0.002){$audio.PressEnded=$true;Invoke-WidgetReleaseNow;return}
    $audio.Timer.Interval=[TimeSpan]::FromSeconds($remaining);$audio.Timer.Start()
}
function Remove-WidgetUnusedAudioFiles($Audio,$Preferences) {
    # Replaced or cleared custom clips otherwise stay in the user's data folder
    # forever. Only files inside our own sounds directory are considered.
    if(!$Audio -or !$Audio.DataDir -or !$Preferences){return}
    $keep=@{}
    foreach($slot in @('press','release')){$entry=$Preferences[$slot];if($entry -and $entry.file){$keep[[string]$entry.file]=$true}}
    $directory=Join-Path $Audio.DataDir 'sounds'
    try{
        foreach($file in [IO.Directory]::GetFiles($directory,'*.wav')){
            if(!$keep.ContainsKey([IO.Path]::GetFileName($file))){try{[IO.File]::Delete($file)}catch{}}
        }
    }catch{}
}
function Set-WidgetAudioPreferences($Preferences,[string]$RequiredSlot) {
    $audio=$script:gptNiangAudio
    if(!$audio){throw '声音播放器尚未就绪。'}
    $candidate=$null
    try{
        $candidate=New-WidgetAudioState $audio.AppDir $audio.DataDir $Preferences
        if($RequiredSlot -and !$candidate[$RequiredSlot]){throw '音效无法加载，原设置已保留。'}
        Write-WidgetAudioPreferences $audio.DataDir $Preferences
    }catch{Close-WidgetAudioState $candidate;throw}
    Close-WidgetAudio;$script:gptNiangAudio=$candidate
}
function Import-WidgetAudio([ValidateSet('press','release')][string]$Slot,[string]$Path) {
    if(!$Path){return $false}
    $audio=$script:gptNiangAudio
    if(!$audio -or !$audio.DataDir){throw '个人音效目录不可用。'}
    $directory=Join-Path $audio.DataDir 'sounds';$null=[IO.Directory]::CreateDirectory($directory)
    $filename=[Guid]::NewGuid().ToString('N')+'.wav';$target=Join-Path $directory $filename
    $process=$null;$committed=$false
    try{
        $node=if($script:config.nodePath){$script:config.nodePath}else{(Get-Command node -ErrorAction Stop).Source}
        $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$node
        $info.Arguments='"'+(Join-Path $audio.AppDir 'runtime/audio-import.mjs')+'" "'+[IO.Path]::GetFullPath($Path)+'" "'+$target+'"'
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
        $process=[Diagnostics.Process]::new();$process.StartInfo=$info
        if(!$process.Start()){throw '音效转换无法启动。'}
        if(!$process.WaitForExit(5000)){$process.Kill();$null=$process.WaitForExit(1000);throw '音效读取超时，请换一个文件。'}
        $result=$process.StandardOutput.ReadToEnd()|ConvertFrom-Json
        if(!$result.ok -or $process.ExitCode-ne 0){
            $message=switch($result.error){
                'too_long'{'音效超过5秒，请选择不超过5秒的文件。'}
                'too_large'{'音效文件超过10MiB，请选择较小的文件。'}
                'unsupported'{'不支持这种WAV编码，请选择其他音效文件。'}
                'io'{'无法读取或保存音效，请检查文件和个人目录。'}
                default{'WAV文件损坏或不完整，无法导入。'}
            }
            throw $message
        }
        $prefs=Copy-WidgetAudioPreferences $audio.Preferences
        $prefs.mode='custom';$prefs[$Slot]=@{file=$filename;name=[IO.Path]::GetFileName($Path)}
        Set-WidgetAudioPreferences $prefs $Slot;Remove-WidgetUnusedAudioFiles $script:gptNiangAudio $prefs;$committed=$true;return $true
    }finally{
        if($process){$process.Dispose()}
        if(!$committed -and [IO.File]::Exists($target)){[IO.File]::Delete($target)}
    }
}
function Set-WidgetAudioMode([ValidateSet('builtin','custom')][string]$Mode) {
    $prefs=Copy-WidgetAudioPreferences $script:gptNiangAudio.Preferences;$prefs.mode=$Mode
    Set-WidgetAudioPreferences $prefs;Remove-WidgetUnusedAudioFiles $script:gptNiangAudio $prefs
}
function Clear-WidgetAudioSlot([ValidateSet('press','release')][string]$Slot) {
    $prefs=Copy-WidgetAudioPreferences $script:gptNiangAudio.Preferences;$prefs.mode='custom';$prefs[$Slot]=$null
    Set-WidgetAudioPreferences $prefs;Remove-WidgetUnusedAudioFiles $script:gptNiangAudio $prefs
}
function Invoke-WidgetAudioPreview([ValidateSet('press','release')][string]$Slot) {
    $audio=$script:gptNiangAudio
    if(!$audio -or !(Get-WidgetAudioEnabled) -or (Get-WidgetAudioVolume)-le 0){return}
    $source=Get-WidgetCustomAudioPath $audio $Slot
    if(!$source){return}
    Stop-WidgetAudio
    try{
        $clip=New-WidgetAudioClip $source (Get-WidgetAudioVolume)
        $audio.Queue.Play($clip)
    }catch{throw ($audio.Preferences[$Slot].name+[Environment]::NewLine+'音效文件不可用，请重新选择。')}
}
function Select-WidgetAudioFile {
    $dialog=[Microsoft.Win32.OpenFileDialog]::new()
    $dialog.Title='选择WAV音效，最长5秒';$dialog.Filter='WAV音效 (*.wav)|*.wav';$dialog.Multiselect=$false;$dialog.CheckFileExists=$true
    if($dialog.ShowDialog($script:window)-eq $true){return $dialog.FileName}
    return $null
}
function Show-WidgetAudioError([string]$Message) {
    [Windows.MessageBox]::Show($script:window,$Message,'GPT 娘 · 音效',[Windows.MessageBoxButton]::OK,[Windows.MessageBoxImage]::Warning)|Out-Null
}
function Invoke-WidgetAudioAction([string]$Action,[string]$Slot) {
    $script:audioDialogOpen=$true
    try{
        switch($Action){
            'import'{$source=Select-WidgetAudioFile;if($source){try{$null=Import-WidgetAudio $Slot $source}catch{throw ([IO.Path]::GetFileName($source)+[Environment]::NewLine+$_.Exception.Message)}}}
            'clear'{Clear-WidgetAudioSlot $Slot}
            'builtin'{Set-WidgetAudioMode 'builtin'}
            'custom'{Set-WidgetAudioMode 'custom'}
            'preview'{Invoke-WidgetAudioPreview $Slot}
        }
    }catch{Show-WidgetAudioError $_.Exception.Message}
    finally{$script:audioDialogOpen=$false;Update-WidgetSettingsMenu}
}
function Get-WidgetAudioStatus {
    $audio=$script:gptNiangAudio
    $status=@{enabled=(Get-WidgetAudioEnabled);volume=(Get-WidgetAudioVolume);backend=$null;ready=[bool]$audio;mode='builtin';press=$null;release=$null}
    if(!$audio){return $status}
    $status.warm=$audio.Queue.IsWarm
    $status.mode=$audio.Preferences.mode;$status.error=$audio.Preferences.loadError
    if($audio.Queue.Error){$status.error=$audio.Queue.Error}
    if($audio.Press -or $audio.Release){$status.backend='winmm.waveOut'}
    foreach($slot in @('press','release')){
        $entry=$audio.Preferences[$slot];$source=Get-WidgetCustomAudioPath $audio $slot
        $status[$slot]=@{name=if($entry){$entry.name}else{'无声'};configured=[bool]$entry;available=([bool]$source -and [IO.File]::Exists($source) -and !$audio.Errors[$slot]);active=[bool]$audio[$slot];error=$audio.Errors[$slot]}
    }
    return $status
}
