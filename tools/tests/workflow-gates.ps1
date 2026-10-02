#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'workflow-common.ps1')
$script:cases=0
function Assert-Equal($Actual,$Expected,$Name) {
    if ($Actual -ne $Expected) { throw "$Name expected=$Expected actual=$Actual" }
    $script:cases++
}
Assert-Equal (Get-LoginState 0 'Logged in using ChatGPT') 'PASS' 'subscription'
Assert-Equal (Get-LoginState 0 'Logged in using an API key') 'FAIL' 'API blocked'
Assert-Equal (Get-LoginState 0 'Logged in using ChatGPT; API key') 'FAIL' 'ambiguous API and subscription blocked'
Assert-Equal (Get-LoginState 0 'unknown output') 'PENDING' 'unknown login'
Assert-Equal (Get-LoginState 1 'Logged in using ChatGPT') 'FAIL' 'failed login'
$run=[pscustomobject]@{status='completed';conclusion='success'}
$job=[pscustomobject]@{name='required';conclusion='success'}
$oldRun=[pscustomobject]@{id=36816782842;head_sha='target';path='ci.yml';event='push';created_at='2026-10-01T04:47:59Z';run_attempt=1;status='completed';conclusion='cancelled'}
$newRun=[pscustomobject]@{id=36816783369;head_sha='target';path='ci.yml';event='push';created_at='2026-10-01T04:47:59Z';run_attempt=1;status='in_progress';conclusion=$null}
Assert-Equal (Get-LatestCiRun @($oldRun,$newRun) 'target' 'ci.yml').id $newRun.id 'same-second duplicate selects newest ID'
Assert-Equal (Get-LatestCiRun @($newRun,$oldRun) 'target' 'ci.yml').id $newRun.id 'API ordering independent'
Assert-Equal (Get-CiState (Get-LatestCiRun @($oldRun,$newRun) 'target' 'ci.yml') @() @('required')) 'PENDING' 'replacement still needs validation'
$oldRun.conclusion='success'
$newRun.status='completed'; $newRun.conclusion='failure'
Assert-Equal (Get-CiState (Get-LatestCiRun @($oldRun,$newRun) 'target' 'ci.yml') @($job) @('required')) 'FAIL' 'old success cannot hide newer failure'
Assert-Equal (Get-LatestCiRun @($oldRun,$newRun) 'other' 'ci.yml') $null 'wrong commit excluded'
Assert-Equal (Get-LatestCiRun @($oldRun,$newRun) 'target' 'other.yml') $null 'wrong workflow excluded'
Assert-Equal (Get-CiState $null @() @('required')) 'PENDING' 'missing run'
Assert-Equal (Get-CiState ([pscustomobject]@{status='in_progress'}) @() @('required')) 'PENDING' 'running'
Assert-Equal (Get-CiState $run @($job) @('required')) 'PASS' 'required passed'
Assert-Equal (Get-CiState $run @($job) @('other')) 'PENDING' 'required job missing'
Assert-Equal (Get-CiState $run @() @('required')) 'FAIL' 'empty jobs'
$jobs=@(1..100 | ForEach-Object { $job }) + @([pscustomobject]@{name='last';conclusion='skipped'})
Assert-Equal (Get-CiState $run $jobs @('required')) 'FAIL' '101st skipped job'
Assert-Equal (Get-OverallState @([pscustomobject]@{status='PASS'}) $true) 'PENDING' 'policy unavailable'
Assert-Equal (Get-OverallState @([pscustomobject]@{status='ERROR'})) 'FAIL' 'exception report'
Assert-Equal (Get-UsbSerial 0 'windows-usb-serial' '') 'windows-usb-serial' 'USB transport no usb field'
Assert-Equal (Get-UsbSerial 1 'error: more than one device' '') $null 'multiple USB'
Assert-Equal (Get-UsbSerial 1 'error: device unauthorized' '') $null 'unauthorized USB'
Assert-Equal (Get-UsbSerial 1 'error: no devices found' '') $null 'TCP only no USB'
Assert-Equal (Get-UsbSerial 0 'usb-a' 'usb-b') $null 'wrong selected device'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Assert-Equal (Get-AgentRisk 'Implement' 'EnvironmentOnly') 'Implement' 'environment does not escalate'
Assert-Equal (Get-AgentRisk 'Implement' 'RequirementsMissing') 'Complex' 'omission escalates'
Assert-Equal (Get-AgentRisk 'Complex' 'LogicError') 'Sensitive' 'logic escalates model'
Assert-Equal (Get-AgentRisk 'Sensitive' 'ReviewBlocker') 'Escalation' 'review escalates reasoning'
Assert-Equal (Get-AgentRisk 'Explore' 'None') 'Explore' 'normal exploration'
Assert-Equal (Get-AgentRunPlan 'Implement' 'None' 2 0).model 'gpt-6.1-sol' 'before escalation budget'
Assert-Equal (Get-AgentRunPlan 'Implement' 'LogicError' 3 0).effort 'max' 'third failure plans supported single-agent ceiling'
Assert-Equal (Get-AgentRunPlan 'Explore' 'LogicError' 4 1).model 'gpt-6-astra' 'escalated model persists'
Assert-Equal (Get-AgentRunPlan 'Sensitive' 'ReviewBlocker' 5 2).effort 'max' 'last additional attempt allowed'
$budgetStillBlocked=$false
try { Get-AgentRunPlan 'Sensitive' 'ReviewBlocker' 6 3 $true | Out-Null } catch { $budgetStillBlocked=$true }
Assert-Equal $budgetStillBlocked $true 'user fix cannot silently reset exhausted budget'
foreach($role in @('Worker','Reviewer')) {
    $reason=''
    try { & (Join-Path $root 'tools/run-agent.ps1') -Role $role -PromptFile 'unused-no-login.txt' } catch { $reason=$_.Exception.Message }
    Assert-Equal $reason 'DELEGATION_DISABLED: Use the current task model; new CLI Worker/Reviewer sessions are retired.' 'retired runner blocks before reading input or login'
}
foreach($counters in @(@(6,3),@(3,3),@(2,3))) {
    $blocked=$false
    try { Get-AgentRunPlan 'Sensitive' 'LogicError' $counters[0] $counters[1] | Out-Null } catch { $blocked=$true }
    Assert-Equal $blocked $true 'maximum exhausted or invalid count blocked'
}
$blocked=$false
try { Get-AgentRunPlan 'Implement' 'EnvironmentOnly' 3 0 | Out-Null } catch { $blocked=$true }
Assert-Equal $blocked $true 'environment is not solved by model escalation'
# Isolated copy: exercise the real sender with an in-memory HTTP stub, never ntfy.
$fixture=Join-Path $root ('.local/workflow/notify-tests/'+[guid]::NewGuid().ToString('N'))
$fixtureTools=Join-Path $fixture 'tools'
$phoneDir=Join-Path $fixture '.local/workflow/phone'
New-Item -ItemType Directory -Force $fixtureTools,$phoneDir | Out-Null
$sender=Join-Path $fixtureTools 'phone-notify.ps1'
Copy-Item (Join-Path $root 'tools/phone-notify.ps1') $sender
@{topic=('sr-'+('a'*48))}|ConvertTo-Json|Set-Content (Join-Path $phoneDir 'config.json')
$global:SongRecordTestHttpCalls=0
$global:SongRecordTestHttpFail=$true
$global:SongRecordTestTitle='WORKFLOW-02'
function Invoke-RestMethod {
    param($Uri,$Method,$ContentType,$Headers,$Body,$TimeoutSec)
    $global:SongRecordTestHttpCalls++
    $payload=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
    $global:SongRecordTestMessage=$payload.message
    Assert-Equal $Uri 'https://ntfy.sh/' 'fixed endpoint'
    Assert-Equal $payload.topic.Length 51 'server-compatible topic length'
    Assert-Equal $payload.title $global:SongRecordTestTitle 'safe task and optional item title'
    Assert-Equal $Headers.Cache 'no' 'no remote cache'
    if($global:SongRecordTestHttpFail){throw 'simulated uncertain network failure'}
    return @{event='message';id='synthetic-message'}
}
$failed=$false
try { & $sender -Mode Send } catch { $failed=$true }
Assert-Equal $failed $true 'uncertain send fails'
$attemptFile=Join-Path $phoneDir 'attempt.json'
Assert-Equal ((Get-Content $attemptFile -Raw|ConvertFrom-Json).status) 'UNKNOWN' 'uncertain attempt persisted'
$failed=$false
try { & $sender -Mode Send } catch { $failed=$true }
Assert-Equal $failed $true 'uncertain send cooldown'
Assert-Equal $global:SongRecordTestHttpCalls 1 'cooldown avoids duplicate HTTP'
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='UNKNOWN';task='WORKFLOW-02';kind='Trial'}|ConvertTo-Json|Set-Content $attemptFile
$failed=$false
try { & $sender -Mode Send } catch { $failed=$true }
Assert-Equal $failed $true 'unknown matching delivery blocked after cooldown'
Assert-Equal $global:SongRecordTestHttpCalls 1 'unknown delivery does not resend'
# This isolated fixture now starts a separate, known-unsent scenario.
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$global:SongRecordTestHttpFail=$false
& $sender -Mode Send
Assert-Equal ((Get-Content (Join-Path $phoneDir 'receipt.json') -Raw|ConvertFrom-Json).status) 'SERVER_ACCEPTED' 'HTTP success is not human receipt'
$a=Get-Content $attemptFile -Raw|ConvertFrom-Json
$r=Get-Content (Join-Path $phoneDir 'receipt.json') -Raw|ConvertFrom-Json
Assert-Equal $a.attempt_id $r.attempt_id 'accepted receipt linked to attempt'
$a.utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o')
$a|ConvertTo-Json|Set-Content $attemptFile
$global:SongRecordTestHttpFail=$true
try { & $sender -Mode Send } catch { }
$failed=$false
try { & $sender -Mode Confirm } catch { $failed=$true }
Assert-Equal $failed $true 'uncertain newer attempt cannot confirm old receipt'
$a=Get-Content $attemptFile -Raw|ConvertFrom-Json
$a.status='SERVER_ACCEPTED'
$a.utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o')
$a|ConvertTo-Json|Set-Content $attemptFile
$failed=$false
try { & $sender -Mode Confirm } catch { $failed=$true }
Assert-Equal $failed $true 'accepted status with different attempt ID refused'
$held=[IO.File]::Open((Join-Path $phoneDir 'send.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$before=$global:SongRecordTestHttpCalls
try {
    $failed=$false
    try { & $sender -Mode Send } catch { $failed=$true }
    Assert-Equal $failed $true 'concurrent operation refused'
    Assert-Equal $global:SongRecordTestHttpCalls $before 'locked sender never calls HTTP'
} finally { $held.Dispose() }
$global:SongRecordTestHttpFail=$false
New-Item -ItemType Directory -Force (Join-Path $fixture 'docs/verification') | Out-Null
$recordFile=Join-Path $fixture 'docs/verification/user-action-records.md'
"- [ ] USER-099 — WORKFLOW-02: synthetic escalation`n  - 준비: fixture`n  - 순서: synthetic`n  - 정상 결과: expected`n  - AI에게 알려줄 결과: result" | Set-Content (Join-Path $fixture '내가할일.md')
"### USER-099 — synthetic escalation`n- 상태: **확인 필요**`n- 작업 ID: WORKFLOW-02`n- 요청 판본: 1`n- 알림 종류: Escalation`n- 알림 행동: Details`n" | Set-Content $recordFile
$global:SongRecordTestTitle='WORKFLOW-02 USER-099'
& $sender -Mode Send -Kind Escalation -ItemId USER-099 -BeforeModel Sol -BeforeReasoning high -AfterReasoning max -FailureCode SchedulerRecovery
Assert-Equal ($global:SongRecordTestMessage -match 'Sol/high.*Astra/max') $true 'single-agent escalation models included'
Assert-Equal ($global:SongRecordTestMessage -match '복귀 후 재시도 예약 문제.*판단 필요') $true 'failure and requested action included'
Assert-Equal ((Get-Content (Join-Path $phoneDir 'receipt.json') -Raw|ConvertFrom-Json).status) 'SERVER_ACCEPTED' 'escalation acceptance not receipt'
$before=$global:SongRecordTestHttpCalls
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$reason=''
try { & $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action LoginSetup } catch { $reason=$_.Exception.Message }
Assert-Equal $reason 'Expected exactly one unchecked user action before notifying.' 'document must exist before item notification'
Assert-Equal $global:SongRecordTestHttpCalls $before 'missing document does not call HTTP'
$itemText="### USER-001 — synthetic request`n- 상태: **확인 필요**`n- 작업 ID: WORKFLOW-02`n- 요청 판본: 1`n- 알림 종류: Intervention`n- 알림 행동: LoginSetup`n"
$itemText | Set-Content $recordFile
# Stale metadata alone must not authorize a notification after a user replies.
$sampleTodo="- [ ] USER-001 — WORKFLOW-02: synthetic request`n  - 준비: fixture`n  - 순서: synthetic`n  - 정상 결과: expected`n  - AI에게 알려줄 결과: result"
foreach($todoText in @('현재 직접 할 일 없음', $sampleTodo.Replace('[ ]','[x]'), "$sampleTodo`n$sampleTodo")) {
    @{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
    $todoText | Set-Content (Join-Path $fixture '내가할일.md')
    $reason=''
    try { & $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action LoginSetup } catch { $reason=$_.Exception.Message }
    Assert-Equal $reason 'Expected exactly one unchecked user action before notifying.' 'absent completed or duplicate checklist item refused for correct reason'
    Assert-Equal $global:SongRecordTestHttpCalls $before 'invalid checklist never calls HTTP'
}
$validTodo="- [ ] USER-001 — WORKFLOW-02: synthetic request`n  - 준비: fixture`n  - 순서: synthetic`n  - 정상 결과: expected`n  - AI에게 알려줄 결과: result"
$invalidCases=@(
    @($validTodo.Replace('WORKFLOW-02','WORKFLOW-03'), 'User action title must include the matching task ID.'),
    @($validTodo.Replace('WORKFLOW-02:','WORKFLOW-03: WORKFLOW-02 reference'), 'User action title must include the matching task ID.')
)
foreach($label in @('준비','순서','정상 결과','AI에게 알려줄 결과')) {
    $invalidCases += ,@(($validTodo -replace "(?m)^  - $([regex]::Escape($label)): [^`r`n]*", ''), "User action is missing required guidance: $label")
}
foreach ($case in $invalidCases) {
    @{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
    $case[0] | Set-Content (Join-Path $fixture '내가할일.md')
    $reason=''
    try { & $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action LoginSetup } catch { $reason=$_.Exception.Message }
    Assert-Equal $reason $case[1] 'specific guidance error not cooldown or other failure'
    Assert-Equal $global:SongRecordTestHttpCalls $before 'invalid guidance never sends HTTP'
}
$validTodo | Set-Content (Join-Path $fixture '내가할일.md')

@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$global:SongRecordTestTitle='WORKFLOW-02 USER-001'
$failed=$false
try { & $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action Device } catch { $failed=$true }
Assert-Equal $failed $true 'action must match recorded request'
Assert-Equal $global:SongRecordTestHttpCalls $before 'mismatched action does not call HTTP'
& $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action LoginSetup
Assert-Equal ($global:SongRecordTestMessage -match 'USER-001 r1:.*로그인 설정 파일 경로') $true 'item ID and fixed action summary included'
$before=$global:SongRecordTestHttpCalls
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$failed=$false
try { & $sender -Mode Send -ItemId USER-001 -Kind Intervention -Action LoginSetup } catch { $failed=$true }
Assert-Equal $failed $true 'accepted item stays deduplicated across unrelated attempts'
Assert-Equal $global:SongRecordTestHttpCalls $before 'duplicate item does not call HTTP'
$global:SongRecordTestHttpFail=$true
$failed=$false
try { & $sender -Mode Send -ItemId USER-001 -Revision 2 -Kind Intervention -Action LoginSetup } catch { $failed=$true }
Assert-Equal $failed $true 'unrecorded revision rejected'
Assert-Equal $global:SongRecordTestHttpCalls $before 'unrecorded revision does not call HTTP'
$itemText.Replace('요청 판본: 1','요청 판본: 2') | Set-Content $recordFile
$reason=''
try { & $sender -Mode Send -ItemId USER-001 -Revision 2 -Kind Intervention -Action LoginSetup } catch { $reason=$_.Exception.Message }
Assert-Equal $reason 'Record the pending state, matching task/revision and revision change reason before notifying.' 'revision change reason required specifically'
Assert-Equal $global:SongRecordTestHttpCalls $before 'missing reason rejects before HTTP'
(($itemText.Replace('요청 판본: 1','요청 판본: 2')+"- 변경 이유: synthetic target change`n").Replace("`n","`r`n")) | Set-Content $recordFile
try { & $sender -Mode Send -ItemId USER-001 -Revision 2 -Kind Intervention -Action LoginSetup } catch { }
Assert-Equal $global:SongRecordTestHttpCalls ($before+1) 'CRLF revision reason reaches HTTP exactly once'
$before=$global:SongRecordTestHttpCalls
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$failed=$false
try { & $sender -Mode Send -ItemId USER-001 -Revision 2 -Kind Intervention -Action LoginSetup } catch { $failed=$true }
Assert-Equal $failed $true 'uncertain item revision also remains deduplicated'
Assert-Equal $global:SongRecordTestHttpCalls $before 'uncertain item never automatically resends'
# Distinct request after uncertain delivery is not a retry of that request.
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='UNKNOWN';task='WORKFLOW-02';kind='Intervention';item_id='USER-001';revision=2}|ConvertTo-Json|Set-Content $attemptFile
$validTodo.Replace('USER-001','USER-002') | Set-Content (Join-Path $fixture '내가할일.md')
$itemText.Replace('USER-001','USER-002') | Set-Content $recordFile
$global:SongRecordTestTitle='WORKFLOW-02 USER-002'
$global:SongRecordTestHttpFail=$false
& $sender -Mode Send -ItemId USER-002 -Kind Intervention -Action LoginSetup
Assert-Equal $global:SongRecordTestHttpCalls ($before+1) 'distinct request sends after uncertain previous item'
$before=$global:SongRecordTestHttpCalls
$validTodo | Set-Content (Join-Path $fixture '내가할일.md')
$global:SongRecordTestTitle='WORKFLOW-02 USER-001'
foreach($kind in @('Intervention','PhoneTest','Escalation')) {
    $failed=$false
    try { & $sender -Mode Send -Kind $kind } catch { $failed=$true }
    Assert-Equal $failed $true 'every user-action kind requires recorded item ID'
}
($itemText.Replace('확인 필요','완료').Replace('요청 판본: 1','요청 판본: 3')+"- 변경 이유: synthetic closed request`n") | Set-Content $recordFile
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='NOT_SENT'}|ConvertTo-Json|Set-Content $attemptFile
$reason=''
try { & $sender -Mode Send -ItemId USER-001 -Revision 3 -Kind Intervention -Action LoginSetup } catch { $reason=$_.Exception.Message }
Assert-Equal $reason 'Record the pending state, matching task/revision and revision change reason before notifying.' 'completed item rejects for recorded status'
Assert-Equal $global:SongRecordTestHttpCalls $before 'rejected requests never call HTTP'
Remove-Item Function:Invoke-RestMethod
Remove-Variable SongRecordTestHttpCalls,SongRecordTestHttpFail,SongRecordTestMessage,SongRecordTestTitle -Scope Global
& pwsh -NoProfile -File (Join-Path $root 'tools/workflow.ps1') -Mode Quick -Python '__nonexistent_python_workflow_test__' *> $null
Assert-Equal $LASTEXITCODE 1 'execution error process status'
$report = Get-Content (Join-Path $root '.local/workflow/quick.json') -Raw | ConvertFrom-Json
Assert-Equal $report.overall 'FAIL' 'execution error overall'
Assert-Equal $report.execution_error $true 'execution error flag'
Assert-Equal $report.scope 'working_tree' 'dirty worktree attribution'
Write-Host "PASS: $script:cases workflow failure/acceptance cases"
# GitHub's pwsh wrapper propagates LASTEXITCODE. The deliberately failing child
# above must not become this successful test suite's process result.
exit 0
