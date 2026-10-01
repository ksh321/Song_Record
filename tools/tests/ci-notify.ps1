#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../ci-notify-common.ps1')
$sha='a'*40
$paths=@('.github/workflows/ci.yml','.github/workflows/api-contract.yml',
    '.github/workflows/idempotency-mysql.yml','.github/workflows/development-workflow.yml')
function Report($states) {
    $checks=for($i=0;$i -lt 4;$i++){[pscustomobject]@{path=$paths[$i];status=$states[$i]}}
    return [pscustomobject]@{commit=$sha;checks=@($checks)}
}
function Equal($actual,$expected) { if($actual -cne $expected){throw "Expected $expected, got $actual"} }
function Reject($action) { $rejected=$false;try{& $action | Out-Null}catch{$rejected=$true};if(-not $rejected){throw 'Expected rejection'} }
Equal (Get-CiNotificationResult (Report @('PASS','PASS','PASS','PASS')) $sha) 'PASS'
Equal (Get-CiNotificationResult (Report @('FAIL','PASS','PASS','PASS')) $sha) 'FAIL'
Equal (Get-CiNotificationResult (Report @('FAIL','PENDING','PASS','PASS')) $sha) 'WAIT'
Equal (Get-CiNotificationResult (Report @('PENDING','PASS','PASS','PASS')) $sha) 'WAIT'
Reject {Get-CiNotificationResult (Report @('PASS','PASS','PASS','PASS')) ('b'*40)}
Reject {$r=Report @('PASS','PASS','PASS','PASS');$r.checks=$r.checks[0..2];Get-CiNotificationResult $r $sha}
Reject {$r=Report @('PASS','PASS','PASS','PASS');$r.checks[3].path=$paths[0];Get-CiNotificationResult $r $sha}
Reject {Get-CiNotificationResult (Report @('SKIPPED','PASS','PASS','PASS')) $sha}
foreach($result in @('PASS','FAIL','ERROR','TIMEOUT')) {
    $message=Get-CiNotificationText 'P10-02' $sha $result
    if($message -notmatch '^P10-02 aaaaaaa:' -or $message -match 'https?://'){throw 'Unsafe/unidentified message'}
}
Write-Host 'CI notification decisions: 12 PASS (no network sends).'
