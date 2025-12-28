# Structured test report
# Usage: .\test_reporter.ps1 [-Full]

param(
    [switch]$Full = $false
)

Write-Host "`n=== RUNNING TESTS ===" -ForegroundColor Cyan
$startTime = Get-Date

$testOutput = flutter test --no-pub --reporter compact 2>&1 | Out-String

$endTime = Get-Date
$duration = ($endTime - $startTime).TotalSeconds

$passedMatch = [regex]::Match($testOutput, '(\d+)\s+passed')
$failedMatch = [regex]::Match($testOutput, '(\d+)\s+failed')
$passed = if ($passedMatch.Success) { [int]$passedMatch.Groups[1].Value } else { 0 }
$failed = if ($failedMatch.Success) { [int]$failedMatch.Groups[1].Value } else { 0 }
$total = $passed + $failed

$categories = @{
    "CALLS" = @("webrtc", "call", "background_call", "call_state", "incoming_call", "call_session")
    "CHAT" = @("chat", "message", "database", "chat_session")
    "SECURITY" = @("auth", "security", "panic", "wipe", "lock", "pin")
    "NOTIFICATIONS" = @("notification")
    "NETWORK" = @("websocket", "presence")
    "UI" = @("widget", "screen")
    "MODELS" = @("model", "config", "crypto")
    "SERVICES" = @("service", "update", "release", "device", "debug", "sound")
}

$categoryNames = @{
    "CALLS" = "ZVONKI"
    "CHAT" = "CHAT"
    "SECURITY" = "BEZOPASNOST"
    "NOTIFICATIONS" = "UVEDOMLENIYA"
    "NETWORK" = "SET"
    "UI" = "UI"
    "MODELS" = "MODELLI"
    "SERVICES" = "SERVISY"
}

$testLines = $testOutput -split "`n" | Where-Object { 
    $_ -match '^\d+:\d+\s+\+(\d+)\s+-(\d+):\s+(.+?):\s+(.+?)(\s+\[E\])?$' 
}

$testResults = @()
foreach ($line in $testLines) {
    if ($line -match '^\d+:\d+\s+\+(\d+)\s+-(\d+):\s+(.+?):\s+(.+?)(\s+\[E\])?$') {
        $file = $matches[3]
        $testName = $matches[4]
        $isFailed = $matches[5] -eq " [E]"
        
        $category = "OTHER"
        if ($testName -match '^(ZVONKI|CHAT|BEZOPASNOST|UVEDOMLENIYA|SET|UI|MODELLI|SERVISY):') {
            $category = $matches[1]
        } else {
            $fileLower = $file.ToLower()
            foreach ($cat in $categories.Keys) {
                if ($categories[$cat] | Where-Object { $fileLower -match $_ }) {
                    $category = $cat
                    break
                }
            }
        }
        
        $testResults += @{
            Category = $category
            File = $file
            Test = $testName
            Passed = -not $isFailed
        }
    }
}

$grouped = $testResults | Group-Object -Property Category

Write-Host "`n=== RESULTS BY CATEGORY ===" -ForegroundColor Green
Write-Host ""

foreach ($group in $grouped | Sort-Object Name) {
    $catKey = $group.Name
    $catDisplayName = if ($categoryNames.ContainsKey($catKey)) { $categoryNames[$catKey] } else { $catKey }
    $tests = $group.Group
    $catPassed = ($tests | Where-Object { $_.Passed }).Count
    $catFailed = ($tests | Where-Object { -not $_.Passed }).Count
    $catTotal = $tests.Count
    
    $color = if ($catFailed -eq 0) { "Green" } else { "Red" }
    $status = if ($catFailed -eq 0) { "[OK]" } else { "[FAIL]" }
    Write-Host "$status $catDisplayName : $catPassed/$catTotal passed" -ForegroundColor $color
    
    if ($Full -or $catFailed -gt 0) {
        foreach ($test in $tests) {
            $status = if ($test.Passed) { "  [OK]" } else { "  [FAIL]" }
            $statusColor = if ($test.Passed) { "Green" } else { "Red" }
            Write-Host "$status " -NoNewline -ForegroundColor $statusColor
            $displayName = $test.Test -replace '^(ZVONKI|CHAT|BEZOPASNOST|UVEDOMLENIYA|SET|UI|MODELLI|SERVISY):\s*', ''
            Write-Host $displayName
        }
    }
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total tests: $total" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "Duration: $([math]::Round($duration, 2)) sec" -ForegroundColor White

if ($failed -gt 0) {
    Write-Host "`n=== FAILED TESTS ===" -ForegroundColor Red
    $failedTests = $testResults | Where-Object { -not $_.Passed }
    foreach ($test in $failedTests) {
        $catDisplayName = if ($categoryNames.ContainsKey($test.Category)) { $categoryNames[$test.Category] } else { $test.Category }
        $displayName = $test.Test -replace '^(ZVONKI|CHAT|BEZOPASNOST|UVEDOMLENIYA|SET|UI|MODELLI|SERVISY):\s*', ''
        Write-Host "  [FAIL] $catDisplayName : $displayName" -ForegroundColor Red
    }
}

Write-Host ""
