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
    if ($OutputText -match 'Logged in using ChatGPT') { return 'PASS' }
    if ($OutputText -match 'API key|api_key') { return 'FAIL' }
    return 'PENDING'
}

function Get-OverallState($Results, [bool]$PolicyPending = $false) {
    if (@($Results | Where-Object status -in @('FAIL','ERROR')).Count) { return 'FAIL' }
    if ($PolicyPending -or -not @($Results).Count -or @($Results | Where-Object status -ne 'PASS').Count) { return 'PENDING' }
    return 'PASS'
}

function Get-CiState($Run, $Jobs, [string[]]$RequiredJobs) {
    if (-not $Run -or $Run.status -ne 'completed') { return 'PENDING' }
    if ($Run.conclusion -ne 'success') { return 'FAIL' }
    if (-not @($Jobs).Count -or @($Jobs | Where-Object conclusion -ne 'success').Count) { return 'FAIL' }
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
