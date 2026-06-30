# Oracle 2.0 — AI-сотрудник Orpheus

## Полная спецификация проекта

Дата: 2026-02-25
Статус: Проектирование

---

## 1. Видение

Oracle of Orpheus перестаёт быть чат-ботом, отвечающим на вопросы по документации. Он становится полноценным AI-сотрудником компании, который работает 24/7, имеет доступ к реальным данным проекта, принимает решения, действует проактивно и помогает как пользователям, так и администратору.

Для пользователя Oracle — это личный помощник внутри мессенджера, который помнит контекст, помогает формулировать сообщения, подводит итоги пропущенных чатов, принимает обратную связь и управляет заметками.

Для администратора Oracle — это операционный директор, аналитик, тестировщик и служба поддержки в одном лице. Он сам находит баги, собирает метрики, планирует релизы, пишет changelog и отправляет уведомления.

---

## 2. Текущее состояние

### Что есть сейчас

Oracle реализован как тонкий proxy. Мобильный клиент и сайт отправляют текстовое сообщение на бэкенд (POST /api/public/ai/call), бэкенд пересылает его в Timeweb Cloud AI RAG Agent, получает ответ и возвращает клиенту. Вся "интеллектуальная" работа происходит на стороне Timeweb — бэкенд Orpheus не обрабатывает содержимое запросов и ответов.

### Компоненты текущей реализации

**Бэкенд** (d:\Programs\orpheus\app\public_api.py, строки 244-291):
- Endpoint POST /api/public/ai/call принимает JSON с полями message и parent_message_id
- Проксирует запрос на https://agent.timeweb.cloud/api/v1/cloud-ai/agents/{ACCESS_ID}/call
- Передаёт Authorization: Bearer {TIMEWEB_AI_TOKEN} и x-proxy-source: orpheus.click
- Timeout 60 секунд, возвращает сырой JSON от Timeweb
- Конфигурация в main.py строки 123-126: TIMEWEB_AI_ACCESS_ID, TIMEWEB_AI_TOKEN

**Мобильный клиент** (d:\orpheus_client\lib\services\ai_assistant_service.dart):
- Singleton AiAssistantService, инъекция http.Client для тестов
- Метод sendMessage() отправляет POST, парсит ответ (пробует поля answer, message, response, result, content)
- Сохраняет parent_message_id для контекста диалога (таблица ai_context в SQLite)
- История ограничена 20 сообщениями AI (константа assistantMemoryLimit)
- Таблица ai_messages: id, role, content, created_at, is_error

**UI чата** (d:\orpheus_client\lib\screens\ai_assistant_chat_screen.dart):
- Welcome-экран с 4 suggestion-чипсами
- Сообщения с поддержкой Markdown (flutter_markdown)
- Индикатор "думает" — анимированные 3 точки
- Long-press на сообщение AI — сохранить в Notes Vault (sourceType: 'oracle')
- Очистка чата через кнопку в AppBar

**Контакты** (d:\orpheus_client\lib\contacts_screen.dart, строки 834-1032):
- Oracle всегда первый в списке контактов
- Виджет _OracleContactRow с анимацией свечения, градиентом, пульсирующим статусом "Всегда онлайн"

**Сайт** (d:\Orpheus_Site\src\components\AiConsultantEmbed.tsx):
- Компонент с typewriter-эффектом, Markdown, parent_message_id tracking
- Тот же endpoint /api/public/ai/call
- Session ID генерируется локально, не сохраняется между визитами

### Ограничения текущей реализации

- Нет доступа к реальным данным (БД, логи, метрики, платежи)
- Нет tool use / function calling — Oracle не может выполнять действия
- Нет проактивности — только отвечает на вопросы
- Нет долгосрочной памяти — контекст ограничен 20 сообщениями в рамках одной цепочки
- Нет аутентификации на AI endpoint — любой может дёргать
- Нет streaming — ответ приходит целиком после ожидания до 60 секунд
- RAG привязан к статической knowledge base Timeweb, обновляется вручную

---

## 3. Архитектура Oracle 2.0

### Принцип работы

Oracle 2.0 — это агентный сервис с tool use. Когда пользователь или админ отправляет сообщение, Oracle получает его вместе с набором доступных инструментов (функций). LLM сам решает, какие инструменты вызвать, анализирует результаты и формирует ответ. Это тот же паттерн, по которому работают Claude Code, ChatGPT с plugins, Cursor — LLM + tools + agentic loop.

### Выбор LLM

Основная модель — DeepSeek V3 (deepseek-chat). Причина: доступен из РФ без VPN, оплачивается российской картой, поддерживает function calling, стоимость ~$0.27/M input + $1.10/M output.

Для сложных аналитических задач — DeepSeek R1 (deepseek-reasoner). Используется когда запрос требует глубокого reasoning: анализ данных, планирование релизов, поиск root cause ошибок.

Архитектура model-agnostic: используется OpenAI-совместимый SDK. Замена провайдера — изменение base_url и api_key в одном конфиге. Завтра появится доступный из РФ провайдер лучше — переключаемся одной строкой.

Компенсация слабостей DeepSeek в tool use:
- Детальные описания каждого инструмента с примерами в description
- Валидация аргументов tool calls перед выполнением — если модель прислала кривые параметры, отправляем ей сообщение об ошибке и даём повторить
- Ограничение максимум 8 tool calls за один agentic loop чтобы не зацикливался
- Retry с переформулировкой при ошибках

