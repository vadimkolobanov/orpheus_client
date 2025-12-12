# Orpheus Server (Backend)

## Быстрый старт

### Предусловия
- Python 3.10+
- Установлен `pip`

### Установка
```bash
python -m venv .venv
.\.venv\Scripts\activate           # Windows
pip install -r requirements.txt
```

### Запуск (локально)
```bash
uvicorn main:app --reload --port 8000
```

### Быстрая проверка
```bash
curl http://localhost:8000/docs
```
Откроется Swagger UI (проверка, что сервер поднялся).

### Тесты
Тестов в репозитории нет. Если добавите — опишите команды здесь.

## Процесс изменений (обязательно)
- Обновить `CHANGELOG.md` (секция Unreleased)
- Добавить запись в `AI_WORKLOG.md`
- При необходимости обновить `docs/*`
- Перед коммитом: `git status` убедиться, что changelog/worklog в коммите

## Hooks
## Отчёты
- `docs/REPORT_SINCE_2025-12-06.md` — сводка изменений с версии 0.9.0 (с 06.12.2025).
Включить локально (требует git):
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```


