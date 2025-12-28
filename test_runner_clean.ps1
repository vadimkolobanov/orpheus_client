# Clean test report grouped by functional areas
# Usage: .\test_runner_clean.ps1

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportFile = "test_reports/clean_report_$timestamp.txt"

if (-not (Test-Path "test_reports")) {
    New-Item -ItemType Directory -Path "test_reports" | Out-Null
}

Write-Host "Running Flutter tests..." -ForegroundColor Cyan
Write-Host ""

# Run tests
$fullOutput = flutter test --no-pub 2>&1 | Out-String

# Parse results
$passedMatch = [regex]::Match($fullOutput, '(\d+)\s+passed')
$failedMatch = [regex]::Match($fullOutput, '(\d+)\s+failed')
$passed = if ($passedMatch.Success) { [int]$passedMatch.Groups[1].Value } else { 0 }
$failed = if ($failedMatch.Success) { [int]$failedMatch.Groups[1].Value } else { 0 }
$total = $passed + $failed

# Category mapping
$categoryMap = @{
    'ZVONKI' = @('webrtc', 'call', 'CallScreen', 'CallSession', 'BackgroundCall', 'IncomingCall', 'WebRTC', 'ICE', 'TURN', 'signaling', 'hang-up')
    'CHAT' = @('chat', 'ChatScreen', 'ChatSession', 'message', 'Message', 'chat_time', 'day-separator')
    'SECURITY' = @('auth', 'AuthService', 'PIN', 'duress', 'wipe', 'lockout', 'SecurityConfig', 'PanicWipe', 'LockScreen', 'PinSetup', 'SecuritySettings')
    'NOTIFICATIONS' = @('notification', 'NotificationService', 'FCM', 'push', 'local notification')
    'CONTACTS' = @('contact', 'Contact', 'ContactsScreen', 'QR', 'qr_scan')
    'DATABASE' = @('database', 'DatabaseService', 'Database', 'CRUD')
    'CRYPTO' = @('crypto', 'CryptoService', 'encrypt', 'decrypt')
    'NETWORK' = @('websocket', 'WebSocket', 'presence', 'connection')
    'UI' = @('widget', 'screen', 'SettingsScreen', 'StatusScreen', 'UpdatesScreen', 'LicenseScreen', 'HelpScreen', 'DebugLogs', 'WelcomeScreen')
    'SERVICES' = @('service', 'Service', 'UpdateService', 'ReleaseNotes', 'DeviceSettings', 'DebugLogger', 'SoundService', 'PendingActions')
    'MODELS' = @('model', 'Model', 'ChatMessage', 'Contact', 'SecurityConfig')
    'PROTOCOL' = @('protocol', 'call_protocol', 'signaling', 'JSON')
}

# Category display names
$categoryNames = @{
    'ZVONKI' = 'ZVONKI'
    'CHAT' = 'CHAT'
    'SECURITY' = 'SECURITY'
    'NOTIFICATIONS' = 'NOTIFICATIONS'
    'CONTACTS' = 'CONTACTS'
    'DATABASE' = 'DATABASE'
    'CRYPTO' = 'CRYPTO'
    'NETWORK' = 'NETWORK'
    'UI' = 'UI'
    'SERVICES' = 'SERVICES'
    'MODELS' = 'MODELS'
    'PROTOCOL' = 'PROTOCOL'
}

# Parse test lines - ищем строки с результатами тестов
$testLines = $fullOutput -split "`n" | Where-Object { 
    $_ -match '^\d+:\d+\s+\+[\d-]+\s*[+-]\d+:' -or $_ -match '^\d+:\d+\s+\+[\d-]+\s*-\d+:' 
}

$categories = @{}
$failedTests = @()

foreach ($line in $testLines) {
    if ($line -match '\[E\]') {
        if ($line -match ':\s*([^:]+?)\s*\[E\]') {
            $testName = $matches[1].Trim()
            $failedTests += $testName
        }
    } elseif ($line -match '^\d+:\d+\s+\+[\d-]+\s*[+-]\d+:\s*(.+)$') {
        $testPath = $matches[1].Trim()
        
        $category = 'OTHER'
        foreach ($cat in $categoryMap.Keys) {
            $keywords = $categoryMap[$cat]
            foreach ($keyword in $keywords) {
                if ($testPath -match $keyword -or $testPath -match [regex]::Escape($keyword)) {
                    $category = $cat
                    break
                }
            }
            if ($category -ne 'OTHER') { break }
        }
        
        if (-not $categories.ContainsKey($category)) {
            $categories[$category] = @()
        }
        
        $testName = $testPath
        if ($testPath -match ':\s*(.+)$') {
            $testName = $matches[1].Trim()
        }
        
        $categories[$category] += $testName
    }
}

# Build report
$report = @"
================================================================================
                    ORPHEUS CLIENT TEST REPORT
================================================================================

Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Total: $total
Passed: $passed
Failed: $failed
Success Rate: $(if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 })%

"@

# Output by category
foreach ($cat in ($categories.Keys | Sort-Object)) {
    $tests = $categories[$cat]
    $count = $tests.Count
    $displayName = if ($categoryNames.ContainsKey($cat)) { $categoryNames[$cat] } else { $cat }
    
    $report += "`n--------------------------------------------------------------------------------`n"
    $report += "$displayName ($count tests)`n"
    $report += "--------------------------------------------------------------------------------`n"
    
    foreach ($test in $tests) {
        $cleanName = $test
        if ($cleanName -match ':\s*(.+)$') {
            $cleanName = $matches[1]
        }
        $cleanName = $cleanName -replace '\(.+\)', ''
        $cleanName = $cleanName -replace '\btest\b', ''
        $cleanName = $cleanName.Trim()
        
        if ($cleanName.Length -gt 0) {
            $report += "  [OK] $cleanName`n"
        }
    }
}

# Failed tests
if ($failedTests.Count -gt 0) {
    $report += "`n--------------------------------------------------------------------------------`n"
    $report += "FAILED TESTS ($($failedTests.Count))`n"
    $report += "--------------------------------------------------------------------------------`n"
    foreach ($test in $failedTests) {
        $cleanName = $test -replace ':\s*(.+)$', '$1'
        $report += "  [FAIL] $cleanName`n"
    }
}

$report | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host $report
Write-Host "`nReport saved: $reportFile" -ForegroundColor Yellow
