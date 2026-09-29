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
Assert-Equal (Get-LoginState 0 'unknown output') 'PENDING' 'unknown login'
Assert-Equal (Get-LoginState 1 'Logged in using ChatGPT') 'FAIL' 'failed login'
$run=[pscustomobject]@{status='completed';conclusion='success'}
$job=[pscustomobject]@{name='required';conclusion='success'}
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
function Invoke-RestMethod {
    param($Uri,$Method,$ContentType,$Headers,$Body,$TimeoutSec)
    $global:SongRecordTestHttpCalls++
    $payload=[Text.Encoding]::UTF8.GetString($Body)|ConvertFrom-Json
    Assert-Equal $Uri 'https://ntfy.sh/' 'fixed endpoint'
    Assert-Equal $payload.topic.Length 51 'server-compatible topic length'
    Assert-Equal $payload.title 'WORKFLOW-02' 'task only title'
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
@{utc=[DateTime]::UtcNow.AddMinutes(-2).ToString('o');status='UNKNOWN'}|ConvertTo-Json|Set-Content $attemptFile
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
Remove-Item Function:Invoke-RestMethod
Remove-Variable SongRecordTestHttpCalls,SongRecordTestHttpFail -Scope Global
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