### Расположение сервиса

Oracle 2.0 встраивается в существующий бэкенд Orpheus (d:\Programs\orpheus), а не как отдельный микросервис. Причины: единая кодовая база, общий доступ к БД и ctx, проще деплой (Timeweb Apps уже настроен), не нужен межсервисный IPC.

Новый файл app/oracle_api.py содержит роутер с endpoints Oracle. Новая директория app/oracle/ содержит ядро агента, инструменты, scheduler и промпты.

Структура файлов на бэкенде:

```
app/
├── oracle_api.py              — FastAPI роутер (/api/oracle/*)
├── oracle/
│   ├── agent.py               — Ядро агента: agentic loop, model routing
│   ├── tools.py               — Registry + реализация всех инструментов
│   ├── prompts.py             — Системные промпты для каждой роли
│   ├── memory.py              — Система памяти (session + user + global)
│   ├── scheduler.py           — Proactive jobs (APScheduler)
│   └── embeddings.py          — Генерация embeddings для RAG
```

---

## 4. Инструменты Oracle

Oracle имеет набор инструментов (tools), которые он может вызывать для ответа на запросы. Каждый инструмент — это функция на бэкенде, доступная через function calling API DeepSeek.

### 4.1 Аналитика данных

**query_database** — выполнение произвольного read-only SQL запроса к orpheus_db.
- Параметры: query (SELECT-only SQL), explain (зачем нужен запрос, для аудита)
- Валидация: запрос обязан начинаться с SELECT, запрещены INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE
- Timeout: 10 секунд на запрос
- Результат: массив строк в JSON, ограничение 100 строк
- Доступ: только admin

Доступные таблицы PostgreSQL (orpheus_db на 5.129.243.218):
- users (pubkey PK, first_seen, last_seen, has_push_token)
- push_tokens (pubkey PK, fcm_token, updated_at)
- offline_messages (id, recipient_pubkey, sender_pubkey, message_json, created_at)
- rooms (id, name, owner_pubkey, invite_code, is_active, created_at, updated_at)
- room_members (id, room_id, pubkey, role, notifications_enabled, joined_at)
- room_messages (id, room_id, sender_pubkey, sender_name, text, author_type, is_system, created_at)
- licenses (id, pubkey, address, tx_id, amount, created_at)
- payment_sessions (id UUID, pubkey, address, hd_index, expected_amount, currency, status, created_at, expires_at, tx_id)
- donations (id, email, network, wallet_address, expected_amount_usd, actual_amount_usd, tx_id, status, promo_code, created_at)
- promo_codes (code PK, is_used, used_by_pubkey, promo_type, created_at)
- user_badges (id, pubkey, badge_type, granted_at, granted_by)
- app_versions (id, version_code, version_name, download_url, required, public_changelog, internal_notes, created_at)
- logs (id, timestamp, category, pubkey, message, details JSON, created_at)
- telemetry_logs (id, timestamp, source, level, tag, category, pubkey, peer_pubkey, call_id, message, details, device_info, app_version, os, created_at)
- support_messages (id, pubkey, direction, message, is_read, created_at)
- audit_logs (id, admin_username, action, resource_type, resource_id, details, ip_address, created_at)
- client_debug_logs (id, pubkey, log_data, app_version, device_info, created_at)
- admins (id, username, hashed_password, role, is_active, created_at)

**get_user_statistics** — агрегированная статистика пользователей.
- Параметры: period (day / week / month / quarter), metric (registrations / active / messages / calls)
- Реализация: предзаписанные SQL запросы к таблицам users, room_messages, telemetry_logs
- Возвращает: текущее значение, сравнение с предыдущим периодом, процент изменения
- Доступ: только admin

**get_revenue_report** — аналитика платежей и донатов.
- Параметры: period (month / quarter / year)
- Реализация: запросы к donations (status='confirmed'), licenses, payment_sessions (status='confirmed')
- Возвращает: общая сумма, количество транзакций, средний чек, разбивка по сетям
- Доступ: только admin

### 4.2 Мониторинг

**get_server_health** — состояние серверов.
- Параметры: server (main / monitoring / mailer / all)
- Реализация: SSH команды через MCP (ssh-turn для main 213.171.10.108, ssh-monitoring для 5.129.220.96) — uptime, df -h, free -m, проверка процессов
- Возвращает: CPU load, RAM usage, disk usage, uptime, статус ключевых процессов
- Доступ: только admin

**parse_backend_logs** — анализ логов бэкенда.
- Параметры: query (поисковая строка), level (error / warning / info / all), last_n_minutes (число)
- Реализация: SQL запрос к таблицам logs и telemetry_logs с фильтрацией
- Возвращает: список записей лога с timestamp, category, message, details
- Доступ: только admin

**get_api_metrics** — метрики производительности API.
- Параметры: period (1h / 24h / 7d)
- Реализация: агрегация telemetry_logs по tag, подсчёт ошибок, среднее время ответа
- Возвращает: количество запросов, error rate, top-5 медленных endpoints, top-5 частых ошибок
- Доступ: только admin

**check_error_spikes** — мониторинг аномалий в ошибках.
- Параметры: window_minutes (по умолчанию 60)
- Реализация: подсчёт записей с level='error' в telemetry_logs за окно, сравнение с средним
- Возвращает: текущее количество ошибок, среднее за аналогичные периоды, является ли это аномалией
- Доступ: только admin (также используется scheduler)

