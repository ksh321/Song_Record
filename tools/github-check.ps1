#requires -Version 7.0
[CmdletBinding()]
param([ValidatePattern('^[0-9a-f]{40}$')][string]$Commit, [switch]$InspectPolicy,
      [ValidatePattern('^[0-9a-f]{40}$')][string]$BaseCommit,
      [ValidatePattern('^[a-zA-Z0-9-]+$')][string]$Account)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
. (Join-Path $PSScriptRoot 'workflow-common.ps1')
. (Join-Path $PSScriptRoot 'ci-scope.ps1')
$gitArgs = @('-c',"safe.directory=$($root.Replace('\','/'))")
if (-not $Commit) { $Commit = & git @gitArgs rev-parse HEAD; if ($LASTEXITCODE) { throw 'Cannot read HEAD' } }
$remote = & git @gitArgs remote get-url origin
if ($LASTEXITCODE -or $remote -notmatch '^https://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?$') {
    throw 'Expected credential-free HTTPS github.com origin; inspect remote without printing secrets'
}
$repo = "$($Matches[1])/$($Matches[2])"
$owner = $Matches[1]
$headers = @{Accept='application/vnd.github+json'; 'User-Agent'='SongRecord-workflow'; 'X-GitHub-Api-Version'='2022-11-28'}
$oldPrompt = $env:GIT_TERMINAL_PROMPT
$oldInteractive = $env:GCM_INTERACTIVE
try {
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE = 'Never'
    if (-not $Account) {
        $accounts = @(& git credential-manager github list 2>$null)
        if ($accounts -contains $owner) { $Account = $owner }
        elseif ($accounts.Count -eq 1 -and $accounts[0] -match '^[a-zA-Z0-9-]+$') { $Account = $accounts[0] }
        else { throw 'Multiple/no GitHub accounts; specify -Account using an existing authenticated account' }
    }
    $credential = "protocol=https`nhost=github.com`nusername=$Account`n`n" | & git @gitArgs credential fill 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub login unavailable; authenticate Git Credential Manager and retry' }
    $password = ($credential | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
    if (-not $password) { throw 'GitHub credential unavailable' }
    $headers.Authorization = 'Bearer ' + $password
    function Read-Api($Path) {
        try { Invoke-RestMethod -Uri (('https://api.github.com/repos/'+$repo+'/'+$Path).TrimEnd('/')) -Headers $headers -TimeoutSec 30 }
        catch {
            $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'network' }
            # Classify only a known public error; never echo arbitrary response bodies.
            if ($code -eq 403 -and $_.ErrorDetails.Message -match 'Upgrade to GitHub Pro or make this repository public to enable this feature') {
                throw "GitHub read failed: HTTP 403 ($Path); PRIVATE_REPOSITORY_PLAN_RESTRICTION; protection state remains unverified"
            }
            throw "GitHub read failed: HTTP $code ($Path); credentials suppressed"
        }
    }
    function Read-Collection($Path, $Property) {
        $items = [System.Collections.Generic.List[object]]::new()
        $separator = if ($Path.Contains('?')) {'&'} else {'?'}
        for ($page=1; $page -le 100; $page++) {
            $data = Read-Api "$Path${separator}per_page=100&page=$page"
            $batch = @($data.$Property)
            foreach ($item in $batch) { $items.Add($item) }
            if ($items.Count -ge $data.total_count) {
                if ($items.Count -ne $data.total_count) { throw 'GitHub pagination changed during query; retry snapshot' }
                return $items.ToArray()
            }
            if (-not $batch.Count) { throw 'Incomplete GitHub pagination; verification pending' }
        }
        throw 'GitHub pagination limit reached; verification pending'
    }
    $info = Read-Api ''
    $policy = [ordered]@{status='NOT_REQUESTED'}
    $policyPending = $false
    if ($InspectPolicy) {
        $policy = [ordered]@{}
        foreach ($path in @("branches/$($info.default_branch)/protection", "rules/branches/$($info.default_branch)")) {
            try { $policy[$path] = Read-Api $path } catch { $policy[$path] = 'UNVERIFIED: ' + $_.Exception.Message; $policyPending = $true }
        }
    }
    $expected = @(
        @{path='.github/workflows/ci.yml'; name='CI'; jobs=@('Flutter analyze, test, and Android build','Spring Boot build and test','MySQL migrations and constraints')},
        @{path='.github/workflows/api-contract.yml'; name='API contract'; jobs=@('contract')},
        @{path='.github/workflows/idempotency-mysql.yml'; name='Idempotency MySQL'; jobs=@('mysql')},
        @{path='.github/workflows/development-workflow.yml'; name='Development workflow'; jobs=@('Source index and automation checks')}
    )
    $runs = @(Read-Collection "actions/runs?head_sha=$Commit" 'workflow_runs' | Where-Object { $_.head_sha -eq $Commit -and $_.event -in @('push','pull_request','workflow_dispatch') })
    & git @gitArgs cat-file -e "${Commit}:tools/ci-policy.json" 2>$null
    $scopedPolicy=($LASTEXITCODE -eq 0)
    $scopeMode='legacy-all'
    if($scopedPolicy) {
        $targetPolicy=(& git @gitArgs show "${Commit}:tools/ci-policy.json") -join "`n"
        $localPolicy=(Get-Content (Join-Path $PSScriptRoot 'ci-policy.json') -Raw).Replace("`r`n","`n").Trim()
        if($LASTEXITCODE -ne 0 -or $targetPolicy.Replace("`r`n","`n").Trim() -cne $localPolicy) { throw 'Target CI policy differs; use matching checkout' }
        if($BaseCommit) {
            $changed=@(Get-CiChangedPaths $root $BaseCommit $Commit)
            $expected=@(Get-CiScope $changed)
            $scopeMode='explicit-push-range'
        } else {
            $expected=@(Get-CiScope @() $true)
            $scopeMode='unknown-range-all'
        }
    }
    $checks = foreach ($workflow in $expected) {
        $run = Get-LatestCiRun $runs $Commit $workflow.path
        # Manual dispatch means full validation even when the changed paths are exempt.
        if($scopedPolicy -and $run.event -eq 'workflow_dispatch') {
            $workflow=@(Get-CiScope @() $true) | Where-Object path -eq $workflow.path
        }
        if($scopedPolicy -and -not $workflow.required -and -not $run) {
            [pscustomobject]@{workflow=$workflow.name;path=$workflow.path;status='NOT_APPLICABLE';run_id=$null;conclusion=$null;url=$null;jobs=@();required_jobs=@()}
            continue
        }
        $jobs = @()
        if ($run -and $run.status -eq 'completed' -and $run.conclusion -eq 'success') {
            $jobs = @(Read-Collection "actions/runs/$($run.id)/attempts/$($run.run_attempt)/jobs" 'jobs')
        }
        $state = Get-CiState $run $jobs $workflow.jobs -AllowUnrequiredSkipped:$scopedPolicy
        [pscustomobject]@{workflow=$workflow.name; path=$workflow.path; status=$state; run_id=$run.id; conclusion=$run.conclusion; url=$run.html_url; jobs=@($jobs | Select-Object name,conclusion);required_jobs=@($workflow.jobs)}
    }
    $applicable=@($checks | Where-Object status -ne 'NOT_APPLICABLE')
    $overall = if($scopedPolicy -and -not $applicable.Count -and -not $policyPending){'NOT_REQUIRED'}else{Get-OverallState $applicable $policyPending}
    $report = [ordered]@{schema=3; utc=[DateTime]::UtcNow.ToString('o'); repository=$repo; commit=$Commit; base_commit=$BaseCommit; scope_mode=$scopeMode; overall=$overall; gate_scope='repository workflow contract; not proof of server branch requirements'; policy=$policy; checks=@($checks)}
    $outDir = Join-Path $root '.local/workflow'
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $report | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $outDir "ci-$Commit.json") -Encoding utf8
    $checks | Format-Table workflow,status,run_id,conclusion,url -AutoSize
    Write-Host "Overall=$overall; requested policy check unresolved=$policyPending"
    if ($overall -eq 'FAIL') { exit 1 }
    if ($overall -eq 'PENDING') { exit 2 }
    exit 0
} finally {
    $headers.Clear(); $credential=$null; $password=$null
    $env:GIT_TERMINAL_PROMPT=$oldPrompt; $env:GCM_INTERACTIVE=$oldInteractive
}
