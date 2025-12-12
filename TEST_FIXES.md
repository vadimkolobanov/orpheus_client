# Исправления тестов

## 1. DatabaseService: database_closed ✅

### Проблема
База данных закрывалась или не инициализировалась в тестах.

### Решение
- Добавлен метод `initWithDatabase(Database db)` в `DatabaseService` для инициализации с готовой БД
- Исправлен метод `close()` для корректного закрытия
- В `database_service_test.dart`:
  - Инициализация FFI в `setUpAll()`
  - Создание in-memory БД в `setUp()` для каждого теста
  - Инициализация сервиса через `initWithDatabase()`
  - Корректное закрытие в `tearDown()`

## 2. SoundService: MissingPluginException ✅

### Проблема
В unit-тестах нет реальных платформенных плагинов (audioplayers), поэтому вызовы MethodChannel падали.

### Решение
- Добавлены моки для MethodChannel `xyz.luan/audioplayers` в `sound_service_test.dart`
- Моки возвращают успешные ответы для всех методов плагина
- Моки устанавливаются в `setUp()` и очищаются в `tearDown()`

## 3. ContactsScreen: реальная БД вместо моков ✅

### Проблема
Виджет в тестах реально ходил в БД, ждал данных и упирался в таймаут.

### Решение
- Используется реальная in-memory БД с правильной инициализацией
- БД создается в `setUp()` для каждого теста
- DatabaseService инициализируется с тестовой БД через `initWithDatabase()`
- Тесты проверяют UI-логику с реальными данными из БД

## Запуск тестов

```bash
# Все тесты
flutter test

# Конкретные группы
flutter test test/services/database_service_test.dart
flutter test test/services/sound_service_test.dart
flutter test test/widgets/contacts_screen_test.dart
```

## Примечания

- Все тесты используют `sqflite_common_ffi` для работы с БД в памяти
- Моки для плагинов устанавливаются только в тестах, не влияют на продакшн код
- In-memory БД изолирована для каждого теста