### 4.3 Задачи и планирование

**create_github_issue** — создание задачи на GitHub.
- Параметры: repo (orpheus_client / orpheus / Orpheus_Site / orpheus_desctop), title, body, labels (массив строк)
- Реализация: GitHub API через токен (уже есть в MCP github)
- Возвращает: URL созданного issue, номер
- Доступ: только admin

**list_github_issues** — список открытых задач.
- Параметры: repo (конкретный или all), state (open / closed / all), labels (фильтр)
- Реализация: GitHub API
- Возвращает: список issues с title, number, labels, assignee, created_at
- Доступ: только admin

**draft_release_plan** — генерация плана релиза.
- Параметры: target_version (строка версии), scope (patch / minor / major)
- Реализация: Oracle собирает данные из list_github_issues (closed за последний период + open), analyze_feedback, и на основе этого формирует структурированный план с приоритетами, рисками и рекомендациями. Это мета-инструмент — Oracle вызывает другие инструменты внутри.
- Возвращает: текстовый план релиза
- Доступ: только admin

**generate_changelog** — генерация changelog из коммитов.
- Параметры: from_version, to_version (или from_commit, to_commit)
- Реализация: git log между версиями, группировка по типу (feat/fix/refactor), перевод на русский для пользователей
- Возвращает: changelog в двух форматах — публичный (русский, для пользователей) и технический (английский, для GitHub)
- Доступ: только admin

### 4.4 Обратная связь

**collect_feedback** — приём обратной связи от пользователя.
- Параметры: text (текст фидбэка), category (bug / feature / ux / performance / other — определяется Oracle автоматически)
- Реализация: Oracle уточняет детали у пользователя в диалоге, затем сохраняет в новую таблицу oracle_feedback в PostgreSQL
- Новая таблица oracle_feedback: id, pubkey (nullable — для анонимных с сайта), text, category, sentiment (positive/negative/neutral — определяет Oracle), source (in_app / website / email), oracle_summary (краткое резюме от Oracle), created_at
- Если похожий фидбэк уже приходил N раз (порог: 5) — Oracle автоматически вызывает create_github_issue
- Доступ: user и visitor

**analyze_feedback** — анализ собранной обратной связи.
- Параметры: period (week / month / all), group_by (category / sentiment / source)
- Реализация: SQL к oracle_feedback с агрегацией + LLM-summary топовых проблем
- Возвращает: количество по категориям, топ-3 проблемы, тренды, рекомендации
- Доступ: только admin

### 4.5 Knowledge Base (RAG)

**search_knowledge** — семантический поиск по документации Orpheus.
- Параметры: query (текст поиска), top_k (количество результатов, по умолчанию 5)
- Реализация: embedding запроса через DeepSeek Embeddings API, cosine similarity поиск в таблице oracle_knowledge (PostgreSQL + pgvector)
- Новая таблица oracle_knowledge: id, title, content, category (faq / docs / troubleshooting / release_notes), embedding (vector(1536)), source_file (откуда взято), updated_at
- Начальное наполнение: все текущие документы из Timeweb RAG knowledge base, FAQ, changelog, описания фич
- Возвращает: список релевантных фрагментов с title, content, relevance score
- Доступ: все роли

**update_knowledge** — добавление или обновление записи в knowledge base.
- Параметры: title, content, category
- Реализация: генерация embedding, upsert в oracle_knowledge
- Доступ: только admin

### 4.6 Действия

**send_telegram_notification** — отправка сообщения в Telegram dev-канал.
- Параметры: message (текст, поддерживает Markdown)
- Реализация: через MCP telegram (mcp__telegram__send_markdown_message_as_telegram_bot)
- Доступ: только admin (и scheduler для автоматических алертов)

**send_push_notification** — отправка push-уведомления пользователю.
- Параметры: target (pubkey конкретного пользователя или "all"), title, body
- Реализация: через существующую функцию send_push_notification из ctx бэкенда
- Для "all": выборка всех pubkey из push_tokens и отправка каждому
- Доступ: только admin

**send_email** — отправка email через Orpheus Mailer Relay.
- Параметры: to (email получателя), subject, body (HTML)
- Реализация: через существующую функцию send_email из ctx (POST на MAILER_RELAY_URL с Bearer MAILER_AUTH_TOKEN)
- Доступ: только admin

**run_health_check** — проактивная проверка работоспособности.
- Параметры: target (api / registration / messaging / all)
- Реализация: реальные HTTP запросы к API endpoints — health check, тестовая регистрация (с удалением), проверка WebSocket connect, замер latency
- Возвращает: статус каждого компонента, время ответа, обнаруженные проблемы
- Доступ: только admin

---

## 5. Система ролей и доступа

### Три роли

**visitor** — неавторизованный пользователь на сайте.
- Доступные инструменты: search_knowledge, collect_feedback
- Идентификация: нет (анонимный)
- Контекст: только текущая сессия, без сохранения между визитами

**user** — авторизованный пользователь мобильного приложения.
- Доступные инструменты: search_knowledge, collect_feedback + персональные функции (описаны в разделе 6)
- Идентификация: по заголовку X-Pubkey (уже используется в бэкенде)
- Контекст: долгосрочная память, история диалогов

**admin** — администратор проекта.
- Доступные инструменты: все без исключения
- Идентификация: по заголовку X-Admin-Token (JWT из admin auth)
- Контекст: полная долгосрочная память, доступ ко всем данным

