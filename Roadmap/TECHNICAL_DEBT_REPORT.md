# 📊 ТЕХНИЧЕСКИЕ ДОЛГИ ПРОЕКТА ORPHEUS

**Дата составления:** 07.02.2026
**Версия:** 1.0
**Компоненты:** Mobile Client, Desktop Client, Backend, Website, Mailer Relay

---

## Содержание

1. [Executive Summary](#executive-summary)
2. [Orpheus Mobile Client (Flutter)](#1-orpheus-mobile-client-flutter)
3. [Orpheus Desktop (C# WinUI 3)](#2-orpheus-desktop-c-winui-3)
4. [Orpheus Backend (Python FastAPI)](#3-orpheus-backend-python-fastapi)
5. [Проблема с Changelog](#4-проблема-с-changelog)
6. [Orpheus Website & Mailer Relay](#5-orpheus-website--mailer-relay)
7. [Сводная статистика](#6-сводная-статистика)
8. [Рекомендации по MCP серверам](#7-рекомендации-по-mcp-серверам)
9. [Приоритизированный план действий](#8-приоритизированный-план-действий)

---

## Executive Summary

Проведен детальный аудит всех компонентов проекта Orpheus. **Выявлено 89 технических долгов** различной степени критичности:

| Компонент | 🔴 Critical | 🟠 High | 🟡 Medium | 🔵 Low | 🟣 Crypto | **Всего** |
|-----------|------------|---------|-----------|--------|-----------|-----------|
| Mobile Client | 5 | 6 | 8 | 4 | 3 | **26** |
| Desktop Client | 6 | 0 | 10 | 4 | 0 | **20** |
| Backend | 6 | 10 | 12 | 9 | 0 | **37** |
| Changelog Issue | 1 | 0 | 0 | 0 | 0 | **1** |
| Website/Mailer | 0 | 0 | 3 | 2 | 0 | **5** |
| **ИТОГО** | **18** | **16** | **33** | **19** | **3** | **89** |

### Ключевые выводы:

✅ **Положительно:**
- Мобильный клиент имеет хорошую архитектурную базу
- Backend масштабируется через Redis
- Zero-knowledge архитектура соблюдена

❌ **Критические проблемы:**
- **18 блокеров для продакшена** (незашифрованная БД, слабое хеширование PIN, credentials в коде)
- Desktop Link feature готов только на **~20%**
- Backend API для changelog **не реализован**
- Отсутствует Certificate Pinning во всех клиентах

⚠️ **Требуется:**
- **5 недель** для исправления всех critical issues (Mobile)
- **8-10 недель** для завершения Desktop Link
- **4 недели** для устранения backend security issues

---

## 1. Orpheus Mobile Client (Flutter)

**Источник:** [SECURITY_AUDIT_REPORT.md](SECURITY_AUDIT_REPORT.md)

### 🔴 Критические уязвимости (5)

| # | Проблема | Файл | Влияние | Срок |
|---|----------|------|---------|------|
| 1 | TURN credentials в открытом коде | [webrtc_service.dart:6-21](../lib/services/webrtc_service.dart#L6-L21) | Злоумышленник может использовать TURN сервер | 4h |
| 2 | БД не зашифрована (sqflite) | [database_service.dart](../lib/services/database_service.dart) | На рутованных устройствах вся переписка доступна | 8h |
| 3 | Нет Certificate Pinning | Все HTTP/WS вызовы | MITM атаки | 4h |
| 4 | PIN: SHA-256 вместо Argon2id | [auth_service.dart:464-476](../lib/services/auth_service.dart#L464-L476) | Brute-force за секунды на GPU | 4h |
| 5 | Sentry DSN в коде | [main.dart](../lib/main.dart) | DoS на мониторинг | 1h |

### 🟠 Серьезные проблемы (6)

| # | Проблема | Файл | Влияние |
|---|----------|------|---------|
| 6 | CryptoService не singleton | [crypto_service.dart](../lib/services/crypto_service.dart) | Ключи не зануляются при wipe |
| 7 | 170+ print() в production | Множество файлов | Утечка в logcat |
| 8 | Биометрия не сохраняется (TODO) | [security_settings_screen.dart:147](../lib/screens/security_settings_screen.dart#L147) | Функция не работает |
| 9 | Public key в WebSocket URL | [config.dart:26-29](../lib/config.dart#L26-L29) | Логируется на всех прокси |
| 10 | HTTP signaling без подписи | [websocket_service.dart:358-397](../lib/services/websocket_service.dart#L358-L397) | Можно завершить чужие звонки |
| 11 | Wipe: fail-open при ошибке | [auth_service.dart:422-452](../lib/services/auth_service.dart#L422-L452) | Данные могут остаться |

### 🟡 Архитектурные недоработки (8)

- Singleton-антипаттерн повсюду
- main.dart — God Object (сотни строк)
- WebRTCService: нет dispose() для StreamControllers
- Дублирование CallKit/CallId логики
- Race condition в PendingActionsService
- Нет индексов на таблице messages
- Миграции БД — silent catch
- verifyPin() — async без await

### 🟣 Криптографические замечания (3)

- X25519 shared secret без HKDF
- Нет Forward Secrecy / key rotation
- Nonce uniqueness не гарантирована

### Оценка готовности: ⚠️ **70% для продакшена**

**Требуется:** 5 недель работы 1 разработчика для устранения всех critical issues

---

## 2. Orpheus Desktop (C# WinUI 3)

### 🔴 Критические проблемы безопасности (6)

| # | Проблема | Файл | Влияние | Срок |
|---|----------|------|---------|------|
| 1 | HTTP вместо HTTPS (ws://) | [PhoneLinkService.cs:152](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\PhoneLinkService.cs#L152) | MITM атаки | 2h |
| 2 | Public key — заглушка (random bytes) | [PhoneLinkService.cs:84](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\PhoneLinkService.cs#L84) | Нет реального шифрования | 6h |
| 3 | OTP в памяти без защиты | [PhoneLinkService.cs:28,139](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\PhoneLinkService.cs#L28) | Утечка через memory dump | 2h |
| 4 | Session Token в plaintext | [DesktopLinkHttpServer.cs:97-98](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\DesktopLinkHttpServer.cs#L97) | Нет валидации | 3h |
| 5 | Desktop ID в LocalSettings | [PhoneLinkService.cs:110-119](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\PhoneLinkService.cs#L110) | Должен быть в Credential Manager | 2h |
| 6 | Нет валидации JSON | [DesktopLinkHttpServer.cs:88-112](d:\orpheus_desctop\orpheus_desktop\Services\DesktopLink\DesktopLinkHttpServer.cs#L88) | Injection атаки | 4h |

### 🟡 Архитектурные проблемы (10)

- **Отсутствует CryptoService** (требуется реализация X25519 + ChaCha20)
- **Отсутствует WebSocketService** (используется raw ClientWebSocket)
- **Отсутствует DatabaseService** (нет персистентности)
- Неправильный паттерн HttpServer (TcpListener вместо HttpListener)
- Отсутствует DI контейнер
- DateTime.Now вместо DateTime.UtcNow
- ThemeService неполный
- NavigationService без параметров
- Нет graceful shutdown
- WebSocket не обрабатывает фрагментированные сообщения

### 🟢 Критические недоделанные фичи (TODOs)

| Feature | Файл | Статус |
|---------|------|--------|
| Create/Import Account | [WelcomeViewModel.cs:18-27](d:\orpheus_desctop\orpheus_desktop\ViewModels\WelcomeViewModel.cs#L18) | Stub (Task.Delay) |
| Load Contacts | [ContactsViewModel.cs:33-35](d:\orpheus_desctop\orpheus_desktop\ViewModels\ContactsViewModel.cs#L33) | Mock данные |
| Messages Sync | [ChatViewPage.xaml.cs:35-46](d:\orpheus_desctop\orpheus_desktop\Views\ChatViewPage.xaml.cs#L35) | Hard-coded demo |
| Add Contact | [ContactsPage.xaml.cs:19](d:\orpheus_desctop\orpheus_desktop\Views\ContactsPage.xaml.cs#L19) | TODO |
| About Dialog | [ShellPage.xaml.cs:217](d:\orpheus_desctop\orpheus_desktop\Views\ShellPage.xaml.cs#L217) | TODO |

### 🔧 Тестовое покрытие

❌ **Нет тестов вообще** — требуется создать `orpheus_desktop.Tests.csproj`

### Desktop Link Feature — Статус готовности

| Компонент | Готовность | Требуется |
|-----------|-----------|-----------|
| QR Generation | ~30% | Криптография |
| HTTP Server | ~50% | Валидация, HttpListener |
| OTP Verification | ~20% | Реальная проверка |
| WebSocket Connection | ~40% | wss://, фрагменты |
| Key Exchange | 0% | Реализация X25519 |
| E2E Encryption | 0% | CryptoService |
| Persist Session | 0% | DatabaseService |
| **Overall** | **~20%** | **8-10 недель работы** |

### Оценка готовности: ⚠️ **25% для продакшена**

**Требуется:** 8-10 недель для завершения Desktop Link + core функций

---

## 3. Orpheus Backend (Python FastAPI)

### 🔴 Критические уязвимости (6)

| # | Проблема | Файл | Влияние | Срок |
|---|----------|------|---------|------|
| 1 | ADMIN_BYPASS_AUTH в продакшене | [main.py:71,731-732](d:\Programs\orpheus\main.py#L71) | Полный доступ к админке | 15min |
| 2 | Дефолтный ADMIN_SECRET | [main.py:63](d:\Programs\orpheus\main.py#L63) | Известный пароль | 20min |
| 3 | Нет Rate Limiting | main.py, admin_api.py, auth_api.py | Brute-force, DDoS | 4h |
| 4 | Утечка pubkey в логах | [main.py:174-175,233-234](d:\Programs\orpheus\main.py#L174) | Деанонимизация | 3h |
| 5 | /api/logs без аутентификации | [logs_api.py](d:\Programs\orpheus\app\logs_api.py) | DoS через логи | 2h |
| 6 | WebSocket 1MB без лимита | [main.py:2214-2218](d:\Programs\orpheus\main.py#L2214) | Memory exhaust | 2h |

### 🟠 Высокий уровень (10)

- Нет аутентификации WebSocket (любой может подключиться под чужим pubkey)
- Потенциальный SQL Injection в raw queries
- CORS разрешает все методы
- `/admin-reply` защищен только plaintext секретом
- TRON integration без обработки ошибок
- payment_watcher: бесконечный цикл без graceful shutdown
- Нет шифрования FCM токенов в БД
- Отсутствует Alembic для миграций БД
- DEBUG_LOG_PATH: hardcoded Windows путь (`d:\orpheus_client`)
- Нет защиты от infinite loops в Redis

### 🟡 Средний уровень (12)

- Нет версионирования API (`/api/v1/`)
- Offline messages буфер без TTL
- asyncpg pool без размера
- Нет graceful shutdown для WS
- Нет heartbeat для long-lived WS
- Нет сжатия больших сообщений
- Некорректная обработка JSON parsing
- Нет circuit breaker для TRON/Firebase/AI
- Нет кэширования (Redis для app_versions)
- Нет Prometheus метрик
- Нет структурированного логирования
- Race condition в payment confirmation

### 🔵 Низкий уровень (9)

- Нет аудита для больших операций (батчинг)
- Нет composite индексов
- Нет EXPLAIN ANALYZE для slow queries
- Нет валидации пользовательского текста (XSS)
- Нет GDPR compliance (soft delete)
- Нет backup/restore механизма
- Нет API documentation (OpenAPI)
- Нет e2e tests для критичных flows
- Deprecated dependencies

### Оценка готовности: ⚠️ **75% для продакшена**

**Требуется:** 4 недели для устранения critical security issues

---

## 4. Проблема с Changelog

### 🔴 Главная причина: Backend API не реализован

**Файлы:**
- Mobile: [lib/services/release_notes_service.dart:41-89](../lib/services/release_notes_service.dart#L41-L89)
- Mobile: [lib/updates_screen.dart:51-81](../lib/updates_screen.dart#L51-L81)
- Mobile: [lib/config.dart:59-142](../lib/config.dart#L59-L142)

**Проблема:**
1. Мобильный клиент запрашивает `GET /api/public/releases?limit=50`
2. **Endpoint не существует на backend**
3. Fallback к встроенным данным из `AppConfig.changelogData`
4. Пользователь видит только старые версии (последняя 1.1.0 от 12.12.2025)

**Решение:**

### Backend (Python FastAPI) — добавить endpoint:

```python
# app/public_api.py или main.py
@app.get("/api/public/releases")
async def get_public_releases(limit: int = 50):
    """Returns list of public app releases with changelog"""
    releases = await db.query("""
        SELECT version_code, version_name, required,
               download_url, created_at, public_changelog
        FROM app_versions
        WHERE public = true
        ORDER BY created_at DESC
        LIMIT $1
    """, limit)

    return [
        {
            "version_code": r.version_code,
            "version_name": r.version_name,
            "required": r.required,
            "download_url": r.download_url,
            "created_at": r.created_at.isoformat() + "Z",
            "public_changelog": r.public_changelog
        }
        for r in releases
    ]
```

### Mobile (Flutter) — добавить логирование:

```dart
// lib/services/release_notes_service.dart
Future<List<ReleaseNote>> fetchPublicReleases({int limit = 30}) async {
  // ... existing code ...
  } catch (e) {
    lastError = e;
    debugPrint('ReleaseNotesService: Network error from $base: $e'); // ← ADD
    continue;
  }
}
```

**Срок исправления:** 2-3 часа (backend endpoint + тестирование)

---

## 5. Orpheus Website & Mailer Relay

### Orpheus Site (React + TypeScript)

**Статус:** ✅ Production Ready (~95%)

**Минорные проблемы:**

🟡 **Medium (3):**
- Нет автоматизированного деплоя (CI/CD для Vercel/Netlify)
- Нет SEO meta tags для всех страниц
- Нет structured data (Schema.org) для поисковиков

🔵 **Low (2):**
- Нет Google Analytics / Plausible для аналитики
- Нет rate limiting на contact forms (если есть)

**Рекомендации:**
- Добавить GitHub Actions для автодеплоя
- Использовать `react-helmet` для SEO
- Добавить sitemap.xml и robots.txt

### Orpheus Mailer Relay (Go)

**Статус:** ✅ Production Ready (~90%)

**Минорные проблемы:**

🟡 **Medium (0)** — нет критичных проблем

🔵 **Low (1):**
- Нет Prometheus метрик для мониторинга
- Можно добавить rate limiting на уровне relay

**Рекомендации:**
- Добавить `/metrics` endpoint
- Логировать все SMTP операции в structured format

---

## 6. Сводная статистика

### По компонентам

```
Orpheus Mobile:  ████████████████░░░░ 70% готовности
Orpheus Desktop: ████░░░░░░░░░░░░░░░░ 25% готовности
Orpheus Backend: ███████████████░░░░░ 75% готовности
Orpheus Website: ███████████████████░ 95% готовности
Orpheus Mailer:  ██████████████████░░ 90% готовности

ОБЩИЙ ПРОЕКТ:    ███████████░░░░░░░░░ 60% готовности
```

### По критичности

| Уровень | Количество | Трудозатраты | Приоритет |
|---------|-----------|--------------|-----------|
| 🔴 Critical | 18 | ~90 часов | Блокеры |
| 🟠 High | 16 | ~120 часов | Неделя 1-2 |
| 🟡 Medium | 33 | ~200 часов | Неделя 3-6 |
| 🔵 Low | 19 | ~80 часов | После релиза |
| 🟣 Crypto | 3 | ~60 часов | Неделя 7-8 |

**Общая оценка:** ~550 часов = **13-14 недель работы** 1 разработчика

---

## 7. Рекомендации по MCP серверам

### Текущая ситуация

Проект Orpheus **не использует MCP серверы**, но они могут значительно ускорить разработку и поддержку.

### Рекомендуемые MCP серверы для проекта

| MCP сервер | Назначение | Приоритет | Преимущества |
|------------|------------|-----------|--------------|
| **@modelcontextprotocol/server-postgres** | Работа с PostgreSQL БД backend | 🔴 HIGH | Прямые SQL запросы, миграции, анализ схемы |
| **@modelcontextprotocol/server-github** | Управление репозиториями | 🟠 MEDIUM | Issues, PRs, code review автоматизация |
| **@modelcontextprotocol/server-filesystem** | Навигация по файлам | 🟢 LOW | Уже есть встроенные инструменты |
| **Custom TRON Blockchain MCP** | Мониторинг TRON payments | 🟡 MEDIUM | Автоматизация проверки транзакций |
| **Custom Firebase MCP** | Управление FCM, аналитика | 🔵 LOW | Push notification debugging |
| **@modelcontextprotocol/server-docker** | Docker контейнеры | 🟡 MEDIUM | Деплой, логи, мониторинг |

### Приоритетный план подключения MCP

#### Фаза 1 (сейчас): PostgreSQL MCP

**Установка:**
```bash
npm install -g @modelcontextprotocol/server-postgres
```

**Конфигурация в Claude Desktop:**
```json
{
  "mcpServers": {
    "postgres": {
      "command": "mcp-server-postgres",
      "args": ["postgresql://orpheus_user:password@localhost:5432/orpheus_db"],
      "env": {
        "POSTGRES_CONNECTION": "postgresql://..."
      }
    }
  }
}
```

**Применение:**
- Быстрый анализ схемы БД
- Генерация миграций Alembic
- Отладка SQL запросов
- Проверка индексов и производительности

#### Фаза 2 (через месяц): GitHub MCP

**Применение:**
- Автоматизация создания issues из технических долгов
- Code review автоматизация
- Управление PR для фич

#### Фаза 3 (по необходимости): Custom MCP серверы

**TRON Blockchain MCP** — для автоматизации:
- Проверки балансов адресов
- Мониторинга транзакций
- Генерации отчетов по платежам

---

## 8. Приоритизированный план действий

### 🚨 Немедленно (Неделя 1) — Блокеры безопасности

**Mobile Client:**
- [ ] Заменить sqflite на sqflite_sqlcipher (8h)
- [ ] Добавить Certificate Pinning (4h)
- [ ] Argon2id вместо SHA-256 для PIN (4h)
- [ ] Убрать TURN credentials из кода → API с TTL (4h)
- [ ] Sentry DSN в dart-define (1h)

**Backend:**
- [ ] Удалить ADMIN_BYPASS_AUTH (15min)
- [ ] Обязательная проверка ADMIN_SECRET (20min)
- [ ] Добавить Rate Limiting (4h)
- [ ] Хешировать pubkey в логах (3h)
- [ ] Реализовать `/api/public/releases` endpoint (3h)

**Итого:** ~32 часа

---

### ⚠️ Неделя 2-3 — Критичные доработки

**Mobile Client:**
- [ ] Исправить биометрию (сохранение настройки) (2h)
- [ ] WebSocket auth challenge-response (6h)
- [ ] HTTP signaling с подписью (4h)
- [ ] CryptoService → singleton + zeroize (4h)
- [ ] Wipe: best-effort pattern (2h)

**Backend:**
- [ ] Шифрование FCM токенов в БД (8h)
- [ ] JWT для `/admin-reply` (3h)
- [ ] Alembic миграции (5h)
- [ ] Graceful shutdown (4h)

**Desktop:**
- [ ] ws:// → wss:// (2h)
- [ ] Реализовать базовый CryptoService (8h)
- [ ] Windows Credential Manager для ключей (4h)

**Итого:** ~52 часа

---

### 🔧 Неделя 4-8 — Desktop Link + Архитектура

**Desktop Client (приоритет):**
- [ ] Завершить CryptoService (X25519 + ChaCha20) (16h)
- [ ] DatabaseService с SQLite (12h)
- [ ] WebSocketService (10h)
- [ ] Реализовать Desktop Link Key Exchange (20h)
- [ ] Sync контактов и сообщений (16h)
- [ ] Unit тесты (20h)

**Mobile Client:**
- [ ] Применить HKDF после ECDH (8h)
- [ ] Ephemeral keys для сессий (16h)
- [ ] Индексы SQLite (4h)
- [ ] Рефакторинг main.dart (12h)

**Backend:**
- [ ] Prometheus метрики (8h)
- [ ] Structured logging (6h)
- [ ] Circuit breaker для TRON/Firebase (10h)

**Итого:** ~158 часов

---

### 📈 Неделя 9-14 — Полировка и тестирование

**Все компоненты:**
- [ ] E2E тесты критичных flows (40h)
- [ ] Load testing (WebSocket, payments) (16h)
- [ ] Security audit round 2 (20h)
- [ ] Performance optimization (20h)
- [ ] Documentation (API, setup guides) (16h)
- [ ] Beta testing с реальными пользователями (32h)

**Итого:** ~144 часа

---

## Общая временная оценка

| Фаза | Срок | Трудозатраты | Ключевые задачи |
|------|------|--------------|-----------------|
| **Фаза 1** | Неделя 1 | 32h | Блокеры безопасности |
| **Фаза 2** | Неделя 2-3 | 52h | Критичные доработки |
| **Фаза 3** | Неделя 4-8 | 158h | Desktop Link feature |
| **Фаза 4** | Неделя 9-14 | 144h | Полировка и тестирование |
| **ИТОГО** | **14 недель** | **386 часов** | Ready for production |

**При команде из 2 разработчиков:** ~7-8 недель
**При команде из 3 разработчиков:** ~5-6 недель

---

## Заключение

Проект Orpheus имеет **солидную основу**, но требует:

1. **Немедленно:** Устранение 18 критических уязвимостей безопасности
2. **В течение месяца:** Завершение Desktop Link feature (сейчас 20%)
3. **В течение 2-3 месяцев:** Полная готовность к продакшену

**Главные риски:**
- Незашифрованная БД мобильного клиента
- Отсутствие Certificate Pinning
- Desktop клиент не готов к релизу

**Рекомендации:**
- Начать с Mobile security fixes (Неделя 1)
- Параллельно завершить Desktop Link (Недели 2-8)
- Использовать MCP серверы для ускорения разработки
- Провести повторный security audit перед релизом

---

**Следующие шаги:**
1. ✅ Согласовать этот список технических долгов
2. ⏳ Создать Issues в GitHub для каждой задачи
3. ⏳ Распределить задачи по спринтам
4. ⏳ Начать работу с Фазы 1 (блокеры безопасности)

---

*Отчет составлен на основе автоматизированного анализа кодовой базы всех компонентов проекта Orpheus.*
