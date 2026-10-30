$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\plugins\codex-right-clearance\scripts\settings-feedback.ps1')
$now=[DateTime]::UtcNow
$preferences=@{mode='auto';gapCssPx=24;manualClearanceCssPx=106}
function Fixture {
 return @{
  time=$now.ToString('o');status='active';connectionSetup=@{state='connected'}
  appliedPreferences=@{mode='auto';gapCssPx=24;manualClearanceCssPx=106}
  results=@(@{status='active';pageVisible=$true;placement='bottom';geometryVerified=$true;domButtonsUncovered=$true;clearanceCssPx=90;requestedClearanceCssPx=90})
 }
}
$cases=@()
function Check($Name,$Status,$Expected,$Settings=@{enabled=$true;mode='auto';gapCssPx=24;manualClearanceCssPx=106},$ChangedAt=[DateTime]::MinValue){
 $feedback=Get-ClearanceSettingsFeedback -Preferences $preferences -Settings $Settings -Status $Status -Now $now -ChangedAt $ChangedAt
 if($feedback.code-ne $Expected){throw ($Name+': '+$feedback.code+' != '+$Expected)}
 $script:cases+=@{name=$Name;code=$feedback.code;text=$feedback.text;detail=$feedback.detail;passed=$true}
}
Check 'verified visible applied snapshot' (Fixture) 'applied'
$s=Fixture;$s.results[0].clearanceMode='fallback';Check 'fixed fallback does not claim extra gap applied' $s 'fallback'
$s=Fixture;$s.appliedPreferences.gapCssPx=0;Check 'saved value not yet read by worker' $s 'pending'
$s=Fixture;$s.time=$now.AddSeconds(-30).ToString('o');Check 'stale result never claimed applied' $s 'stale'
$s=Fixture;$s.time=$now.AddSeconds(30).ToString('o');Check 'future result rejected' $s 'stale'
$s=Fixture;$s.results[0].pageVisible=$false;Check 'background frame is not current input' $s 'waiting'
$s=Fixture;$s.results[0].geometryVerified=$false;Check 'unverified geometry not success' $s 'waiting'
$s=Fixture;$s.results[0].clearanceCssPx=0;Check 'zero shrink not success' $s 'waiting'
$s=Fixture;$s.results[0].clearanceCssPx=80;Check 'wrong actual shrink not success' $s 'waiting'
$s=Fixture;$s.results[0].domButtonsUncovered=$false;Check 'covered buttons not success' $s 'waiting'
$s=Fixture;$s.results=@(@{status='original';pageVisible=$true;placement='centered';requestedClearanceCssPx=90});Check 'centered input explained' $s 'centered'
$s=Fixture;$s.results=@(@{status='original';pageVisible=$true;placement='bottom';requestedClearanceCssPx=0});Check 'no overlapping pet explained' $s 'original'
$s=Fixture;$s.connectionSetup.state='connection-unavailable';Check 'missing connection explained' $s 'disconnected'
$s=Fixture;$s.connectionSetup.state='connection-unavailable';$s.connectionSetup.requiresClientReopen=$true;Check 'startup connection cannot be repaired with a slider' $s 'startup-connection-missing'
$s=Fixture;$s.appliedPreferences=$null;Check 'old worker without acknowledgement pending' $s 'pending'
$s=Fixture;Check 'newer edit waits for sample' $s 'pending' -ChangedAt $now.AddSeconds(1)
$s=Fixture;Check 'failed save never claimed applied' $s 'not-saved' -Settings @{enabled=$true;mode='auto';gapCssPx=0;manualClearanceCssPx=106}
$s=Fixture;Check 'disabled state explained' $s 'disabled' -Settings @{enabled=$false;mode='auto';gapCssPx=24;manualClearanceCssPx=106}
$s=Fixture;$s.results+=@{status='active';pageVisible=$true;placement='bottom';geometryVerified=$true;domButtonsUncovered=$true;clearanceCssPx=90;requestedClearanceCssPx=90};Check 'ambiguous visible inputs not claimed applied' $s 'ambiguous'
$s=Fixture;$s.results=@();$s.status='error';Check 'layout failure explained' $s 'error'
$report=@{time=$now.ToString('o');passed=$true;cases=$cases;realClientTouched=$false}

[ordered]@{passed=$true;caseCount=$cases.Count;realClientTouched=$false}|ConvertTo-Json -Compress
