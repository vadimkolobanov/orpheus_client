# Скрипт для запуска тестов и генерации отчета
# Использование: .\test_runner.ps1

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportFile = "test_reports/test_report_$timestamp.txt"
$jsonReportFile = "test_reports/test_report_$timestamp.json"

# Создаем директорию для отчетов
if (-not (Test-Path "test_reports")) {
    New-Item -ItemType Directory -Path "test_reports" | Out-Null
}

Write-Host "Запуск тестов Flutter..." -ForegroundColor Cyan
Write-Host "Отчет будет сохранен в: $reportFile" -ForegroundColor Yellow
Write-Host ""

# Запускаем тесты и сохраняем вывод
$testOutput = flutter test --no-pub 2>&1 | Out-String

# Сохраняем полный вывод
$testOutput | Out-File -FilePath $reportFile -Encoding UTF8

# Парсим результаты
$passedMatch = [regex]::Match($testOutput, '(\d+)\s+passed')
$failedMatch = [regex]::Match($testOutput, '(\d+)\s+failed')
$passed = if ($passedMatch.Success) { [int]$passedMatch.Groups[1].Value } else { 0 }
$failed = if ($failedMatch.Success) { [int]$failedMatch.Groups[1].Value } else { 0 }
$total = $passed + $failed

# Извлекаем информацию о неудачных тестах
$failedTests = @()
$failedTestDetails = @()
$lines = $testOutput -split "`n"

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    
    # Ищем строки с [E] - это проваленные тесты
    # Формат: "00:02 +49 -9: D:/path/test.dart: Group Name Test Name [E]"
    if ($line -match '\[E\]') {
        # Извлекаем имя теста
        if ($line -match ':\s*([^:]+?)\s*\[E\]') {
            $testName = $matches[1].Trim()
            $failedTests += $testName
            
            # Ищем описание ошибки в следующих строках
            $errorDetails = @()
            for ($j = $i + 1; $j -lt [Math]::Min($i + 5, $lines.Count); $j++) {
                $nextLine = $lines[$j]
                if ($nextLine -match '^\s+[A-Z]' -or $nextLine -match 'Exception|Error|Failed') {
                    $errorDetails += $nextLine.Trim()
                }
                if ($nextLine -match '^\d+:\d+' -and $nextLine -notmatch '\[E\]') {
                    break
                }
            }
            if ($errorDetails.Count -gt 0) {
                $failedTestDetails += @{
                    test = $testName
                    error = $errorDetails[0]
                }
            }
        }
    }
}

# Создаем JSON отчет
$jsonReport = @{
    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    date = Get-Date -Format "yyyy-MM-dd"
    summary = @{
        total = $total
        passed = $passed
        failed = $failed
        success_rate = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 2) } else { 0 }
    }
    failed_tests = $failedTests
    failed_test_details = $failedTestDetails
    full_output = $testOutput
} | ConvertTo-Json -Depth 10

$jsonReport | Out-File -FilePath $jsonReportFile -Encoding UTF8

# Выводим краткую сводку
Write-Host "=== РЕЗУЛЬТАТЫ ТЕСТОВ ===" -ForegroundColor Green
Write-Host "Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "Всего тестов: $total" -ForegroundColor White
Write-Host "Успешно: $passed" -ForegroundColor Green
Write-Host "Провалено: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Полный отчет: $reportFile" -ForegroundColor Yellow
Write-Host "JSON отчет: $jsonReportFile" -ForegroundColor Yellow

# Выводим список проваленных тестов
if ($failed -gt 0) {
    Write-Host "`n=== ПРОВАЛЕННЫЕ ТЕСТЫ ($failed) ===" -ForegroundColor Red
    $testNum = 1
    foreach ($testDetail in $failedTestDetails) {
        Write-Host "`n$testNum. $($testDetail.test)" -ForegroundColor Red
        if ($testDetail.error) {
            Write-Host "   Ошибка: $($testDetail.error)" -ForegroundColor Yellow
        }
        $testNum++
    }
    
    # Если не удалось извлечь детали, показываем все строки с [E]
    if ($failedTestDetails.Count -eq 0) {
        $failedLines = $testOutput -split "`n" | Where-Object { $_ -match '\[E\]' }
        foreach ($line in $failedLines) {
            Write-Host $line.Trim() -ForegroundColor Red
        }
    }
}

