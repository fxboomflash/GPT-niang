param([string]$HomeDirectory,[string]$NodePath,[switch]$ValidateOnly,[switch]$Launch)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition-eq 'Desktop'){$env:PSModulePath=@((Join-Path $PSHOME 'Modules'),(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'))-join ';'}
if(-not $HomeDirectory){$HomeDirectory=$env:CODEX_HOME}
if(-not $HomeDirectory){$HomeDirectory=Join-Path $env:USERPROFILE '.codex'}
$HomeDirectory=(Resolve-Path -LiteralPath $HomeDirectory).ProviderPath
if(-not $NodePath){
 $candidates=@($env:CODEX_CLEARANCE_NODE,(Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'))
 $nodeCommand=Get-Command node -ErrorAction SilentlyContinue
 if($nodeCommand){$candidates+=$nodeCommand.Source}
 foreach($candidate in $candidates){if($candidate-and (Test-Path -LiteralPath $candidate -PathType Leaf)){$NodePath=$candidate;break}}
}
if(-not $NodePath){throw 'Node.js 22 or newer is required.'}
if($Launch){
 $command='"'+(Join-Path $PSHOME 'powershell.exe')+'" -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "'+$PSCommandPath+'" -HomeDirectory "'+$HomeDirectory+'" -NodePath "'+$NodePath+'"'
 $startup=([wmiclass]'Win32_ProcessStartup').CreateInstance();$startup.ShowWindow=0
 $launched=([wmiclass]'Win32_Process').Create($command,$PSScriptRoot,$startup)
 if($launched.ReturnValue-ne 0){throw 'Settings window could not start.'}
 @{status='settings-opened';pid=$launched.ProcessId;clientClosed=$false}|ConvertTo-Json -Compress
 exit 0
}
$data=Join-Path $HomeDirectory 'plugin-data\codex-right-clearance-v3'
$settingsFile=Join-Path $data 'settings.json'
$statusFile=Join-Path $data 'status.json'
$service=Join-Path $PSScriptRoot 'service.cjs'
$value=@{}
if(Test-Path -LiteralPath $settingsFile){$value=Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='GPT 娘 · 输入框避让设置'
$form.ClientSize=New-Object Drawing.Size(510,360)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.AutoScaleMode='Dpi'
function LabelAt($text,$x,$y,$width,$height){$label=New-Object Windows.Forms.Label;$label.Text=$text;$label.SetBounds($x,$y,$width,$height);$form.Controls.Add($label);return $label}
$null=LabelAt '拖动滑块后自动保存，当前窗口实时生效。' 22 18 465 28
$null=LabelAt '居中的输入框保持原样，只调整底部输入框右侧。' 22 48 465 28
$mode=New-Object Windows.Forms.ComboBox
$mode.DropDownStyle='DropDownList';$mode.SetBounds(22,88,465,30)
$null=$mode.Items.Add('自动：跟随桌宠大小和位置');$null=$mode.Items.Add('手动：固定收缩距离')
$mode.SelectedIndex=0;if($value.mode-eq 'manual'){$mode.SelectedIndex=1}
$form.Controls.Add($mode)
$gapLabel=LabelAt '自动模式的额外间距' 22 135 465 26
$gap=New-Object Windows.Forms.TrackBar;$gap.SetBounds(22,163,465,42);$gap.Minimum=0;$gap.Maximum=80;$gap.TickFrequency=10
$gap.Value=10;if($null-ne $value.gapCssPx){$gap.Value=[Math]::Max(0,[Math]::Min(80,[int]$value.gapCssPx))};$form.Controls.Add($gap)
$manualLabel=LabelAt '手动模式的收缩距离' 22 208 465 26
$manual=New-Object Windows.Forms.TrackBar;$manual.SetBounds(22,236,465,42);$manual.Minimum=0;$manual.Maximum=600;$manual.TickFrequency=50
$manual.Value=96;if($null-ne $value.manualClearanceCssPx){$manual.Value=[Math]::Max(0,[Math]::Min(600,[int]$value.manualClearanceCssPx))};$form.Controls.Add($manual)
$stateLabel=LabelAt '' 22 287 465 24
$reset=New-Object Windows.Forms.Button;$reset.Text='恢复默认';$reset.SetBounds(22,318,120,30);$form.Controls.Add($reset)
$close=New-Object Windows.Forms.Button;$close.Text='关闭';$close.SetBounds(367,318,120,30);$form.Controls.Add($close)
$saveTimer=New-Object Windows.Forms.Timer;$saveTimer.Interval=450
$readTimer=New-Object Windows.Forms.Timer;$readTimer.Interval=1000
function UpdateLabels {
 $gapLabel.Text='自动模式的额外间距：'+$gap.Value+' 像素'
 $manualLabel.Text='手动模式的收缩距离：'+$manual.Value+' 像素'
 $gap.Enabled=$mode.SelectedIndex-eq 0;$manual.Enabled=$mode.SelectedIndex-eq 1
}
function SavePreferences {
 $saveTimer.Stop()
 try{
  $payload=@{mode=$(if($mode.SelectedIndex-eq 1){'manual'}else{'auto'});gapCssPx=$gap.Value;manualClearanceCssPx=$manual.Value}|ConvertTo-Json -Compress
  $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
  $result=& $NodePath $service configure --home $HomeDirectory --settings-base64 $encoded 2>&1
  if($LASTEXITCODE-ne 0){throw ($result|Out-String)}
  $stateLabel.Text='已保存，等待输入框更新…'
 }catch{$stateLabel.Text='保存失败：'+$_.Exception.Message}
}
function ScheduleSave {UpdateLabels;$saveTimer.Stop();$saveTimer.Start()}
$gap.Add_ValueChanged({ScheduleSave});$manual.Add_ValueChanged({ScheduleSave});$mode.Add_SelectedIndexChanged({ScheduleSave})
$saveTimer.Add_Tick({SavePreferences})
$readTimer.Add_Tick({
 if($saveTimer.Enabled){return}
 try{
  $current=Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8|ConvertFrom-Json
  $active=@($current.results|Where-Object {$_.status-eq 'active'})
  if($active.Count){$stateLabel.Text='当前实际收缩：'+$active[0].clearanceCssPx+' 像素'}
  elseif($current.status-eq 'original-layout'){$stateLabel.Text='当前保持原样（居中或无桌宠遮挡）'}
  else{$stateLabel.Text='运行状态：'+$current.status}
 }catch{$stateLabel.Text='等待避让插件连接…'}
})
$reset.Add_Click({$mode.SelectedIndex=0;$gap.Value=10;$manual.Value=96;ScheduleSave})
$close.Add_Click({$form.Close()})
$form.Add_FormClosing({if($saveTimer.Enabled){SavePreferences};$saveTimer.Dispose();$readTimer.Dispose()})
UpdateLabels
if($ValidateOnly){$result=@{validated=$true;modeCount=$mode.Items.Count;gapRange=@($gap.Minimum,$gap.Maximum);manualRange=@($manual.Minimum,$manual.Maximum);writesPerformed=$false};$form.Dispose();$saveTimer.Dispose();$readTimer.Dispose();$result|ConvertTo-Json -Compress;exit 0}
$settingsMutex=New-Object Threading.Mutex($false,'Local\CodexClearanceSettings')
if(-not $settingsMutex.WaitOne(0)){
 try{$existingEvent=[Threading.EventWaitHandle]::OpenExisting('Local\CodexClearanceSettingsActivate');$null=$existingEvent.Set();$existingEvent.Dispose()}catch{}
 $settingsMutex.Dispose();$form.Dispose();exit 0
}
$activationEvent=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::AutoReset,'Local\CodexClearanceSettingsActivate')
$activationTimer=New-Object Windows.Forms.Timer;$activationTimer.Interval=200
$activationTimer.Add_Tick({if($activationEvent.WaitOne(0)){$form.Show();$form.WindowState='Normal';$form.Activate()}})
$activationTimer.Start()
$readTimer.Start()
try{$null=$form.ShowDialog()}finally{$activationTimer.Dispose();$activationEvent.Dispose();$form.Dispose();$settingsMutex.ReleaseMutex();$settingsMutex.Dispose()}
