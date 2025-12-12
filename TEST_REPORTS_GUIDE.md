# Руководство по отчетам о тестировании

## Быстрый старт

### Запуск тестов с отчетом
```powershell
.\test_runner.ps1
```

Это создаст:
- Текстовый отчет: `test_reports/test_report_YYYY-MM-DD_HH-mm-ss.txt`
- JSON отчет: `test_reports/test_report_YYYY-MM-DD_HH-mm-ss.json`

### Быстрый просмотр результатов
```powershell
.\quick_test.ps1
```

Показывает краткую сводку без сохранения файлов.

## Просмотр отчетов

### Последний отчет
```powershell
.\test_reports\view_report.ps1
```

### Отчет за конкретную дату
```powershell
.\test_reports\view_report.ps1 -Date "2025-01-15"
```

### Сводка за период
```powershell
# За последние 7 дней
.\test_reports\generate_summary.ps1

# За последние 30 дней
.\test_reports\generate_summary.ps1 -Days 30
```

## Структура JSON отчета

```json
{
  "timestamp": "2025-01-15 14:30:00",
  "date": "2025-01-15",
  "summary": {
    "total": 70,
    "passed": 61,
    "failed": 9,
    "success_rate": 87.14
  },
  "failed_tests": [
    "DatabaseService Tests Очистка истории чата",
    "SoundService Tests SoundService - Singleton паттерн"
  ],
  "full_output": "..."
}
```

## Автоматизация

### Добавление в CI/CD

Создайте файл `.github/workflows/tests.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.0.0'
      - run: flutter pub get
      - run: flutter test
      - name: Upload test results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: test_reports/
```

### Ежедневный запуск

Настройте задачу в Windows Task Scheduler для ежедневного запуска `test_runner.ps1`.

## Анализ трендов

Используйте `generate_summary.ps1` для отслеживания:
- Изменения процента успешных тестов
- Количество проваленных тестов по дням
- Частота запусков тестов

## Решение проблем

### Если тесты не запускаются
1. Проверьте, что Flutter установлен: `flutter --version`
2. Установите зависимости: `flutter pub get`
3. Проверьте синтаксис: `flutter analyze`

### Если отчеты не создаются
1. Убедитесь, что директория `test_reports` существует
2. Проверьте права на запись в директорию
3. Запустите PowerShell от имени администратора




