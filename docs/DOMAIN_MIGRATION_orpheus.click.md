# Миграция домена Orpheus: разделение сайта / API / обновлений

## Контекст текущей реализации (как сейчас)

### Клиент (Android / Flutter)
- Базовый хост зашит в `lib/config.dart` (`AppConfig.serverIp`).
- Связь:
  - WebSocket: `wss://<host>/ws/<pubkey>` (см. `AppConfig.webSocketUrl()`)
  - HTTP: `https://<host>/api/...` (см. `AppConfig.httpUrl()`)
- Обновления:
  - Клиент делает `GET https://<host>/api/check-update` (см. `lib/services/update_service.dart`).
  - Сервер отдаёт `download_url`.
  - Если `download_url` начинается с `http`, клиент использует его **как есть** (это позволяет мигрировать обновления без изменения домена у старых клиентов).

### Сервер связи (FastAPI)
- Один сервис одновременно отдаёт:
  - сайт `GET /` (читает `static/index.html`)
  - обновление APK `GET /download` (отдаёт `static/orpheus.apk`)
  - API обновлений `GET /api/check-update` (таблица `app_versions`)
  - WebSocket `WS /ws/{client_id}`

## Цель (как должно быть)

- `orpheus.click` — сайт + вход в админку (единый сервис `OPHEUS_ADMIN`)
- `api.orpheus.click` — API + WebSocket связь
- `update.orpheus.click` — раздача APK/артефактов (Timeweb Cloud S3)

### Критичное требование
Старый домен `vadimkolobanov-orpheus-d95e.twc1.net` **оставляем работать** (связь + обновления) пока есть клиенты, которые:
- подключаются по старому домену
- получают обновления по старому домену

## План миграции маленькими этапами (без остановки прод)

### Этап 0. Подготовка
- Зафиксировать текущие рабочие пути, которые нельзя ломать на старом домене:
  - `GET /api/check-update`
  - `WS /ws/...`
  - `POST /api/signal`
  - `GET /download` (пока не перенесены артефакты)
- Поставить низкий DNS TTL для будущих записей (например 300–600 сек), чтобы быстро откатываться.

**Готово, когда**: ничего не меняли в проде, только подготовили почву.

### Этап 1. DNS для `orpheus.click`
Создать записи:
- `orpheus.click` → сервер/хостинг сайта
- `api.orpheus.click` → сервер связи (на старте можно CNAME на текущий домен сервера связи или A на его IP)
- `update.orpheus.click` → endpoint S3/website/CDN Timeweb Cloud

**Готово, когда**: все три имени резолвятся, но приложение ещё не переключали.

### Этап 2. Поднять `update.orpheus.click` на S3 (Timeweb Cloud)
- Создать bucket, включить публичную раздачу (или через CDN/website hosting).
- Залить APK:
  - минимум: `orpheus.apk`
  - лучше: `orpheus-<version>.apk` + `latest.apk`
- Проверить скачивание по `https://update.orpheus.click/...`.

**Готово, когда**: APK открывается/скачивается с нового домена.

### Этап 3. «Тихая» миграция обновлений для старых клиентов (без релиза)
Суть: старый клиент продолжает спрашивать старый сервер `GET /api/check-update`, но получает **абсолютный** `download_url` на новый домен.

- В записи последней версии в `app_versions` установить:
  - `download_url = "https://update.orpheus.click/orpheus.apk"` (или versioned путь)

**Готово, когда**: старые клиенты качают APK уже с `update.orpheus.click`, а связь остаётся на старом домене.

### Этап 4. Включить `api.orpheus.click` (TLS + WebSocket)
- Выпустить сертификат для `api.orpheus.click`.
- Убедиться, что прокси/хостинг корректно поддерживает WebSocket Upgrade на `/ws`.

**Готово, когда**: `wss://api.orpheus.click/ws/<pubkey>` подключается.

### Этап 5. Сайт на `orpheus.click` (отдельно)
- Разместить сайт на `orpheus.click` (публичные страницы) в сервисе `OPHEUS_ADMIN`.
- Админка доступна по `/admin`, вход по `/login`.
- Старый домен можно оставить как есть или сделать редирект только для `/` (не трогая `/ws` и `/api`).

**Готово, когда**: сайт живёт отдельно.

### Этап 6. Новый релиз клиента: переход на `api.orpheus.click` + безопасный fallback
- В клиенте добавить приоритетный хост `api.orpheus.click`.
- Если новый хост недоступен — автоматически пробовать старый домен.

**Готово, когда**: новый клиент работает на `api.orpheus.click`, но не «умирает», если DNS/TLS/прокси временно сломаны.

### Этап 7. Долгая совместимость
- Старый домен держим включённым до конца миграции аудитории.
- Позже можно включить «принудительное обновление» (`required=true`) на старом домене.

---

## Технические проверки (чек-лист)

- [ ] `GET https://<old>/api/check-update` работает
- [ ] `GET https://<old>/download` работает (пока нужно)
- [ ] `wss://<old>/ws/<pubkey>` работает
- [ ] `GET https://api.orpheus.click/api/check-update` работает
- [ ] `wss://api.orpheus.click/ws/<pubkey>` работает
- [ ] `https://update.orpheus.click/<apk>` скачивается
- [ ] В `app_versions.download_url` стоит абсолютная ссылка на `update.orpheus.click`



