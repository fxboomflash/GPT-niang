param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. (Join-Path $appDir 'runtime\host-ready.ps1')
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
$state=New-WidgetReadinessState
$script:probeReady=$false;$script:probes=0
$probe={param($h)$script:probes++;return $script:probeReady}
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 0 $probe) $false 'Loading screen stays hidden'
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 500 $probe) $false 'Probe is throttled'
Assert-Equal $script:probes 1 'No rapid accessibility polling'
$script:probeReady=$true
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 1000 $probe) $false 'First interface sample stays hidden'
$script:probeReady=$false
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 2000 $probe) $false 'Loading recurrence clears the candidate'
$script:probeReady=$true
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 3000 $probe) $false 'New candidate needs confirmation'
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 4000 $probe) $true 'Loaded interface becomes visible'
$script:probeReady=$false
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]1) 5000 $probe) $true 'Later content refreshes do not hide the widget'
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]2) 5000 $probe) $false 'New window waits for its own interface'
Assert-Equal (Test-WidgetHostReady $state ([IntPtr]::Zero) 6000 $probe) $false 'Missing host is not ready'
# Exercise real accessibility controls in our own isolated WPF window.
$window=New-Object Windows.Window;$window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Width=300;$window.Height=200
$panel=New-Object Windows.Controls.StackPanel;$window.Content=$panel
$loading=New-Object Windows.Controls.ProgressBar;$loading.IsIndeterminate=$true;$loading.Height=20;$panel.Children.Add($loading)|Out-Null
try{
  $window.Show();$window.UpdateLayout()
  $handle=([Windows.Interop.WindowInteropHelper]::new($window)).Handle
  function Get-ProbedInterface([bool]$Expected){
    $deadline=[DateTime]::UtcNow.AddSeconds(3)
    do{
      $result=[GptWidgetHostReadiness]::Poll($handle)
      $frame=New-Object Windows.Threading.DispatcherFrame
      $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(30)
      $timer.Add_Tick({param($sender,$event)$sender.Stop();$frame.Continue=$false})
      $timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
      if($result-eq $Expected){return $result}
    }while([DateTime]::UtcNow-lt $deadline)
    return $result
  }
  Assert-Equal (Get-ProbedInterface $false) $false 'Progress-only window is not loaded'
  $input=New-Object Windows.Controls.TextBox;$input.Height=40;$panel.Children.Add($input)|Out-Null;$window.UpdateLayout()
  Assert-Equal (Get-ProbedInterface $true) $true 'Visible input confirms usable UI'
  $panel.Children.Remove($input)
  $button=New-Object Windows.Controls.Button;$button.Content='New thread';$button.IsEnabled=$false;$panel.Children.Add($button)|Out-Null;$window.UpdateLayout()
  Assert-Equal (Get-ProbedInterface $false) $false 'Disabled navigation is not usable'
  $button.IsEnabled=$true;$window.UpdateLayout()
  Assert-Equal (Get-ProbedInterface $true) $true 'Enabled navigation confirms usable UI'
  Write-Output 'PASS: startup waits for usable UI, resets for new hosts, and latches after loading'
}finally{$window.Close()}
