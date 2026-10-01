#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Init','Subscribe','Send','Confirm')][string]$Mode='Send',
    [ValidatePattern('^(WORKFLOW-\d{2}|P\d{2}-\d{2}[a-z]?)(-[A-Z0-9]+)?$')][string]$TaskId='WORKFLOW-02',
    [ValidateSet('Trial','PhoneTest','Intervention','Escalation')][string]$Kind='Trial',
    [ValidatePattern('^USER-\d{3}$')][string]$ItemId,
    [ValidateRange(1,999)][int]$Revision=1,
    [ValidateSet('Details','LoginSetup','Device','PhoneSteps','Decision')][string]$Action='Details',
    [ValidateSet('Luna','Sol','Astra')][string]$BeforeModel='Astra',
    [ValidateSet('medium','high','xhigh','max','ultra','high/xhigh')][string]$BeforeReasoning='high',
    [ValidateSet('ultra','unconfirmed')][string]$AfterReasoning='ultra',
    [ValidateSet('SchedulerRecovery','AuthFollowup','LogicContract','EnvironmentBlocked','ModelUnavailable')][string]$FailureCode='LogicContract',
    [string]$Adb='adb'
)
$ErrorActionPreference='Stop'
$dir=Join-Path (Split-Path $PSScriptRoot -Parent) '.local/workflow/phone'
$config=Join-Path $dir 'config.json'
$receipt=Join-Path $dir 'receipt.json'
$attempt=Join-Path $dir 'attempt.json'
New-Item -ItemType Directory -Force $dir | Out-Null
$lock=$null
try { $lock=[IO.File]::Open((Join-Path $dir 'send.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
catch { throw 'Another notification operation is active; retry later.' }
try {
if ($Mode -eq 'Init') {
    if (-not (Test-Path $config)) {
        @{topic=('sr-'+[Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLowerInvariant())} |
            ConvertTo-Json | Set-Content $config -Encoding utf8
    }
    Write-Host 'Local topic ready; not subscribed or delivery verified.'; exit 0
}
if (-not (Test-Path $config)) { throw 'Run Init first.' }
$topic=(Get-Content $config -Raw | ConvertFrom-Json).topic
if ($topic -cnotmatch '^sr-[0-9a-f]{48}$') { throw 'Invalid local topic.' }
if ($Mode -eq 'Subscribe') {
    # Suppress Android's echo of the secret topic. Never put it in committed evidence.
    $output=& $Adb -d shell am start -a android.intent.action.VIEW -d "ntfy://ntfy.sh/$topic" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $output -match 'Error|Exception') { throw 'Phone subscription failed; check ntfy installation and USB.' }
    Write-Host 'Subscription intent accepted; human receipt still pending.'; exit 0
}
if ($Mode -eq 'Confirm') {
    if (-not (Test-Path $receipt)) { throw 'No trial send to confirm.' }
    $r=Get-Content $receipt -Raw | ConvertFrom-Json
    if (-not (Test-Path $attempt)) { throw 'No matching attempt.' }
    $a=Get-Content $attempt -Raw | ConvertFrom-Json
    if (-not $r.attempt_id -or $r.attempt_id -ne $a.attempt_id -or $a.status -ne 'SERVER_ACCEPTED') { throw 'Latest attempt is not the accepted trial; confirmation refused.' }
    if ($r.kind -ne 'Trial' -or $r.task -ne $TaskId -or $r.status -ne 'SERVER_ACCEPTED') { throw 'No matching accepted trial.' }
    # Master calls only after an explicit human reply confirming this trial on the phone.
    $r.status='HUMAN_CONFIRMED'; $r | Add-Member confirmed_utc ([DateTime]::UtcNow.ToString('o')) -Force
    $r | ConvertTo-Json | Set-Content $receipt -Encoding utf8
    Write-Host 'Human receipt confirmation recorded.'; exit 0
}
$itemRecord=$null
if ($Kind -ne 'Trial' -and -not $ItemId) { throw 'User action notifications require an item ID recorded in 내가할일.md.' }
if ($ItemId) {
    $todo=Join-Path (Split-Path $PSScriptRoot -Parent) '내가할일.md'
    if (-not (Test-Path $todo)) {
        throw 'Update the user action document before sending an item notification.'
    }
    $active=[regex]::Matches((Get-Content $todo -Raw), "(?m)^- \[ \] $ItemId —[^\r\n]+\r?$")
    if ($active.Count -ne 1) { throw 'Expected exactly one unchecked user action before notifying.' }
    $todoText=Get-Content $todo -Raw
    $taskTitlePattern="(?m)^- \[ \] $ItemId — $([regex]::Escape($TaskId)):[^\r\n]+\r?$"
    if ($todoText -notmatch $taskTitlePattern) { throw 'User action title must include the matching task ID.' }
    $actionSections=[regex]::Matches($todoText,"(?ms)^- \[ \] $ItemId —[^\r\n]*\r?\n(?<body>.*?)(?=^- \[[ x]\] USER-\d{3} —|\z)")
    if ($actionSections.Count -ne 1) { throw 'Expected one user action section.' }
    foreach ($label in @('준비','순서','정상 결과','AI에게 알려줄 결과')) {
        if ($actionSections[0].Groups['body'].Value -notmatch "(?m)^  - $([regex]::Escape($label)): \S[^\r\n]*\r?$") {
            throw "User action is missing required guidance: $label"
        }
    }
    $records=Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/verification/user-action-records.md'
    if (-not (Test-Path $records)) { throw 'Record request metadata before notifying.' }
    $sections=[regex]::Matches((Get-Content $records -Raw), "(?ms)^### $ItemId —[^\r\n]*\r?\n(?<body>.*?)(?=^#{1,3} |\z)")
    if ($sections.Count -ne 1) { throw 'Expected exactly one matching item in the user action document.' }
    $body=$sections[0].Groups['body'].Value
    if ($body -notmatch '(?m)^- 상태: \*\*확인 필요\*\*\s*$' -or
        $body -notmatch "(?m)^- 작업 ID: $([regex]::Escape($TaskId))\s*$" -or
        $body -notmatch "(?m)^- 요청 판본: $Revision\s*$" -or
        $body -notmatch "(?m)^- 알림 종류: $Kind\s*$" -or
        $body -notmatch "(?m)^- 알림 행동: $Action\s*$" -or
        ($Revision -gt 1 -and $body -notmatch '(?m)^- 변경 이유: \S[^\r\n]*\r?$')) {
        throw 'Record the pending state, matching task/revision and revision change reason before notifying.'
    }
    $items=Join-Path $dir 'items'
    New-Item -ItemType Directory -Force $items | Out-Null
    $itemRecord=Join-Path $items "$ItemId-r$Revision.json"
    if (Test-Path $itemRecord) { throw 'This item revision was already attempted; do not send a duplicate notification.' }
}
if (Test-Path $attempt) {
    $previous=Get-Content $attempt -Raw | ConvertFrom-Json
    if (([DateTime]::UtcNow-[DateTime]$previous.utc).TotalSeconds -lt 60) { throw 'Wait at least 60 seconds between notifications.' }
    if ($previous.status -eq 'UNKNOWN' -and $previous.task -eq $TaskId -and $previous.kind -eq $Kind -and
        ((-not $ItemId) -or (-not $previous.item_id) -or ($previous.item_id -eq $ItemId -and $previous.revision -eq $Revision))) {
        throw 'Previous matching notification has unknown delivery. Check it with the user; do not automatically resend.'
    }
}
# Fixed templates only: no logs, URLs, free text, account names or credentials.
$message=switch($Kind) {
    Trial {'시험 알림입니다. 휴대폰 수신 여부를 대화에 알려주세요.'}
    PhoneTest {'휴대폰 테스트가 필요합니다. 대화의 조작 순서를 확인해 주세요.'}
    Intervention {'사용자 조작이 필요합니다. 대화의 요청 사항을 확인해 주세요.'}
    Escalation {
        $summary=switch($FailureCode) {
            SchedulerRecovery {'복귀 후 재시도 예약 문제'}
            AuthFollowup {'인증 차단 뒤 자동 후속 전송 문제'}
            LogicContract {'요구사항·논리 검증 실패'}
            EnvironmentBlocked {'실행 환경·권한 문제'}
            ModelUnavailable {'최대 추론 실행 미확인'}
        }
        $escalationAction=if($FailureCode -eq 'ModelUnavailable'){'Astra 최대 추론 설정 확인 필요'}else{'대화의 실패 기록·재개 방안 판단 필요'}
        "$BeforeModel/$BeforeReasoning → Astra/${AfterReasoning}: $summary. $escalationAction."
    }
}
$title=$TaskId
if ($ItemId) {
    $title="$TaskId $ItemId"
    $actionText=switch($Action) {
        LoginSetup {'로그인 설정 파일 경로 또는 없음/모름을 알려주세요.'}
        Device {'휴대폰을 USB로 연결하고 디버깅을 허용해 주세요.'}
        PhoneSteps {'준비된 앱의 실기 순서를 확인하고 결과를 알려주세요.'}
        Decision {'기록된 선택 사항을 확인하고 결정해 주세요.'}
        Details {'기록된 요청 사항을 확인하고 답해주세요.'}
    }
    $message="$ItemId r${Revision}: $actionText 자세한 내용은 내가할일.md와 대화를 확인하세요. " + $(if($Kind -eq 'Escalation'){$message}else{''})
}
# Urgent Android channel; sound duration/volume remain user-controlled on phone.
$payload=@{topic=$topic;title=$title;message=$message;priority=5} | ConvertTo-Json -Compress
$sendAttempt=@{attempt_id=[guid]::NewGuid().ToString('N');utc=[DateTime]::UtcNow.ToString('o');task=$TaskId;kind=$Kind;status='UNKNOWN'}
if ($ItemId) {
    $sendAttempt.item_id=$ItemId; $sendAttempt.revision=$Revision
    $sendAttempt | ConvertTo-Json | Set-Content $itemRecord -Encoding utf8
}
$sendAttempt | ConvertTo-Json | Set-Content $attempt -Encoding utf8
try {
    $response=Invoke-RestMethod -Uri 'https://ntfy.sh/' -Method Post -ContentType 'application/json; charset=utf-8' -Headers @{Cache='no'} -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 20
    if ($response.event -ne 'message' -or -not $response.id) { throw 'Unexpected response' }
} catch { throw 'Notification send failed or uncertain. Do not claim delivery; retry only after checking state.' }
$sendAttempt.status='SERVER_ACCEPTED'
if ($itemRecord) { $sendAttempt | ConvertTo-Json | Set-Content $itemRecord -Encoding utf8 }
$sendAttempt | ConvertTo-Json | Set-Content $attempt -Encoding utf8
@{attempt_id=$sendAttempt.attempt_id;utc=[DateTime]::UtcNow.ToString('o');task=$TaskId;kind=$Kind;status='SERVER_ACCEPTED';message_id=$response.id} |
    ConvertTo-Json | Set-Content $receipt -Encoding utf8
Write-Host "$TaskId notification accepted by server; phone receipt PENDING."
} finally { if($lock){$lock.Dispose()} }
