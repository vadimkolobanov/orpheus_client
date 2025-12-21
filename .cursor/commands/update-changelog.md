# Command: update-changelog (orpheus_client)

Цель: обновить `CHANGELOG.md` (Keep a Changelog) в секции `[Unreleased]`.

## Правила
- Пиши коротко и по делу.
- “Added/Changed/Fixed/Removed” — по смыслу.
- Не дублируй длинные технические детали (они идут в `AI_WORKLOG.md` и `docs/**`).

## Шаблон
- **Added**: что появилось (фича/экран/сервис)
- **Changed**: что изменилось в поведении/UX
- **Fixed**: что исправили
- **Removed**: что убрали
# Update CHANGELOG

Обнови `CHANGELOG.md` (только `## [Unreleased]`) на основе текущего diff:

- Добавь пункты в правильные секции: Added/Changed/Fixed/Removed
- Пиши коротко, пользовательским языком (не внутренние детали реализации)
- Не меняй уже выпущенные версии, если они появятся ниже


