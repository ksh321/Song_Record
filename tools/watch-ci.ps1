#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [ValidatePattern('^[0-9a-f]{40}$')][string]$BaseCommit,
    [Parameter(Mandatory)][ValidatePattern('^(WORKFLOW-\d{2}|P\d{2}-\d{2}[a-z]?)(-[A-Z0-9]+)?$')][string]$TaskId,
    [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Account='ksh321',
    [ValidateRange(60,1800)][int]$IntervalSeconds=120,
    [ValidateRange(1,48)][int]$MaxHours=12,
    [switch]$Start,
    [switch]$Once
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$dir=Join-Path $root '.local/workflow/ci-watch'
New-Item -ItemType Directory -Force $dir | Out-Null
$pwsh=Join-Path $PSHOME 'pwsh.exe'
if ($Start) {
    if ($Once) { throw 'Start and Once cannot be combined' }
    $argsList=@('-NoProfile','-File',('"'+$PSCommandPath+'"'),'-Commit',$Commit,
        '-TaskId',$TaskId,'-Account',$Account,'-IntervalSeconds',$IntervalSeconds,'-MaxHours',$MaxHours)
    if($BaseCommit){$argsList+=@('-BaseCommit',$BaseCommit)}
    $process=Start-Process -FilePath $pwsh -ArgumentList $argsList -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $dir "$Commit.stdout.log") `
        -RedirectStandardError (Join-Path $dir "$Commit.stderr.log")
    Write-Host "CI watcher launched: PID=$($process.Id), commit=$Commit. Check local state for readiness."
    exit 0
}
. (Join-Path $PSScriptRoot 'ci-notify-common.ps1')
$statePath=Join-Path $dir "$Commit.json"
$lock=$null
try { $lock=[IO.File]::Open((Join-Path $dir "$Commit.lock"),'OpenOrCreate','ReadWrite','None') }
catch { Write-Host 'An existing watcher owns this commit.'; exit 0 }
try {
    if (Test-Path $statePath) {
        $old=Get-Content $statePath -Raw | ConvertFrom-Json
        if ($old.notification -in @('SERVER_ACCEPTED','UNKNOWN')) {
            Write-Host 'Already attempted this commit notification; no automatic duplicate.'; exit 0
        }
    }
    $state=[ordered]@{commit=$Commit;task=$TaskId;pid=$PID;status='WATCHING';notification='NONE';
        started_utc=[DateTime]::UtcNow.ToString('o');updated_utc='';consecutive_errors=0}
    function Save-State {
        $state.updated_utc=[DateTime]::UtcNow.ToString('o')
        $state | ConvertTo-Json | Set-Content $statePath -Encoding utf8
    }
    Save-State
    $deadline=[DateTime]::UtcNow.AddHours($MaxHours)
    while ($true) {
        $result='WAIT'
        try {
            $queried=[DateTime]::UtcNow
            $checkArgs=@('-NoProfile','-File',(Join-Path $PSScriptRoot 'github-check.ps1'),'-Commit',$Commit,'-Account',$Account)
            if($BaseCommit){$checkArgs+=@('-BaseCommit',$BaseCommit)}
            & $pwsh @checkArgs *> (Join-Path $dir "$Commit.check.log")
            $code=$LASTEXITCODE
            $reportPath=Join-Path $root ".local/workflow/ci-$Commit.json"
            if ($code -notin @(0,1,2) -or -not (Test-Path $reportPath)) { throw 'CI read unavailable' }
            $report=Get-Content $reportPath -Raw | ConvertFrom-Json
            if ([DateTime]$report.utc -lt $queried) { throw 'Stale CI report' }
            $result=Get-CiNotificationResult $report $Commit
            $state.consecutive_errors=0
        } catch {
            # Do not forward raw network/credential errors into notifications.
            $state.consecutive_errors++
            if ($state.consecutive_errors -ge 3) { $result='ERROR' }
        }
        if ($result -eq 'WAIT' -and [DateTime]::UtcNow -ge $deadline) { $result='TIMEOUT' }
        $state.status=$result
        Save-State
        if ($result -ne 'WAIT') {
            $config=Get-Content (Join-Path $root '.local/workflow/phone/config.json') -Raw | ConvertFrom-Json
            if ($config.topic -cnotmatch '^sr-[0-9a-f]{48}$') { throw 'Invalid local ntfy configuration' }
            $payload=@{topic=$config.topic;title="$TaskId CI";priority=5;
                message=(Get-CiNotificationText $TaskId $Commit $result)} | ConvertTo-Json -Compress
            # Save before POST: a timeout must not cause an automatic duplicate.
            $state.notification='UNKNOWN'; Save-State
            try {
                $response=Invoke-RestMethod -Uri 'https://ntfy.sh/' -Method Post `
                    -ContentType 'application/json; charset=utf-8' -Headers @{Cache='no'} `
                    -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 20
                if ($response.event -ne 'message' -or -not $response.id) { throw 'Unexpected response' }
            } catch { Write-Host 'CI notification delivery uncertain. Inspect local state; no automatic resend.'; exit 1 }
            $state.notification='SERVER_ACCEPTED'; Save-State
            Write-Host "$TaskId $result notification accepted; human receipt unconfirmed."
            exit 0
        }
        if ($Once) { $state.status='WAIT_ONCE_EXIT'; Save-State; exit 2 }
        Start-Sleep -Seconds $IntervalSeconds
    }
} finally { if ($lock) { $lock.Dispose() } }
