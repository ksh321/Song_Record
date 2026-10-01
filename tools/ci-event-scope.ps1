#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci-scope.ps1')
$event=Get-Content $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$root=Split-Path $PSScriptRoot -Parent
$full=$true
$paths=@()
try {
    if($env:GITHUB_EVENT_NAME -eq 'push') {
        $paths=@(Get-CiChangedPaths $root $event.before $event.after);$full=$false
    } elseif($env:GITHUB_EVENT_NAME -eq 'pull_request') {
        $head=$event.pull_request.head.sha
        $base=& git merge-base $event.pull_request.base.sha $head
        if($LASTEXITCODE){throw 'Merge base unavailable'}
        $paths=@(Get-CiChangedPaths $root $base $head);$full=$false
    }
} catch { Write-Host 'Changed range unavailable: all CI jobs required.' }
$scope=@(Get-CiScope $paths $full)
$jobs=@(($scope | Where-Object name -eq 'CI').jobs)
$policy=Get-Content (Join-Path $PSScriptRoot 'ci-policy.json') -Raw | ConvertFrom-Json
foreach($job in ($policy.workflows | Where-Object name -eq 'CI').jobs) {
    "$($job.key)=$($job.name -in $jobs)".ToLowerInvariant() | Add-Content $env:GITHUB_OUTPUT -Encoding utf8
}
