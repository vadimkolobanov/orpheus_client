# Быстрый запуск тестов с кратким отчетом
# Использование: .\quick_test.ps1

Write-Host "Запуск тестов..." -ForegroundColor Cyan

# Запускаем тесты и перехватываем вывод
$process = Start-Process -FilePath "flutter" -ArgumentList "test", "--no-pub" -NoNewWindow -Wait -PassThru -RedirectStandardOutput "test_output.tmp" -RedirectStandardError "test_error.tmp"

$output = Get-Content "test_output.tmp" -Raw -ErrorAction SilentlyContinue
$error = Get-Content "test_error.tmp" -Raw -ErrorAction SilentlyContinue
$fullOutput = $output + $error

# Удаляем временные файлы
Remove-Item "test_output.tmp" -ErrorAction SilentlyContinue
Remove-Item "test_error.tmp" -ErrorAction SilentlyContinue

# Парсим результаты
$passedMatch = [regex]::Match($fullOutput, "(\d+)\s+passed")
$failedMatch = [regex]::Match($fullOutput, "(\d+)\s+failed")
$passed = if ($passedMatch.Success) { [int]$passedMatch.Groups[1].Value } else { 0 }
$failed = if ($failedMatch.Success) { [int]$failedMatch.Groups[1].Value } else { 0 }
$total = $passed + $failed

Write-Host "`n=== РЕЗУЛЬТАТЫ ===" -ForegroundColor Green
Write-Host "Всего: $total | Успешно: $passed | Провалено: $failed" -ForegroundColor White

if ($failed -gt 0) {
    Write-Host "`n=== ПРОВАЛЕННЫЕ ТЕСТЫ ===" -ForegroundColor Red
    
    # Извлекаем имена проваленных тестов
    $lines = $fullOutput -split "`n"
    foreach ($line in $lines) {
        if ($line -match "\[E\]" -and $line -match ":\s*(.+?)\s*\[E\]") {
            $testName = $matches[1].Trim()
            Write-Host "  ❌ $testName" -ForegroundColor Red
        }
    }
    
    Write-Host "`nДля подробностей запустите: .\test_runner.ps1" -ForegroundColor Yellow
} else {
    Write-Host "`n✅ Все тесты прошли успешно!" -ForegroundColor Green
}







