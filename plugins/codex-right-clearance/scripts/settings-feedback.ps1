function Test-ClearancePreferencesEqual($Left,$Right) {
 if($null-eq $Left-or $null-eq $Right){return $false}
 return $Left.mode-eq $Right.mode-and $null-ne $Left.gapCssPx-and $null-ne $Right.gapCssPx-and [int]$Left.gapCssPx-eq [int]$Right.gapCssPx-and $null-ne $Left.manualClearanceCssPx-and $null-ne $Right.manualClearanceCssPx-and [int]$Left.manualClearanceCssPx-eq [int]$Right.manualClearanceCssPx
}
function Get-ClearanceSettingsFeedback($Preferences,$Settings,$Status,[DateTime]$ChangedAt=[DateTime]::MinValue,[DateTime]$Now=[DateTime]::UtcNow) {
 $selection=if($Preferences.mode-eq 'manual'){'手动收缩 '+$Preferences.manualClearanceCssPx+' 像素'}else{'自动额外间距 '+$Preferences.gapCssPx+' 像素'}
 function Feedback($code,$text,$detail){return [pscustomobject]@{code=$code;text=$text;detail=$detail}}
 if(-not (Test-ClearancePreferencesEqual $Preferences $Settings)){return Feedback 'not-saved' '当前数值尚未保存' '拖动结束后自动保存；保存失败时会显示原因。'}
 if($Settings.enabled-ne $true){return Feedback 'disabled' '参数已保存，避让插件尚未启用' $selection}
 $sampleAt=[DateTime]::MinValue
 if($null-eq $Status-or -not [DateTime]::TryParse([string]$Status.time,[ref]$sampleAt)-or ($Now-$sampleAt.ToUniversalTime()).TotalSeconds-gt 15-or ($Now-$sampleAt.ToUniversalTime()).TotalSeconds-lt -1){return Feedback 'stale' '参数已保存，尚未收到实时结果' '可点击“重新应用”，只重连本插件。'}
 if($Status.connectionSetup.requiresClientReopen-eq $true){return Feedback 'startup-connection-missing' '参数已保存，本次启动缺少避让连接' '需完整重新打开 Codex 一次；调整滑块不能补建连接。'}
 if($Status.connectionSetup.state-ne 'connected'){return Feedback 'disconnected' '参数已保存，输入框连接尚未恢复' '可点击“重新应用”；不会关闭或重启 Codex。'}
 if(-not (Test-ClearancePreferencesEqual $Preferences $Status.appliedPreferences)-or $sampleAt.ToUniversalTime()-lt $ChangedAt.ToUniversalTime()){return Feedback 'pending' '参数已保存，等待插件应用' $selection}
 $visible=@($Status.results|Where-Object {$_.pageVisible-eq $true})
 $active=@($visible|Where-Object {$_.status-eq 'active'-and $_.geometryVerified-eq $true-and $_.domButtonsUncovered-eq $true-and $_.placement-eq 'bottom'-and $null-ne $_.clearanceCssPx-and [double]$_.clearanceCssPx-ge 1-and [Math]::Abs([double]$_.clearanceCssPx-[double]$_.requestedClearanceCssPx)-le 1})
 if($active.Count-eq 1){
  if($Preferences.mode-eq 'auto'-and $active[0].clearanceMode-eq 'fallback'){return Feedback 'fallback' '参数已保存，桌宠测量暂不可用' ('暂用固定收缩 '+$active[0].clearanceCssPx+' 像素；测量恢复后应用额外间距。')}
  return Feedback 'applied' '已生效' ($selection+'；实际收缩 '+$active[0].clearanceCssPx+' 像素')
 }
 if($active.Count-gt 1){return Feedback 'ambiguous' '参数已保存，当前输入框不唯一' '尚不能确认当前可见输入框的实际收缩。'}
 if(@($visible|Where-Object {$_.status-eq 'original'-and $_.placement-eq 'centered'}).Count){return Feedback 'centered' '参数已应用，居中输入框保持原样' '进入底部对话输入框后才会收缩。'}
 if(@($visible|Where-Object {$_.status-eq 'original'-and $_.requestedClearanceCssPx-eq 0}).Count){return Feedback 'original' '参数已应用，当前保持原宽' $(if($Preferences.mode-eq 'manual'){'手动收缩距离为 0。'}else{'当前没有桌宠遮挡，无需收缩。'})}
 if($Status.status-eq 'error'){return Feedback 'error' '参数已保存，布局检查未通过' '可点击“重新应用”，恢复连接后再确认。'}
 return Feedback 'waiting' '参数已保存，等待可调整的输入框' '当前页面尚无可确认的底部输入框。'
}
