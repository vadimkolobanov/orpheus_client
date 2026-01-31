---
alwaysApply: true
---

# MCP серверы Orpheus

## Доступные серверы и когда их использовать:

### GitHub (`mcp_github_*`)
- Коммиты, PR, issues
- Пример: `mcp_github_push_files`, `mcp_github_list_commits`

### Telegram (`mcp_telegram_*`)
- Отправка уведомлений в Telegram
- Пример: `mcp_telegram_send_markdown_message_as_telegram_bot`

### PostgreSQL (`mcp_postgres-orpheus_*`)
- Запросы к базе данных Orpheus
- Пример: `mcp_postgres-orpheus_execute_query`

### SSH серверы
- `mcp_ssh-turn_*` — TURN сервер
- `mcp_ssh-monitoring_*` — мониторинг

### Sentry (`mcp_sentry_*`)
- Ошибки и issues в продакшене
- Пример: `mcp_sentry_get_issue_details`

### Timeweb (`mcp_timeweb-mcp-server_*`)
- Деплой приложений
- Пример: `mcp_timeweb-mcp-server_create_timeweb_app`

### Browser (`mcp_cursor-ide-browser_*`)
- Тестирование веб-интерфейсов
- Пример: `mcp_cursor-ide-browser_browser_navigate`

## Автоматическое использование:
- При работе с git → используй GitHub MCP
- При деплое → используй Timeweb MCP
- При анализе ошибок → используй Sentry MCP
