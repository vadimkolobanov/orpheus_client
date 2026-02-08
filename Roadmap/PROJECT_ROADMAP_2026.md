# 🗺️ ORPHEUS PROJECT ROADMAP 2026

**Версия:** 1.0
**Дата:** 07.02.2026
**Статус проекта:** Beta → Production Preparation

---

## 📋 Содержание

1. [Текущее состояние проекта](#текущее-состояние-проекта)
2. [Vision и цели](#vision-и-цели)
3. [Q1 2026 (Февраль - Апрель)](#q1-2026-февраль---апрель)
4. [Q2 2026 (Май - Июль)](#q2-2026-май---июль)
5. [Q3 2026 (Август - Октябрь)](#q3-2026-август---октябрь)
6. [Q4 2026 (Ноябрь - Декабрь)](#q4-2026-ноябрь---декабрь)
7. [Метрики успеха](#метрики-успеха)
8. [Риски и митигация](#риски-и-митигация)

---

## Текущее состояние проекта

### Версии компонентов

| Компонент | Версия | Статус | Готовность |
|-----------|--------|--------|------------|
| **Orpheus Mobile** | v1.1.2+8 | Beta | 70% |
| **Orpheus Desktop** | v0.1.0 (beta) | Alpha | 25% |
| **Orpheus Backend** | v1.x | Production | 75% |
| **Orpheus Website** | v1.x | Production | 95% |
| **Orpheus Mailer** | v1.x | Production | 90% |

### Активные пользователи

- **Mobile:** ~100-500 beta testers
- **Desktop:** Internal testing only
- **Backend:** Stable, handling production load

### Технические долги

**Выявлено:** 89 технических долгов ([подробнее](TECHNICAL_DEBT_REPORT.md))
- 🔴 Critical: 18
- 🟠 High: 16
- 🟡 Medium: 33
- 🔵 Low: 19

---

## Vision и цели

### Миссия проекта

> Создать самый безопасный и удобный мессенджер с E2E шифрованием, AI-ассистентом и поддержкой криптовалютных платежей для пользователей, ценящих приватность.

### Ключевые преимущества

1. **Zero-knowledge архитектура** — сервер никогда не видит расшифрованные сообщения
2. **Duress mode & Panic wipe** — защита под давлением
3. **Oracle of Orpheus** — встроенный AI ассистент
4. **Desktop Link** — синхронизация с Windows приложением
5. **TRON payments** — встроенная поддержка криптовалютных платежей

### Целевая аудитория

- Журналисты и активисты
- Бизнесмены с высокими требованиями к безопасности
- Пользователи, недовольные Telegram/Signal/WhatsApp
- Криптоэнтузиасты

### Цели на 2026 год

| Метрика | Q1 | Q2 | Q3 | Q4 |
|---------|----|----|----|----|
| **Активные пользователи** | 500 | 5,000 | 20,000 | 50,000 |
| **Retention (30 дней)** | 30% | 40% | 50% | 60% |
| **Play Store Rating** | 4.2 | 4.5 | 4.7 | 4.8 |
| **Desktop пользователи** | 50 | 500 | 2,000 | 5,000 |

---

## Q1 2026 (Февраль - Апрель)

### 🎯 Главная цель: **Security Hardening + Desktop Link MVP**

### Февраль 2026

#### Неделя 1-2 (07.02 - 20.02): Критические security fixes

**Mobile Client:**
- [x] Заменить sqflite на sqflite_sqlcipher
- [x] Добавить Certificate Pinning
- [x] Argon2id вместо SHA-256 для PIN
- [x] TURN credentials через API с TTL
- [x] Sentry DSN в dart-define

**Backend:**
- [x] Удалить ADMIN_BYPASS_AUTH
- [x] Обязательная проверка ADMIN_SECRET
- [x] Добавить Rate Limiting (fastapi-limiter2)
- [x] Хешировать pubkey в логах
- [x] Реализовать `/api/public/releases` endpoint

**Релиз:** Mobile v1.1.3 (security update)

#### Неделя 3-4 (21.02 - 06.03): Доработки и тестирование

**Mobile Client:**
- [ ] Исправить биометрию (сохранение настройки)
- [ ] WebSocket auth (challenge-response)
- [ ] HTTP signaling с Ed25519 подписью
- [ ] CryptoService → singleton + zeroize keys

**Backend:**
- [ ] Шифрование FCM токенов в БД (AES-256)
- [ ] JWT для `/admin-reply`
- [ ] Alembic миграции БД

**Desktop:**
- [ ] ws:// → wss://
- [ ] Базовый CryptoService (X25519 + ChaCha20)
- [ ] Windows Credential Manager для ключей

**Релиз:** Mobile v1.2.0 (major security improvements)

---

### Март 2026

#### Неделя 1-2 (07.03 - 20.03): Desktop Link — Phase 1

**Desktop Client:**
- [ ] Реализовать полный CryptoService
- [ ] DatabaseService с SQLite + SQLCipher
- [ ] WebSocketService для real-time sync
- [ ] QR код с реальным публичным ключом (не random bytes)

**Mobile Client:**
- [ ] Desktop Link сервер (HTTP + WebSocket)
- [ ] Sync контактов с Desktop
- [ ] Sync сообщений с Desktop

**Тестирование:**
- [ ] E2E тесты для Desktop Link pairing
- [ ] Тестирование E2E шифрования между mobile и desktop

#### Неделя 3-4 (21.03 - 03.04): Desktop Link — Phase 2

**Desktop Client:**
- [ ] UI для чатов с реальными данными
- [ ] Отправка/получение сообщений
- [ ] Нотификации Windows
- [ ] Автозапуск с системой

**Mobile Client:**
- [ ] Desktop sessions management
- [ ] Revoke desktop access
- [ ] Multi-desktop support

**Релиз:** Desktop v0.5.0 (Desktop Link Beta)

---

### Апрель 2026

#### Неделя 1-2 (04.04 - 17.04): Полировка и оптимизация

**Mobile Client:**
- [ ] Применить HKDF после ECDH
- [ ] Ephemeral keys для сессий (Forward Secrecy)
- [ ] Индексы SQLite для производительности
- [ ] Рефакторинг main.dart (reduce God Object)

**Backend:**
- [ ] Prometheus метрики
- [ ] Structured logging (structlog)
- [ ] Circuit breaker для TRON/Firebase
- [ ] Graceful shutdown для WebSocket

**Desktop:**
- [ ] Полировка UI/UX
- [ ] Settings screen
- [ ] Themes support

#### Неделя 3-4 (18.04 - 30.04): Beta testing

**Тестирование:**
- [ ] Закрытое beta-тестирование Desktop (50 пользователей)
- [ ] Load testing Backend (WebSocket, payments)
- [ ] Security audit round 2
- [ ] Bug fixes

**Маркетинг:**
- [ ] Обновление сайта (Desktop Link announce)
- [ ] Видео-демо Desktop Link
- [ ] Статья в блоге

**Релиз:**
- Mobile v1.3.0 (криптографические улучшения)
- Desktop v0.8.0 (Desktop Link Beta ready)

---

### Q1 Итоги

✅ **Достижения:**
- Устранены все критические уязвимости Mobile
- Desktop Link feature завершена (MVP)
- Backend готов к масштабированию

📊 **Метрики:**
- Активные пользователи: 500+
- Desktop beta testers: 50+
- Security audit: PASS

---

## Q2 2026 (Май - Июль)

### 🎯 Главная цель: **Production Release + Growth**

### Май 2026

#### Неделя 1-2: Desktop Release Preparation

**Desktop Client:**
- [ ] Все критичные баги исправлены
- [ ] Unit тесты (70%+ coverage)
- [ ] Installer (MSIX package)
- [ ] Auto-update механизм

**Mobile Client:**
- [ ] Улучшения UI/UX на основе фидбека
- [ ] Оптимизация потребления батареи
- [ ] Offline mode improvements

**Backend:**
- [ ] Horizontal scaling (multi-node Redis)
- [ ] Database replication (PostgreSQL)
- [ ] Monitoring dashboard (Grafana)

#### Неделя 3-4: Public Release

**Релиз:**
- **Desktop v1.0.0** — Production ready
- **Mobile v1.4.0** — Stability improvements

**Маркетинг:**
- [ ] Press release (ProductHunt, Hacker News)
- [ ] YouTube review от инфлюенсеров
- [ ] Reddit AMA (r/privacy, r/selfhosted)
- [ ] Twitter/X кампания

---

### Июнь 2026

#### Фокус: **Rooms (Групповые чаты) + Notes Vault**

**Mobile Client:**
- [ ] Rooms UI overhaul (современный дизайн)
- [ ] Admin controls (kick, ban, permissions)
- [ ] Room invites (QR коды, ссылки)
- [ ] File sharing в rooms (до 50MB)

**Desktop Client:**
- [ ] Rooms support
- [ ] Sync с mobile

**Notes Vault:**
- [ ] Rich text editor (markdown support)
- [ ] Attachments (images, files)
- [ ] Tags и категории
- [ ] Full-text search

**Релиз:** Mobile v1.5.0, Desktop v1.1.0

---

### Июль 2026

#### Фокус: **Voice Messages + Media**

**Mobile Client:**
- [ ] Voice messages (запись и воспроизведение)
- [ ] Waveform visualization
- [ ] Voice-to-text (через AI Oracle)
- [ ] Image compression и превью
- [ ] Video messages (до 1 минуты)

**Backend:**
- [ ] Media storage optimization (S3-compatible)
- [ ] CDN integration для быстрой загрузки
- [ ] Thumbnail generation

**Desktop Client:**
- [ ] Voice messages playback
- [ ] Media viewer

**Релиз:** Mobile v1.6.0, Desktop v1.2.0

---

### Q2 Итоги

✅ **Достижения:**
- Desktop официально запущен
- Rooms и Notes Vault ready
- Voice messages support

📊 **Метрики:**
- Активные пользователи: 5,000+
- Desktop: 500+ активных пользователей
- Retention 30d: 40%+

---

## Q3 2026 (Август - Октябрь)

### 🎯 Главная цель: **iOS Version + Advanced Features**

### Август 2026

#### Фокус: **iOS Development Start**

**iOS Client:**
- [ ] Project setup (Swift + SwiftUI)
- [ ] CryptoService (порт с Android)
- [ ] DatabaseService (CoreData + SQLCipher)
- [ ] Basic UI (contacts, chats)

**Mobile (Android):**
- [ ] Улучшения производительности
- [ ] Material Design 3
- [ ] Темы и кастомизация

**Desktop:**
- [ ] macOS версия (из WinUI в Avalonia?)
- [ ] Linux поддержка (опционально)

---

### Сентябрь 2026

#### Фокус: **iOS Beta + Payments v2**

**iOS Client:**
- [ ] WebSocket + E2E encryption
- [ ] Desktop Link поддержка
- [ ] TestFlight beta (100 пользователей)

**Payments:**
- [ ] USDT TRC-20 support
- [ ] In-app purchases (подписки)
- [ ] Referral program (10% бонус)

**Oracle AI:**
- [ ] Voice input
- [ ] Context-aware responses
- [ ] Multi-language support

---

### Октябрь 2026

#### Фокус: **iOS Release + Enterprise Features**

**iOS Client:**
- [ ] App Store submission
- [ ] VoIP push notifications
- [ ] CallKit integration
- [ ] Full feature parity с Android

**Enterprise:**
- [ ] Self-hosted backend option
- [ ] LDAP/AD integration
- [ ] Advanced admin controls
- [ ] Audit logs export

**Релиз:** iOS v1.0.0

---

### Q3 Итоги

✅ **Достижения:**
- iOS версия запущена
- Payments v2 готов
- Enterprise features

📊 **Метрики:**
- Активные пользователи: 20,000+
- iOS: 2,000+ в первый месяц
- Retention 30d: 50%+

---

## Q4 2026 (Ноябрь - Декабрь)

### 🎯 Главная цель: **Scale + Advanced Security**

### Ноябрь 2026

#### Фокус: **WebRTC Groups + Advanced Crypto**

**Mobile (Android + iOS):**
- [ ] Group voice calls (до 8 человек)
- [ ] Group video calls (до 4 человек)
- [ ] Screen sharing (desktop)

**Crypto:**
- [ ] Double Ratchet Algorithm (Signal Protocol)
- [ ] Perfect Forward Secrecy для всех сообщений
- [ ] Post-quantum cryptography research

**Backend:**
- [ ] SFU (Selective Forwarding Unit) для group calls
- [ ] TURN server pooling

---

### Декабрь 2026

#### Фокус: **Year Review + 2027 Planning**

**Features:**
- [ ] Disappearing messages (self-destruct timer)
- [ ] Screenshot notifications
- [ ] Advanced duress mode (fake chats)
- [ ] Backup & restore (зашифрованный backup в cloud)

**Marketing:**
- [ ] Year in Review статья
- [ ] User testimonials
- [ ] Security audit результаты публикация
- [ ] 2027 Roadmap announcement

**Релиз:** Mobile v2.0.0, Desktop v2.0.0

---

### Q4 Итоги

✅ **Достижения:**
- Group calls готовы
- Advanced security features
- 50,000+ пользователей

📊 **Метрики:**
- Активные пользователи: 50,000+
- Desktop: 5,000+ активных
- iOS: 10,000+ активных
- Retention 30d: 60%+

---

## Метрики успеха

### Технические метрики

| Метрика | Q1 | Q2 | Q3 | Q4 | Цель 2026 |
|---------|----|----|----|----|-----------|
| **Uptime Backend** | 99.5% | 99.7% | 99.9% | 99.9% | 99.9% |
| **Avg Response Time** | <200ms | <150ms | <100ms | <100ms | <100ms |
| **Security Incidents** | 0 | 0 | 0 | 0 | 0 |
| **Test Coverage** | 60% | 70% | 80% | 85% | 80%+ |

### Пользовательские метрики

| Метрика | Q1 | Q2 | Q3 | Q4 |
|---------|----|----|----|----|
| **MAU (Monthly Active Users)** | 500 | 5K | 20K | 50K |
| **DAU/MAU Ratio** | 0.3 | 0.35 | 0.4 | 0.45 |
| **Retention Day 1** | 60% | 65% | 70% | 75% |
| **Retention Day 7** | 40% | 45% | 50% | 55% |
| **Retention Day 30** | 30% | 40% | 50% | 60% |
| **Avg Session Duration** | 5min | 7min | 10min | 12min |

### Бизнес метрики

| Метрика | Q1 | Q2 | Q3 | Q4 |
|---------|----|----|----|----|
| **Paying Users** | 10 | 100 | 500 | 1,500 |
| **ARPU (Average Revenue Per User)** | $5 | $8 | $10 | $12 |
| **MRR (Monthly Recurring Revenue)** | $50 | $800 | $5K | $18K |
| **CAC (Customer Acquisition Cost)** | $10 | $8 | $5 | $3 |
| **LTV/CAC Ratio** | 2:1 | 3:1 | 5:1 | 7:1 |

---

## Риски и митигация

### Технические риски

| Риск | Вероятность | Влияние | Митигация |
|------|------------|---------|-----------|
| **Критическая уязвимость найдена** | Средняя | Высокое | Регулярные security audits, bug bounty |
| **Backend не справляется с нагрузкой** | Низкая | Высокое | Horizontal scaling, load testing |
| **Desktop Link нестабилен** | Средняя | Среднее | Больше тестирования, beta период |
| **iOS approval отклонен** | Средняя | Среднее | Следовать guidelines, альтернативный релиз |

### Бизнес риски

| Риск | Вероятность | Влияние | Митигация |
|------|------------|---------|-----------|
| **Низкая user adoption** | Средняя | Высокое | Агрессивный маркетинг, referral program |
| **Конкуренция (Signal, Telegram)** | Высокая | Среднее | Фокус на unique features (AI, Desktop Link) |
| **Блокировка в странах** | Средняя | Среднее | Multi-host fallback, Tor support |
| **Проблемы с монетизацией** | Низкая | Среднее | Diversify (подписки, payments, enterprise) |

### Операционные риски

| Риск | Вероятность | Влияние | Митигация |
|------|------------|---------|-----------|
| **Потеря ключевого разработчика** | Низкая | Высокое | Documentation, knowledge sharing |
| **Инфраструктура проблемы** | Низкая | Среднее | Backup серверы, monitoring |
| **GDPR compliance issues** | Низкая | Высокое | Legal review, privacy by design |

---

## Долгосрочная vision (2027+)

### 2027: **Orpheus Ecosystem**

- **Orpheus Cloud:** Зашифрованное облачное хранилище (1TB за $5/мес)
- **Orpheus Business:** Enterprise version с advanced admin controls
- **Orpheus Web:** WebAssembly версия (работает в браузере)
- **Orpheus Protocol:** Open protocol для сторонних клиентов

### 2028: **Decentralization**

- **Federated servers:** Пользователи могут запустить свой сервер
- **P2P mode:** Direct connections без сервера
- **Blockchain integration:** Decentralized identity (DID)

### 2029: **AI Evolution**

- **Oracle 2.0:** Advanced AI с долгосрочной памятью
- **Smart Replies:** AI-generated responses
- **Translation:** Real-time перевод сообщений
- **Voice Synthesis:** AI voice для анонимности

---

## Заключение

Orpheus имеет **сильный потенциал** стать ведущим privacy-focused мессенджером.

**Ключевые факторы успеха:**
1. ✅ Уникальные features (Desktop Link, AI Oracle, Duress mode)
2. ✅ Zero-knowledge architecture
3. ✅ Open development и transparency
4. ⏳ Execution на этот roadmap

**Следующие шаги:**
1. Завершить Q1 2026 security fixes (февраль)
2. Запустить Desktop Link beta (март-апрель)
3. Подготовиться к production release (май)

**Let's build the future of secure messaging! 🚀**

---

*Roadmap v1.0 — Обновляется ежеквартально*
