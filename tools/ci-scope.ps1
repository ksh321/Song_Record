function Test-CiGlob([string]$Path, [string]$Pattern) {
    $regex=[regex]::Escape($Pattern).Replace('\*\*','.*').Replace('\*','[^/]*')
    return $Path -cmatch ('^'+$regex+'$')
}
function Test-CiRule($Paths, $Rule, $Always) {
    foreach($path in $Paths) {
        foreach($pattern in @($Always)+@($Rule.include)) { if(Test-CiGlob $path $pattern){return $true} }
        $excluded=$false
        foreach($pattern in $Rule.exclude) { if(Test-CiGlob $path $pattern){$excluded=$true;break} }
        if(-not $excluded){return $true}
    }
    return $false
}
function Get-CiScope($Paths, [bool]$Full=$false) {
    $policy=Get-Content (Join-Path $PSScriptRoot 'ci-policy.json') -Raw | ConvertFrom-Json
    foreach($workflow in $policy.workflows) {
        $required=$Full -or (Test-CiRule $Paths $workflow $policy.always)
        $jobs=@(foreach($job in $workflow.jobs) {
            if($required -and ($Full -or -not $job.key -or (Test-CiRule $Paths $job $policy.always))){$job.name}
        })
        if($workflow.name -eq 'CI' -and $required){$jobs=@('Scope changed files')+$jobs}
        [pscustomobject]@{path=$workflow.path;name=$workflow.name;required=$required;jobs=$jobs}
    }
}
function Get-CiChangedPaths([string]$Root,[string]$Base,[string]$Head) {
    if($Base -cnotmatch '^[0-9a-f]{40}$' -or $Head -cnotmatch '^[0-9a-f]{40}$' -or $Base -eq $Head){throw 'Invalid CI range'}
    $args=@('-c',"safe.directory=$($Root.Replace('\','/'))",'-C',$Root)
    & git @args merge-base --is-ancestor $Base $Head
    if($LASTEXITCODE){throw 'CI base is not an available ancestor'}
    $paths=@(& git @args -c core.quotePath=false diff --name-only --no-renames $Base $Head)
    if($LASTEXITCODE){throw 'Cannot inspect CI range'}
    return $paths
}