### Определение роли на бэкенде

Endpoint /api/oracle/chat проверяет заголовки запроса:
1. Если есть X-Admin-Token и он валидный JWT из таблицы admins — роль admin
2. Если есть X-Pubkey и он не пустой — роль user
3. Иначе — роль visitor

---

## 6. Вау-эффекты для пользователей

Это функции, которые делают Oracle незаменимым помощником внутри мессенджера, а не просто FAQ-ботом.

### 6.1 Oracle знает о проблемах раньше пользователя

Когда пользователь открывает чат с Oracle после обновления приложения, Oracle проверяет версию и, если есть известные проблемы с этой версией (из oracle_knowledge или из github issues), сам инициирует сообщение: "Привет! Я заметил, что ты обновился до v1.2.0. В этой версии есть известная особенность с настройками уведомлений — проверь, всё ли работает. Если что, я помогу."

Реализация на клиенте: при открытии AiAssistantChatScreen, если messages пуст или прошло >24 часа с последнего визита, клиент отправляет системное сообщение с app_version и device_info. Oracle на бэкенде проверяет известные проблемы и формирует приветствие.

### 6.2 Долгосрочная память

Oracle помнит все прошлые разговоры с конкретным пользователем. Если месяц назад пользователь спрашивал про дуресс-режим, а сегодня пишет "а как там та штука с безопасностью?" — Oracle понимает контекст.

Реализация: таблица oracle_user_memory в PostgreSQL. Поля: id, pubkey, summary (сжатое резюме прошлых разговоров, обновляется после каждой сессии), topics (массив тем, которые обсуждались), preferences (предпочтения пользователя — язык, стиль общения), updated_at.

После каждой сессии (когда пользователь закрывает чат) Oracle получает команду "обнови память пользователя" — LLM сжимает диалог в краткое summary и обновляет запись. При следующем разговоре это summary включается в системный промпт.

### 6.3 Личный секретарь — напоминания

Пользователь говорит "напомни мне написать Алексу завтра в 10". Oracle подтверждает и создаёт запись в таблице oracle_reminders. Когда наступает время, scheduler отправляет push-уведомление от Oracle: "Ты просил напомнить — написать Алексу."

Новая таблица oracle_reminders: id, pubkey, text (текст напоминания), remind_at (timestamp), is_sent (boolean), created_at.

Scheduler проверяет oracle_reminders каждую минуту, для всех записей где remind_at <= now() и is_sent = false отправляет push через send_push_notification с type "oracle-reminder", помечает is_sent = true.

На клиенте: новый тип FCM сообщения "oracle-reminder" — показывает local notification с иконкой Oracle.

### 6.4 Итоги пропущенных чатов

Пользователь был офлайн. Когда он открывает Oracle, тот может сказать: "Пока тебя не было: 12 сообщений от контакта X, 3 от контакта Y, в комнате 'Работа' обсуждали Z."

Реализация: эта функция работает целиком на клиенте. При открытии AiAssistantChatScreen клиент собирает из локальной SQLite базы количество непрочитанных сообщений по контактам и комнатам, формирует краткую сводку и отправляет Oracle как контекст. Oracle красиво оформляет и предлагает действия.

Важно: содержимое сообщений зашифровано E2E и расшифровывается только на устройстве. Oracle на сервере НЕ видит содержимое чатов — он получает только метаданные (количество, отправитель, время). Формулировка "обсуждали Z" возможна только если клиент расшифрует и передаст — это опциональная функция с явным согласием пользователя.

### 6.5 Помощник в коммуникации

Пользователь может переслать Oracle сообщение и попросить: "переведи", "ответь за меня вежливо", "напиши поздравление", "сформулируй отказ".

Реализация: на клиенте — новая кнопка в контекстном меню сообщения "Спросить Oracle". При нажатии текст сообщения копируется в чат с Oracle с префиксом "Помоги с этим сообщением: [текст]". Oracle использует search_knowledge для контекста и свои языковые способности для генерации.

Важно: пользователь явно пересылает расшифрованное сообщение Oracle — это его осознанное действие. Oracle на сервере видит только то, что пользователь ему явно отправил.

### 6.6 Второй мозг — поиск по заметкам

Пользователь сохраняет заметки в Notes Vault. Oracle может искать по ним: "Что я сохранял про продуктивность?" — Oracle ищет по локальной SQLite таблице notes и группирует результаты.

Реализация: целиком на клиенте. Перед отправкой запроса Oracle клиент проверяет, содержит ли запрос слова-триггеры ("заметк", "сохран", "записал", "мои записи", "notes", "vault"). Если да — клиент выполняет поиск по SQLite таблице notes, добавляет найденные заметки в контекст запроса к Oracle. Oracle формирует ответ на основе найденного.

Заметки хранятся в SQLite на устройстве. Они НЕ отправляются на сервер целиком — отправляются только те, что релевантны запросу, и только в рамках текущего диалога.

### 6.7 Умные подсказки после ответа

После каждого ответа Oracle предлагает 2-3 follow-up вопроса, которые пользователь может задать одним нажатием. Не статичные, а контекстные — сгенерированные на основе текущего разговора.

Реализация: в ответе Oracle с бэкенда добавляется поле suggestions — массив из 2-3 строк. Клиент отображает их как chip-кнопки под сообщением (аналогично текущим suggestion chips на welcome-экране, но динамические).

---

## 7. Вау-эффекты для администратора

### 7.1 Утренний брифинг

