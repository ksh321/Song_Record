#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ci-scope.ps1')
. (Join-Path $PSScriptRoot '../workflow-common.ps1')
. (Join-Path $PSScriptRoot '../ci-notify-common.ps1')
$count=0
function Assert($ok,$label){if(-not $ok){throw $label};$script:count++}
function Names($paths){return @((Get-CiScope $paths | Where-Object required).name)}
Assert ((Names @('docs/progress.md','AGENTS.md','내가할일.md')).Count -eq 0) 'documentation requires no CI'
Assert (((Names @('tools/phone-notify.ps1')) -join ',') -eq 'Development workflow') 'notification only automation'
Assert (((Names @('docs/workflow-state.json')) -join ',') -eq 'Development workflow') 'executable state is not prose'
Assert (((Names @('docs/reference/search/plan.txt')) -join ',') -eq 'Development workflow') 'source provenance'
$mobile=@(Get-CiScope @('apps/mobile/lib/main.dart'))
Assert ((($mobile | Where-Object required).name -join ',') -eq 'CI') 'mobile workflow'
Assert ((($mobile | Where-Object name -eq 'CI').jobs -join ',') -eq 'Scope changed files,Flutter analyze, test, and Android build') 'mobile excludes backend jobs'
$server=@(Get-CiScope @('services/api/src/main/Test.java'))
Assert ((($server | Where-Object name -eq 'CI').jobs -join ',') -eq 'Scope changed files,Spring Boot build and test,MySQL migrations and constraints') 'backend jobs'
Assert ('Idempotency MySQL' -in ($server | Where-Object required).name) 'backend database integration'
foreach($path in @('docs/contracts/openapi.yaml','fixtures/contracts/api-wire.json','.github/workflows/ci.yml','tools/ci-event-scope.ps1','.unknown-build-config')) {
    Assert ((Names @($path)).Count -ge 3) "sensitive or unknown path: $path"
}
Assert ((Names @('docs/progress.md','apps/mobile/pubspec.lock','tools/phone-notify.ps1')).Count -eq 2) 'mixed push union'
Assert (@(Get-CiScope @() $true | Where-Object required).Count -eq 4) 'unknown range all required'
$run=[pscustomobject]@{status='completed';conclusion='success'}
$jobs=@([pscustomobject]@{name='required';conclusion='success'},[pscustomobject]@{name='unrelated';conclusion='skipped'})
Assert ((Get-CiState $run $jobs @('required') -AllowUnrequiredSkipped) -eq 'PASS') 'only out-of-scope skip allowed'
Assert ((Get-CiState $run $jobs @('required','unrelated') -AllowUnrequiredSkipped) -eq 'FAIL') 'required skip fails'
$jobs[1].conclusion='failure'
Assert ((Get-CiState $run $jobs @('required') -AllowUnrequiredSkipped) -eq 'FAIL') 'unexpected failure not hidden'
$sha='a'*40
$report=[pscustomobject]@{commit=$sha;base_commit=('b'*40);scope_mode='explicit-push-range';checks=@(Get-CiScope @('AGENTS.md') | ForEach-Object {[pscustomobject]@{path=$_.path;status='NOT_APPLICABLE'}})}
Assert ((Get-CiNotificationResult $report $sha) -eq 'NOT_REQUIRED') 'no CI is not PASS'
$report.scope_mode='unknown-range-all';$rejected=$false
try{Get-CiNotificationResult $report $sha | Out-Null}catch{$rejected=$true}
Assert $rejected 'exemption without evidence rejected'
# Trigger lists are generated from the same policy; detect future drift.
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$policy=Get-Content (Join-Path $root 'tools/ci-policy.json') -Raw | ConvertFrom-Json
foreach($workflow in $policy.workflows) {
    $expected=@('**')+@($workflow.exclude | ForEach-Object {'!'+$_})+@($workflow.include)+@($policy.always)
    $source=Get-Content (Join-Path $root $workflow.path) -Raw
    $blocks=[regex]::Matches($source,'(?ms)^    paths:\r?\n(?<paths>(?:      - [^\r\n]+\r?\n)+)')
    Assert ($blocks.Count -eq 2) 'push and PR filter present'
    foreach($block in $blocks) {
        $actual=@([regex]::Matches($block.Groups['paths'].Value,'(?m)^      - (.+)') | ForEach-Object {$_.Groups[1].Value | ConvertFrom-Json})
        Assert (($actual -join '|') -ceq ($expected -join '|')) "trigger policy drift $($workflow.path)"
    }
}
Write-Host "CI scope: $count PASS."
