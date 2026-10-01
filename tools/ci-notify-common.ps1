function Get-CiNotificationResult($Report, [string]$Commit) {
    if ($Report.commit -cne $Commit) { throw 'CI report commit mismatch' }
    $paths = @('.github/workflows/ci.yml', '.github/workflows/api-contract.yml',
        '.github/workflows/idempotency-mysql.yml', '.github/workflows/development-workflow.yml')
    if (@($Report.checks).Count -ne $paths.Count) { throw 'Incomplete CI report' }
    foreach ($path in $paths) {
        $rows = @($Report.checks | Where-Object path -eq $path)
        if ($rows.Count -ne 1 -or $rows[0].status -notin @('PASS','FAIL','PENDING')) {
            throw 'Invalid CI report'
        }
    }
    if (@($Report.checks | Where-Object status -eq 'PENDING').Count) { return 'WAIT' }
    if (@($Report.checks | Where-Object status -eq 'FAIL').Count) { return 'FAIL' }
    return 'PASS'
}

function Get-CiNotificationText([string]$TaskId, [string]$Commit, [string]$Result) {
    $summary = switch ($Result) {
        'PASS' { '필수 CI 모두 성공' }
        'FAIL' { '필수 CI 실패 또는 취소 등 통과하지 못한 결과 발생' }
        'ERROR' { 'CI 조회 오류가 반복되어 감시 중단' }
        'TIMEOUT' { 'CI 확인 제한 시간 도달, 결과 미확인' }
        default { throw 'Invalid notification result' }
    }
    return "$TaskId $($Commit.Substring(0,7)): $summary. 대화에 CI 확인 후 이어서 진행이라고 알려주세요."
}
