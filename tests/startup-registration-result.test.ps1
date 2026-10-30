$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\scripts\Bundle.Common.ps1')
$persistent=@{rootNonVolatile=$true;packageNonVolatile=$true}
$cases=@(
 @{name='new registration';output=(@{state='registered';registration=@{registryPersistence=$persistent}}|ConvertTo-Json -Depth 5 -Compress);exit=0;expected=$true},
 @{name='already registered';output=(@{state='persistent-registration-verified';registryPersistence=$persistent}|ConvertTo-Json -Depth 5 -Compress);exit=0;expected=$true},
 @{name='temporary package';output=(@{state='registered';registration=@{registryPersistence=@{rootNonVolatile=$true;packageNonVolatile=$false}}}|ConvertTo-Json -Depth 5 -Compress);exit=0;expected=$false},
 @{name='missing verification';output=(@{state='persistent-registration-verified'}|ConvertTo-Json -Compress);exit=0;expected=$false},
 @{name='plugin disabled';output=(@{state='plugin-disabled'}|ConvertTo-Json -Compress);exit=0;expected=$false},
 @{name='process failure';output='';exit=1;expected=$false},
 @{name='invalid response';output='not-json';exit=0;expected=$false}
)
foreach($case in $cases){
 $passed=$false
 try{$null=Assert-BundleStartupRegistration @($case.output) $case.exit;$passed=$true}catch{}
 if($passed-ne $case.expected){throw ('Unexpected registration validation: '+$case.name)}
}
@{passed=$true;caseCount=$cases.Count;clientTouched=$false}|ConvertTo-Json -Compress