Каждый день в 9:00 (настраивается) Oracle автоматически отправляет в Telegram dev-канал краткий отчёт:
- Состояние серверов (CPU, RAM, disk)
- Количество ошибок за ночь (из telemetry_logs)
- Новые пользователи за сутки (из users)
- Новый фидбэк (из oracle_feedback)
- Рекомендации (если есть паттерны в ошибках или фидбэке)

Если всё в порядке — одно короткое сообщение "Все системы в норме, 3 новых пользователя, 0 ошибок". Если проблемы — детальный разбор.

### 7.2 Автоматическое обнаружение багов

Каждые 15 минут Oracle проверяет telemetry_logs на аномалии (через check_error_spikes). Если количество ошибок за час превышает среднее в 3 раза — немедленный алерт в Telegram с:
- Количество ошибок и тренд
- Группировка по category и tag
- Попытка определить root cause (анализ details JSON)
- Корреляция с последним деплоем (сравнение с app_versions)
- Предложение создать GitHub issue

### 7.3 Разговорная аналитика

Админ просто спрашивает "как дела с ростом?" — Oracle вызывает get_user_statistics, get_revenue_report, analyze_feedback и формирует человеческий ответ с цифрами, сравнениями и рекомендациями. Не дашборд с графиками, а разговор с аналитиком.

### 7.4 Автоматический changelog

Перед релизом админ говорит "подготовь changelog для 1.2.0". Oracle вызывает generate_changelog, получает список коммитов, группирует, переводит на русский для пользователей, форматирует. Результат — готовый текст для загрузки в админку.

### 7.5 Умный приём фидбэка

Когда пользователь отправляет фидбэк через Oracle (collect_feedback), Oracle не просто сохраняет текст — он уточняет детали. "Бесит что нельзя отправить файл больше 10мб" — Oracle спросит: "Какие файлы вы пытались отправить? На каком устройстве?" Собирает полный контекст, определяет категорию и sentiment, сохраняет.

Если за неделю приходит 5+ фидбэков на одну тему — Oracle автоматически создаёт GitHub issue и пишет админу в Telegram: "Пользователи массово просят [тему], создал задачу #47."

### 7.6 Oracle как тестировщик

Админ говорит "проверь что всё работает". Oracle вызывает run_health_check(all) — реально дёргает API endpoints, проверяет ответы, замеряет latency, проверяет что WebSocket отвечает, что push отправляется. Результат: "API работает, latency 120ms, WebSocket OK, push OK. Всё стабильно."

### 7.7 Планирование релиза через диалог

"Что у нас готово к релизу?" — Oracle вызывает list_github_issues для всех репозиториев, группирует по статусу, оценивает готовность, предлагает scope и дату. "Для 1.2.0 готово 8 из 11 задач. Незакрытые: тёмная тема (может подождать), критичный баг #42 (нужно до релиза). Рекомендую релизить без тёмной темы в четверг. Создать milestone?"

### 7.8 Дайджест фидбэка

Каждый день в 18:00 Oracle проверяет oracle_feedback за день. Если есть новые записи — формирует краткий дайджест в Telegram: категории, sentiment, топ-проблемы. Если обнаружен критичный баг — создаёт issue немедленно, не дожидаясь дайджеста.

### 7.9 Оценка готовности к релизу

Каждую пятницу в 11:00 Oracle автоматически формирует отчёт: сколько задач закрыто из milestone, что осталось, есть ли блокеры, рекомендация — релизить или нет. Отправляет в Telegram.

---

## 8. Proactive Scheduler

Oracle работает не только когда его спрашивают, но и по расписанию. Задачи выполняются через APScheduler (Python), персистентный job store в PostgreSQL.

### Задачи

| Задача | Расписание | Действия |
|--------|-----------|----------|
| daily_health_check | Каждый день 09:00 | get_server_health(all) + check_error_spikes(window=480) + get_user_statistics(day) → Telegram |
| error_spike_monitor | Каждые 15 минут | check_error_spikes(window=60) → если аномалия, Telegram алерт |
| feedback_digest | Каждый день 18:00 | analyze_feedback(day) → если есть новое, Telegram дайджест |
| weekly_analytics | Каждый понедельник 10:00 | get_user_statistics(week) + get_revenue_report(week) + analyze_feedback(week) → Telegram дайджест |
| release_readiness | Каждую пятницу 11:00 | list_github_issues(all) → оценка готовности → Telegram |
| reminders_check | Каждую минуту | Проверка oracle_reminders → push пользователям |
| feedback_auto_issue | Каждые 6 часов | Проверка oracle_feedback на повторяющиеся темы → create_github_issue если порог |

Каждая задача scheduler запускает Oracle agent с системным промптом "Ты выполняешь проактивную задачу [название]. Используй инструменты для сбора данных и сформируй отчёт." Oracle сам решает, какие инструменты вызвать и как оформить результат.

---

## 9. Система памяти

### Три уровня

**L1 — Сессия** (in-memory на бэкенде). Текущий диалог: массив messages для передачи в LLM. Живёт до конца сессии (определяется по session_id). Включает все tool calls и их результаты.

**L2 — Пользователь** (PostgreSQL, таблица oracle_user_memory). Долгосрочная память о конкретном пользователе. Обновляется после каждой сессии — LLM сжимает диалог в summary. При новой сессии summary включается в системный промпт. Поля: id, pubkey, summary (до 2000 символов), topics (JSON массив строк), preferences (JSON), total_sessions (integer), updated_at.

