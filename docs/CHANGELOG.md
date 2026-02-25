# Документация — История изменений

Этот файл отслеживает все изменения в документации проекта Orpheus Client.
Формат: Обратный хронологический порядок (новое первым).

---

## 2026-02-09 — Реструктуризация документации (v1.1.3 выпуск)

**Дата/Время**: 2026-02-09 20:35 UTC

**Что было сделано**:

### Удалены файлы (уже удалены из git, ссылки убраны из документации):
- `docs/COMMIT_PROCESS.md` — дублировался с `DEVELOPMENT_GUIDE.md`
- `docs/DOMAIN_MIGRATION_orpheus.click.md` — архивная миграция завершена
- `docs/RELEASES.md` — заменён на `ai_kb/11-release-history.md` (публичный вид)
- `docs/TESTING_GAPS.md` — слился с `docs/testing/README.md`

### Обновлены файлы:

1. **`docs/README.md`** (2026-02-09 20:34)
   - Убраны ссылки на удалённые файлы
   - Добавлена полная секция "База знаний AI" со всеми 11 файлами ai_kb/
   - Структурировано на три раздела: "Для разработчика", "База знаний AI", "Архив"
   - Уточнены ссылки на release notes (orpheus.click/changelog и ai_kb/11-release-history.md)

2. **`docs/DEVELOPMENT_GUIDE.md`** (2026-02-09 20:34)
   - Убрана ссылка на удалённый COMMIT_PROCESS.md
   - Заменена на прямое описание формата Conventional Commits в самом файле

3. **`docs/PHILOSOPHY.md`** (2026-02-09 20:34)
   - Убрана ссылка на удалённый RELEASES.md
   - Заменена на orpheus.click/changelog и ai_kb/11-release-history.md

4. **`docs/testing/TEST_CATALOG.md`** (2026-02-09 20:33)
   - Убрана ссылка на удалённый TESTING_GAPS.md
   - Заменена на docs/testing/README.md

5. **`docs/ai_kb/04-features.md`** (2026-02-09 20:20)
   - **Исправлена фактическая ошибка**: Rooms НЕ используют E2E шифрование
   - Убрано ложное утверждение "с E2E шифрованием"
   - Добавлено важное предупреждение: "сообщения в комнатах хранятся на сервере (не E2E)"

6. **`docs/ai_kb/11-release-history.md`** (2026-02-09 20:20)
   - **Исправлена фактическая ошибка**: Rooms в v1.1.3 и других версиях
   - Убрано "с E2E шифрованием" в двух местах (v1.1.3 и в summary в конце)
   - Добавлено уточнение: "(сообщения хранятся на сервере)"

7. **`docs/ai_kb/README.md`** (2026-02-09 20:33)
   - Добавлены 10-rooms.md и 11-release-history.md в список "Что загружать" в базу знаний AI
   - Убраны ссылки на удалённые файлы из секции "Что НЕ загружать"

### В секции `[Unreleased]` CHANGELOG.md (проекта):
- Добавлено: документация реструктурирована, фактические ошибки о Rooms исправлены

**В какой части проекта**: Вся документация (`docs/`)

**Результат проверки**:
- Все файлы последовательно обновлены
- Ссылки на удалённые файлы убраны (README.md, DEVELOPMENT_GUIDE.md, PHILOSOPHY.md, TEST_CATALOG.md)
- Фактические ошибки о Rooms исправлены в ai_kb
- Все 11 файлов ai_kb/ актуальны и готовы к загрузке в Knowledge Base

**Связанные файлы**:
- `docs/README.md` — точка входа в документацию
- `docs/DEVELOPMENT_GUIDE.md` — гайд для разработчиков
- `docs/PHILOSOPHY.md` — философия проекта
- `docs/testing/TEST_CATALOG.md` — каталог тестов
- `docs/ai_kb/` — вся папка (все 11 файлов)
- `CHANGELOG.md` (в корне проекта) — основной changelog приложения

---

## Структура документации (текущее состояние после 2026-02-09)

### Для разработчиков
- `docs/PROJECT_OVERVIEW.md` — обзор
- `docs/PROJECT_STRUCTURE.md` — структура файлов
- `docs/ARCHITECTURE.md` — архитектура
- `docs/DEVELOPMENT_GUIDE.md` — гайд для разработки
- `docs/PHILOSOPHY.md` — принципы и философия
- `docs/FUNCTIONAL_PRINCIPLES.md` — функциональные принципы
- `docs/FEATURES_AND_LIMITATIONS.md` — что работает/не работает
- `docs/SECURITY_REVIEW.md` — обзор безопасности (для разработчиков)
- `docs/testing/` — вся информация по тестированию
- `docs/DECISIONS/` — ADR (решения архитектуры)

### Для пользователей (AI Knowledge Base)
- `docs/ai_kb/01-what-is-orpheus.md` — что это такое
- `docs/ai_kb/02-getting-started.md` — быстрый старт
- `docs/ai_kb/03-privacy-security.md` — приватность и безопасность
- `docs/ai_kb/04-features.md` — возможности (ИСПРАВЛЕНЫ: Rooms без E2E)
- `docs/ai_kb/05-faq.md` — часто задаваемые вопросы
- `docs/ai_kb/06-troubleshooting.md` — решение проблем
- `docs/ai_kb/07-support-and-bug-report.md` — поддержка
- `docs/ai_kb/08-security-modes.md` — режимы безопасности
- `docs/ai_kb/09-system-screen.md` — экран системы
- `docs/ai_kb/10-rooms.md` — комнаты (групповые чаты)
- `docs/ai_kb/11-release-history.md` — история обновлений (ИСПРАВЛЕНЫ: Rooms без E2E)

### Архив
- `docs/_archive/` — старые/неактуальные документы
