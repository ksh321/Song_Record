function Get-AgentRunPlan([string]$Risk, [string]$Finding, [int]$Failures, [int]$MaximumFailures, [bool]$ReviewAfterUserFix = $false) {
    if ($Failures -lt 0 -or $MaximumFailures -lt 0 -or $MaximumFailures -gt $Failures) {
        throw 'Invalid cumulative failure counters'
    }
    if ($MaximumFailures -ge 3 -and -not $ReviewAfterUserFix) { throw 'Maximum reasoning failed three times; notify user and preserve resume state.' }
    if ($Failures -ge 3 -and $Finding -eq 'EnvironmentOnly') {
        throw 'Environment intervention required; reasoning escalation cannot grant access or install missing tools.'
    }
    $selected = Get-AgentRisk $Risk $Finding
    $model = switch ($selected) { Explore {'gpt-6-luna'} Sensitive {'gpt-6-astra'} Escalation {'gpt-6-astra'} default {'gpt-6-sol'} }
    $effort = switch ($selected) { Complex {'high'} Sensitive {'high'} Escalation {'xhigh'} default {'medium'} }
    if ($Failures -ge 3 -or $MaximumFailures -gt 0) { $model='gpt-6-astra'; $effort='ultra' }
    return @{risk=$selected; model=$model; effort=$effort}
}

function Get-AgentRisk([string]$Risk, [string]$Finding) {
    if ($Finding -in @('None','EnvironmentOnly')) { return $Risk }
    switch ($Risk) {
        Explore { return 'Complex' }
        Implement { return 'Complex' }
        Complex { return 'Sensitive' }
        default { return 'Escalation' }
    }
}

function Get-LoginState([int]$ExitCode, [string]$OutputText) {
    if ($ExitCode -ne 0) { return 'FAIL' }
    if ($OutputText -match 'API key|api_key') { return 'FAIL' }
    if ($OutputText -match 'Logged in using ChatGPT') { return 'PASS' }
    return 'PENDING'
}

function Get-OverallState($Results, [bool]$PolicyPending = $false) {
    if (@($Results | Where-Object status -in @('FAIL','ERROR')).Count) { return 'FAIL' }
    if ($PolicyPending -or -not @($Results).Count -or @($Results | Where-Object status -ne 'PASS').Count) { return 'PENDING' }
    return 'PASS'
}

function Get-LatestCiRun($Runs, [string]$Commit, [string]$Path) {
    # Same-second duplicate pushes need a deterministic run-ID tie breaker.
    # Never select an older success merely because the latest run has not passed.
    $Runs | Where-Object {
        $_.head_sha -eq $Commit -and $_.path -eq $Path -and
        $_.event -in @('push','pull_request','workflow_dispatch')
    } | Sort-Object {[DateTime]$_.created_at}, {[long]$_.id}, {[int]$_.run_attempt} -Descending | Select-Object -First 1
}

function Get-CiState($Run, $Jobs, [string[]]$RequiredJobs, [switch]$AllowUnrequiredSkipped) {
    if (-not $Run -or $Run.status -ne 'completed') { return 'PENDING' }
    if ($Run.conclusion -ne 'success') { return 'FAIL' }
    if (-not @($Jobs).Count) { return 'FAIL' }
    foreach($job in $Jobs) {
        if($job.conclusion -eq 'success'){continue}
        if($AllowUnrequiredSkipped -and $job.name -notin $RequiredJobs -and $job.conclusion -eq 'skipped'){continue}
        return 'FAIL'
    }
    foreach ($name in $RequiredJobs) { if ($name -notin @($Jobs.name)) { return 'PENDING' } }
    return 'PASS'
}

function Get-UsbSerial([int]$ExitCode, [string]$OutputText, [string]$Requested) {
    # The output MUST come from `adb -d get-serialno`: -d selects USB transport.
    if ($ExitCode -ne 0) { return $null }
    $serial = $OutputText.Trim()
    if (-not $serial -or $serial -eq 'unknown' -or $serial -match '\s') { return $null }
    if ($Requested -and $Requested -ne $serial) { return $null }
    return $serial
}