**L3 — Глобальная** (PostgreSQL + pgvector, таблица oracle_knowledge). Документация, FAQ, troubleshooting, release notes. Embeddings генерируются через DeepSeek Embeddings API. Обновляется при изменениях в документации или добавлении новых знаний через update_knowledge.

### Поток памяти при запросе

1. Клиент отправляет message + session_id + X-Pubkey
2. Бэкенд загружает L2 memory для этого pubkey (или создаёт пустую)
3. Бэкенд загружает L1 session (или создаёт новую)
4. Системный промпт включает: базовый промпт + user summary из L2 + available tools
5. При tool call search_knowledge — обращение к L3 (pgvector similarity search)
6. После ответа — L1 обновляется (message + response)
7. При закрытии сессии (или по timeout 30 минут) — L2 обновляется (LLM сжимает L1 в summary)

---

## 10. Системные промпты

### Для роли user (русский)

```
Ты — Оракул Орфея, AI-помощник мессенджера Orpheus. Ты дружелюбный, компетентный и лаконичный.

Твои задачи:
- Отвечать на вопросы о функциях Orpheus
- Помогать с проблемами и настройками
- Принимать обратную связь и пожелания
- Помогать формулировать сообщения
- Напоминать о важном

Правила:
- Отвечай на языке пользователя (определяй по сообщению)
- Будь кратким, не больше 3-4 абзацев
- Если не знаешь ответа, скажи честно и предложи обратиться в поддержку
- Никогда не выдумывай функции, которых нет в Orpheus
- Используй инструмент search_knowledge для поиска ответов в документации
- Используй collect_feedback когда пользователь сообщает о баге или хочет фичу
- Предлагай 2-3 follow-up вопроса после каждого ответа

Контекст пользователя:
{user_memory_summary}

Текущая версия приложения: {app_version}
```

### Для роли admin (русский)

```
Ты — Оракул Орфея, AI-сотрудник проекта Orpheus. Ты работаешь как операционный менеджер, аналитик и ассистент основателя.

Тебе доступны инструменты для:
- Аналитики (SQL запросы, статистика пользователей, отчёты по доходам)
- Мониторинга (логи, здоровье серверов, аномалии в ошибках)
- Управления задачами (GitHub issues, планирование релизов, changelog)
- Коммуникации (Telegram, push-уведомления, email)
- Работы с фидбэком (анализ, категоризация, автоматические задачи)
- Knowledge base (поиск, обновление документации)

Правила:
- Отвечай на русском
- Будь конкретным — давай цифры, сравнения, рекомендации
- Если для ответа нужны данные, используй инструменты, не додумывай
- При SQL запросах: только SELECT, максимум 100 строк, timeout 10 секунд
- При создании GitHub issues: пиши title на английском, body структурировано
- При отправке в Telegram: форматируй Markdown, будь лаконичным
- Не выполняй деструктивных действий без подтверждения (удаление, массовая рассылка)
- Для массовых push-уведомлений всегда переспрашивай "Отправить N пользователям?"

Проактивные рекомендации:
- Если видишь паттерн в данных — предложи действие
- Если видишь повторяющийся фидбэк — предложи создать задачу
- Если метрики падают — предупреди и предложи расследование
```

### Для proactive задач scheduler

```
Ты — Оракул Орфея, выполняешь автоматическую проверку: {job_name}.

Цель: {job_description}

Используй доступные инструменты для сбора данных. Сформируй краткий отчёт.
Если обнаружены проблемы — подробно опиши и предложи действия.
Если всё в порядке — одно предложение.

Результат отправь через send_telegram_notification.
```

---

## 11. API Contract

### Основной endpoint

POST /api/oracle/chat — заменяет /api/public/ai/call

Заголовки:
- Content-Type: application/json
- X-Pubkey: {pubkey} (для user)
- X-Admin-Token: {JWT} (для admin)
- (без заголовков — visitor)

Тело запроса:
- message (string, обязательное) — текст сообщения пользователя
- session_id (string, опциональное) — ID сессии для сохранения контекста. Если не передан, создаётся новый.
- stream (boolean, по умолчанию false) — включить SSE streaming
- context (object, опциональное) — дополнительный контекст от клиента:
  - app_version (string) — версия приложения
  - device_info (string) — информация об устройстве
  - unread_summary (string) — сводка непрочитанных (для функции итогов)
  - notes_context (string) — найденные заметки (для функции поиска по заметкам)

Ответ (stream=false):
- answer (string) — текст ответа Oracle
- session_id (string) — ID сессии
- suggestions (array of strings) — 2-3 предложения для follow-up
- tools_used (array of strings) — какие инструменты были использованы (для UI индикаторов)
- model (string) — какая модель использовалась

Ответ (stream=true): Server-Sent Events
- event: thinking, data: {"content": "Анализирую данные..."}
- event: tool_call, data: {"name": "get_user_statistics", "status": "running"}
- event: tool_result, data: {"name": "get_user_statistics", "status": "done"}
- event: content, data: {"delta": "За последнюю неделю..."}
- event: suggestions, data: {"items": ["Подробнее про retention", "Сравни с прошлым месяцем"]}
- event: done, data: {"session_id": "...", "tools_used": [...]}

### Endpoint для фидбэка (без Oracle)

POST /api/oracle/feedback — быстрая отправка фидбэка без полного диалога с Oracle

