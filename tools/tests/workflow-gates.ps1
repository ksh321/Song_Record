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
& pwsh -NoProfile -File (Join-Path $root 'tools/workflow.ps1') -Mode Quick -Python '__nonexistent_python_workflow_test__' *> $null
Assert-Equal $LASTEXITCODE 1 'execution error process status'
$report = Get-Content (Join-Path $root '.local/workflow/quick.json') -Raw | ConvertFrom-Json
Assert-Equal $report.overall 'FAIL' 'execution error overall'
Assert-Equal $report.execution_error $true 'execution error flag'
Assert-Equal $report.scope 'working_tree' 'dirty worktree attribution'
Write-Host "PASS: $script:cases workflow failure/acceptance cases"