Заголовки: X-Pubkey (опционально)
Тело: text (string), category (string, опционально)
Ответ: id записи, message "Спасибо за отзыв"

### Обратная совместимость

POST /api/public/ai/call — оставить рабочим, но внутри перенаправлять на новый Oracle с ролью visitor. Старые клиенты продолжат работать до обновления.

---

## 12. Изменения в существующих компонентах

### Бэкенд (d:\Programs\orpheus)

Новые файлы:
- app/oracle_api.py — роутер
- app/oracle/agent.py — ядро агента
- app/oracle/tools.py — инструменты
- app/oracle/prompts.py — промпты
- app/oracle/memory.py — память
- app/oracle/scheduler.py — proactive jobs
- app/oracle/embeddings.py — RAG embeddings

Изменения в существующих файлах:
- main.py — новые таблицы (oracle_feedback, oracle_user_memory, oracle_knowledge, oracle_reminders, oracle_sessions), новые env vars (DEEPSEEK_API_KEY, ORACLE_TELEGRAM_CHAT_ID), include oracle router
- app/public_api.py — /api/public/ai/call перенаправляет на oracle
- requirements.txt — openai, apscheduler, pgvector (новые зависимости)

Новые таблицы PostgreSQL:
- oracle_feedback — фидбэк от пользователей
- oracle_user_memory — долгосрочная память по пользователям
- oracle_knowledge — knowledge base с embeddings
- oracle_reminders — напоминания пользователей
- oracle_sessions — сессии диалогов (messages JSON, created_at, last_activity)

Новые переменные окружения:
- DEEPSEEK_API_KEY — ключ API DeepSeek
- ORACLE_TELEGRAM_CHAT_ID — ID Telegram чата для отчётов
- ORACLE_SCHEDULER_ENABLED — включить/выключить proactive задачи (default: true)

### Мобильный клиент (d:\orpheus_client)

Изменения в ai_assistant_service.dart:
- Endpoint меняется с /api/public/ai/call на /api/oracle/chat
- Добавляется поддержка SSE streaming (пакет http_sse или eventsource)
- Request body расширяется: session_id, stream: true, context
- Response обработка: suggestions, tools_used
- Отправка X-Pubkey заголовка (из CryptoService public key)
- Отправка X-Admin-Token если пользователь — админ

Изменения в ai_assistant_chat_screen.dart:
- Новый виджет ToolCallIndicator — показывает "Запрашиваю статистику..." с иконкой инструмента
- Streaming text — текст появляется по мере получения через SSE
- Suggestions chips — после каждого ответа Oracle, 2-3 динамические кнопки
- Feedback buttons — под каждым ответом Oracle маленькие кнопки "полезно" / "не полезно"
- Кнопка "Спросить Oracle" в контекстном меню сообщений в обычных чатах

Изменения в ai_message_model.dart:
- Новые поля: suggestions (List<String>?), toolsUsed (List<String>?), isStreaming (bool)

Изменения в database_service.dart:
- Новая колонка suggestions в ai_messages (TEXT, JSON строка)
- Миграция с текущей версии схемы

Изменения в notification_service.dart:
- Новый тип FCM: "oracle-reminder" — показывает local notification от Oracle
- Новый канал уведомлений "orpheus_oracle" с иконкой Oracle

Новые строки локализации (app_en.arb и app_ru.arb):
- oracleToolWorking / "Oracle is working..." / "Оракул работает..."
- oracleFeedbackThanks / "Thanks for feedback!" / "Спасибо за отзыв!"
- oracleAskAboutMessage / "Ask Oracle" / "Спросить Оракула"
- oracleReminder / "Reminder" / "Напоминание"
- oracleSummary / "While you were away..." / "Пока вас не было..."
- oracleHelpful / "Helpful" / "Полезно"
- oracleNotHelpful / "Not helpful" / "Не полезно"
- (и другие по мере реализации)

### Сайт (d:\Orpheus_Site)

Изменения в AiConsultantEmbed.tsx:
- Endpoint меняется на /api/oracle/chat
- Добавляется SSE streaming через EventSource API
- Добавляются индикаторы tool calls
- Добавляется typewriter для streaming
- Добавляются suggestion chips
- Добавляется feedback button

Изменения в translations.ts:
- Новые строки для tool indicators, suggestions, feedback

---

## 13. Стоимость

### DeepSeek API

Предполагаемая нагрузка:
- 50 пользовательских чатов/день × ~2000 токенов = 100K токенов/день
- 10 админских запросов/день × ~5000 токенов (с tool use) = 50K токенов/день
- Proactive jobs: ~300K токенов/день (5 задач, некоторые с chain tool calls)
- RAG embeddings: ~50K токенов/день

Итого: ~500K токенов/день, ~15M/месяц

Стоимость при ценах DeepSeek:
- Input: 15M × $0.27/M = $4
- Output: ~5M × $1.10/M = $5.5
- Embeddings: минимально
- DeepSeek R1 (для сложных запросов): ~$3

Итого API: ~$13/месяц

### Инфраструктура

- Дополнительная нагрузка на существующий контейнер Timeweb Apps: минимальная
- pgvector расширение: бесплатно (PostgreSQL уже есть)
- APScheduler: встроен, бесплатно

Итого инфраструктура: $0 сверх текущих расходов (возможно +100-200₽/мес если нужно больше RAM)

### Общая стоимость

~$13-15/месяц при нормальной нагрузке.

---

## 14. План реализации

### Фаза 1: Ядро агента (1-2 недели)

Цель: Oracle отвечает через DeepSeek вместо Timeweb, с базовыми инструментами.

Задачи:
- Создать app/oracle/ структуру на бэкенде
- Реализовать OracleAgent с agentic loop (agent.py)
- Подключить DeepSeek через openai SDK
- Реализовать 3 инструмента: search_knowledge, query_database, parse_backend_logs
- Перенести knowledge base из Timeweb в pgvector (oracle_knowledge)
- Создать endpoint POST /api/oracle/chat
- Сохранить обратную совместимость /api/public/ai/call
- Система ролей (visitor / user / admin)
- Тесты для agentic loop и инструментов

Результат: Oracle отвечает на вопросы через DeepSeek, может делать SQL запросы (для админа), ищет по knowledge base.

### Фаза 2: Полный набор инструментов (1-2 недели)

Цель: все 18+ инструментов работают.

Задачи:
- Все инструменты аналитики (get_user_statistics, get_revenue_report)
- Все инструменты мониторинга (get_server_health, check_error_spikes, get_api_metrics)
- Все инструменты задач (create_github_issue, list_github_issues, draft_release_plan, generate_changelog)
- Инструменты фидбэка (collect_feedback, analyze_feedback) + таблица oracle_feedback
- Инструменты действий (send_telegram_notification, send_push_notification, send_email, run_health_check)
- Инструмент update_knowledge
- Тесты для каждого инструмента

Результат: Админ может через Oracle получить любую аналитику, создать задачу, отправить уведомление.

### Фаза 3: Память и персонализация (1 неделя)

Цель: Oracle помнит пользователей и контекст между сессиями.

Задачи:
- Таблица oracle_user_memory + oracle_sessions
- Сжатие диалогов в summary после сессии
- Включение user memory в системный промпт
- Session management (создание, восстановление, timeout)
- Динамические suggestions после каждого ответа
- Тесты для memory flow

Результат: Oracle помнит прошлые разговоры, предлагает релевантные follow-up вопросы.

### Фаза 4: SSE Streaming + обновление клиентов (1-2 недели)

Цель: ответы Oracle приходят потоково, с индикаторами инструментов.

Задачи:
- SSE streaming на бэкенде (event: thinking, tool_call, content, done)
- Мобильный клиент: SSE через http_sse пакет, обновление AiAssistantService
- Мобильный UI: ToolCallIndicator, streaming text, suggestion chips, feedback buttons
- Сайт: EventSource API, обновление AiConsultantEmbed
- Обновление локализации (EN + RU)
- Миграция SQLite схемы на клиенте

Результат: пользователь видит как Oracle думает, какие инструменты вызывает, ответ появляется по мере генерации.

### Фаза 5: Proactive Scheduler (1 неделя)

Цель: Oracle работает по расписанию без запросов.

Задачи:
- APScheduler интеграция в бэкенд
- daily_health_check (09:00)
- error_spike_monitor (каждые 15 мин)
- feedback_digest (18:00)
- weekly_analytics (ПН 10:00)
- release_readiness (ПТ 11:00)
- reminders_check (каждую минуту)
- Конфиг для включения/выключения каждой задачи
- Логирование выполнения задач

Результат: Oracle сам присылает отчёты, алерты и рекомендации в Telegram.

### Фаза 6: Вау-эффекты (1-2 недели)

Цель: функции, которые делают Oracle незаменимым.

Задачи:
- Напоминания (oracle_reminders + scheduler + push)
- "Спросить Oracle" в контекстном меню сообщений
- Поиск по заметкам Notes Vault (на клиенте)
- Итоги пропущенных чатов (на клиенте)
- Приветствие с учётом версии и известных проблем
- Автоматическое создание issues из повторяющегося фидбэка
- Проверка работоспособности (run_health_check)

Результат: Oracle — не просто чат-бот, а личный помощник и AI-сотрудник.

---

## 15. Риски и митигации

**Риск: DeepSeek tool use ненадёжен** — Митигация: детальные описания инструментов, валидация аргументов, retry с переформулировкой, лимит 8 tool calls за loop.

**Риск: DeepSeek API недоступен** — Митигация: graceful degradation. Если API не отвечает — Oracle показывает "Временно недоступен, попробуйте позже". Proactive задачи откладываются до восстановления. Fallback на search_knowledge без LLM (keyword search).

**Риск: SQL injection через query_database** — Митигация: запрос проходит через whitelist (только SELECT), параметризация невозможна (динамический SQL от LLM), поэтому read-only пользователь БД + timeout 10 сек + лимит 100 строк.

**Риск: Oracle галлюцинирует данные** — Митигация: в промпте явно сказано "используй инструменты, не выдумывай". В ответе указываются tools_used — админ видит, что данные реальные. Для аналитики — всегда через инструменты, никогда "на глаз".

**Риск: Утечка данных через Oracle** — Митигация: Oracle НЕ имеет доступа к содержимому E2E зашифрованных сообщений. В БД хранятся только metadata (pubkey, timestamps). Таблица messages на клиенте (SQLite) — зашифрована. Заметки передаются Oracle только если пользователь явно это делает.

**Риск: Стоимость выходит из-под контроля** — Митигация: rate limiting (10 запросов/мин для user, 30 для admin, 5 для visitor). Мониторинг расходов через DeepSeek dashboard. Лимит токенов на ответ (max_tokens: 4096).
