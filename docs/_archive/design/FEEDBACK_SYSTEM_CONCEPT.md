# Концепт: Чат с разработчиком (Orpheus Support Chat)

> **Дата**: Январь 2026  
> **Статус**: ✅ РЕАЛИЗОВАНО  
> **Версия**: 2.0 — Постоянный чат с разработчиком

---

## 1. Ключевая идея

### ❌ НЕ делаем (тикетная система)
- Создать обращение → Ждать → Закрыть
- Темы, статусы, приоритеты
- "Ваш тикет #42 принят"

### ✅ Делаем (постоянный чат)
- У каждого пользователя **один чат** с разработчиком
- Чат **всегда открыт** — просто пиши
- Кнопка **"Отправить логи"** прямо в чате
- Разработчик видит все чаты в админке и отвечает

> **Аналогия**: Как личный чат в Telegram с поддержкой. Один диалог, история сохраняется, пиши когда хочешь.

---

## 2. Архитектура

### 2.1 Общая схема

```
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│  КЛИЕНТ         │         │  БЭКЕНД         │         │  АДМИНКА        │
│  (Flutter)      │         │  (orpheus)      │         │  (OPHEUS_ADMIN) │
├─────────────────┤         ├─────────────────┤         ├─────────────────┤
│ SupportChat     │◀───────▶│ support_messages│◀───────▶│ SupportRouter   │
│ Screen          │  WS/HTTP│ client_logs     │   API   │ ChatListUI      │
│                 │         │                 │         │ ChatViewUI      │
└─────────────────┘         └─────────────────┘         └─────────────────┘
```

### 2.2 Таблицы БД (упрощённые)

```sql
-- Сообщения чата поддержки (все пользователи в одной таблице)
CREATE TABLE support_messages (
    id SERIAL PRIMARY KEY,
    pubkey VARCHAR(255) NOT NULL,           -- ID пользователя (= ID чата)
    direction VARCHAR(10) NOT NULL,         -- 'user' или 'admin'
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    is_read BOOLEAN DEFAULT FALSE           -- Прочитано ли (для уведомлений)
);
CREATE INDEX idx_support_messages_pubkey ON support_messages(pubkey);
CREATE INDEX idx_support_messages_created ON support_messages(created_at);

-- Debug-логи от клиентов
CREATE TABLE client_debug_logs (
    id SERIAL PRIMARY KEY,
    pubkey VARCHAR(255) NOT NULL,
    log_data TEXT NOT NULL,                 -- Экспортированные логи
    app_version VARCHAR(50),
    device_info TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_client_logs_pubkey ON client_debug_logs(pubkey);
CREATE INDEX idx_client_logs_created ON client_debug_logs(created_at);
```

> **Примечание**: Нет таблицы tickets! Один pubkey = один чат. История вечная.

---

## 3. Клиент (Flutter)

### 3.1 Новый экран: SupportChatScreen

```
┌──────────────────────────────────────┐
│ ← ЧАТ С РАЗРАБОТЧИКОМ                │
├──────────────────────────────────────┤
│                                      │
│       ┌────────────────────────────┐ │
│ 14:32 │ Привет! У меня проблема со │ │
│   Вы  │ звонками, обрываются...    │ │
│       └────────────────────────────┘ │
│                                      │
│ ┌────────────────────────────────┐   │
│ │ Привет! Можешь отправить логи? │   │
│ │ Посмотрю что происходит.       │ 15:10
│ └────────────────────────────────┘ Разр.
│                                      │
│       ┌────────────────────────────┐ │
│ 15:12 │ 📎 Debug-логи отправлены   │ │
│   Вы  │ (312 записей)              │ │
│       └────────────────────────────┘ │
│                                      │
│ ┌────────────────────────────────┐   │
│ │ Вижу! Проблема в TURN сервере. │   │
│ │ Исправим в след. обновлении.   │ 15:45
│ └────────────────────────────────┘ Разр.
│                                      │
├──────────────────────────────────────┤
│ [Сообщение...]           [📎] [➤]   │
└──────────────────────────────────────┘

[📎] — кнопка "Отправить логи"
[➤]  — отправить сообщение
```

### 3.2 Новые файлы

```
lib/
  screens/
    support_chat_screen.dart    # Экран чата с разработчиком
  services/
    support_chat_service.dart   # Сервис для работы с чатом

test/
  services/
    support_chat_service_test.dart
  widgets/
    support_chat_screen_test.dart
```

### 3.3 SupportChatService

```dart
class SupportChatService {
  static final instance = SupportChatService._();
  SupportChatService._();
  
  // Локальный кеш сообщений
  final List<SupportMessage> _messages = [];
  List<SupportMessage> get messages => List.unmodifiable(_messages);
  
  // Stream для UI
  final _messagesController = StreamController<List<SupportMessage>>.broadcast();
  Stream<List<SupportMessage>> get messagesStream => _messagesController.stream;
  
  // Счётчик непрочитанных (ответы от разработчика)
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  
  /// Загрузить историю чата
  Future<void> loadHistory() async {
    // GET /api/support/messages
  }
  
  /// Отправить сообщение
  Future<void> sendMessage(String text) async {
    // POST /api/support/message
    // или через WebSocket: {"type": "support-msg", "text": "..."}
  }
  
  /// Отправить debug-логи
  Future<void> sendLogs() async {
    final logsText = DebugLogger.exportToText();
    final deviceInfo = await _getDeviceInfo();
    
    // POST /api/support/logs
    // В чате появится системное сообщение "📎 Debug-логи отправлены"
  }
  
  /// Обработка входящего сообщения от разработчика
  void _onAdminMessage(Map<String, dynamic> data) {
    final msg = SupportMessage.fromJson(data);
    _messages.add(msg);
    _unreadCount++;
    _messagesController.add(_messages);
  }
}
```

### 3.4 Модель сообщения

```dart
enum MessageDirection { user, admin }

class SupportMessage {
  final int id;
  final MessageDirection direction;
  final String text;
  final DateTime createdAt;
  final bool isLogsAttachment;  // Системное сообщение о логах
  
  SupportMessage({
    required this.id,
    required this.direction,
    required this.text,
    required this.createdAt,
    this.isLogsAttachment = false,
  });
}
```

### 3.5 Интеграция в Settings

```dart
// lib/screens/settings_screen.dart

ListTile(
  leading: const Icon(Icons.support_agent, color: Colors.white70),
  title: const Text('Написать разработчику'),
  subtitle: const Text('Вопросы, проблемы, предложения'),
  trailing: _unreadCount > 0 
    ? Badge(label: Text('$_unreadCount')) 
    : null,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SupportChatScreen()),
  ),
),
```

---

## 4. Бэкенд (orpheus)

### 4.1 Новые endpoints

```python
# === SUPPORT CHAT API ===

class SupportMessageCreate(BaseModel):
    text: str

class SupportLogsCreate(BaseModel):
    logs_data: str  # До 500KB
    app_version: Optional[str] = None
    device_info: Optional[str] = None


@app.get("/api/support/messages")
async def get_support_messages(
    x_pubkey: str = Header(...),
    limit: int = Query(100, le=500),
    before_id: Optional[int] = None,  # Для пагинации
):
    """Получить историю чата"""
    query = support_messages.select().where(
        support_messages.c.pubkey == x_pubkey
    ).order_by(support_messages.c.id.desc()).limit(limit)
    
    if before_id:
        query = query.where(support_messages.c.id < before_id)
    
    messages = await database.fetch_all(query)
    
    # Помечаем сообщения от админа как прочитанные
    await database.execute(
        support_messages.update()
        .where(support_messages.c.pubkey == x_pubkey)
        .where(support_messages.c.direction == 'admin')
        .values(is_read=True)
    )
    
    return {"messages": [dict(m) for m in reversed(messages)]}


@app.post("/api/support/message")
async def send_support_message(
    request: SupportMessageCreate,
    x_pubkey: str = Header(...),
):
    """Отправить сообщение в чат поддержки"""
    
    if len(request.text) > 5000:
        raise HTTPException(400, "Сообщение слишком длинное (макс. 5000 символов)")
    
    msg_id = await database.execute(
        support_messages.insert().values(
            pubkey=x_pubkey,
            direction='user',
            message=request.text,
            created_at=datetime.utcnow(),
        )
    )
    
    await log_event("SUPPORT", "Новое сообщение от пользователя", 
                    pubkey=x_pubkey, details={"msg_id": msg_id})
    
    return {"id": msg_id, "status": "sent"}


@app.post("/api/support/logs")
async def send_support_logs(
    request: SupportLogsCreate,
    x_pubkey: str = Header(...),
):
    """Отправить debug-логи"""
    
    if len(request.logs_data) > 500_000:
        raise HTTPException(400, "Логи слишком большие (макс. 500KB)")
    
    # Сохраняем логи
    log_id = await database.execute(
        client_debug_logs.insert().values(
            pubkey=x_pubkey,
            log_data=request.logs_data,
            app_version=request.app_version,
            device_info=request.device_info,
            created_at=datetime.utcnow(),
        )
    )
    
    # Добавляем системное сообщение в чат
    lines_count = request.logs_data.count('\n')
    await database.execute(
        support_messages.insert().values(
            pubkey=x_pubkey,
            direction='user',
            message=f"📎 Debug-логи отправлены ({lines_count} записей)",
            created_at=datetime.utcnow(),
        )
    )
    
    await log_event("SUPPORT", "Получены debug-логи", 
                    pubkey=x_pubkey, details={"log_id": log_id, "size": len(request.logs_data)})
    
    return {"log_id": log_id, "status": "received"}
```

### 4.2 WebSocket для real-time (опционально)

```python
# В websocket_endpoint добавить обработку

if msg_type == "support-msg":
    # Сохраняем сообщение в БД
    text = message.get("text", "")
    if text and len(text) <= 5000:
        await database.execute(
            support_messages.insert().values(
                pubkey=pubkey,
                direction='user',
                message=text,
                created_at=datetime.utcnow(),
            )
        )

# Для отправки ответа от админа (через Redis pub/sub или polling)
if msg_type == "support-reply":
    # Приходит когда админ ответил
    pass
```

---

## 5. Админка (OPHEUS_ADMIN)

### 5.1 Новый роутер: support.py

```python
router = APIRouter(prefix="/api/support", tags=["support"])


@router.get("/chats")
async def get_support_chats(
    current_admin = Depends(get_current_active_admin),
    has_unread: Optional[bool] = None,
):
    """Список всех чатов (уникальные pubkey с последним сообщением)"""
    
    # Подзапрос: последнее сообщение для каждого pubkey
    query = """
        SELECT DISTINCT ON (pubkey) 
            pubkey,
            message as last_message,
            direction as last_direction,
            created_at as last_message_at,
            (SELECT COUNT(*) FROM support_messages sm2 
             WHERE sm2.pubkey = sm.pubkey 
             AND sm2.direction = 'user' 
             AND sm2.is_read = FALSE) as unread_count
        FROM support_messages sm
        ORDER BY pubkey, created_at DESC
    """
    
    chats = await database.fetch_all(query)
    return {"chats": [dict(c) for c in chats]}


@router.get("/chats/{pubkey}")
async def get_chat_messages(
    pubkey: str,
    current_admin = Depends(get_current_active_admin),
    limit: int = Query(100, le=500),
):
    """Получить сообщения конкретного чата"""
    
    messages = await database.fetch_all(
        support_messages.select()
        .where(support_messages.c.pubkey == pubkey)
        .order_by(support_messages.c.id.desc())
        .limit(limit)
    )
    
    # Помечаем как прочитанные
    await database.execute(
        support_messages.update()
        .where(support_messages.c.pubkey == pubkey)
        .where(support_messages.c.direction == 'user')
        .values(is_read=True)
    )
    
    return {"messages": [dict(m) for m in reversed(messages)]}


@router.post("/chats/{pubkey}/reply")
async def reply_to_chat(
    pubkey: str,
    request: AdminReplyRequest,
    current_admin = Depends(get_current_active_admin),
):
    """Ответить пользователю"""
    
    msg_id = await database.execute(
        support_messages.insert().values(
            pubkey=pubkey,
            direction='admin',
            message=request.text,
            created_at=datetime.utcnow(),
            is_read=False,
        )
    )
    
    # Попытка отправить через WebSocket если пользователь онлайн
    if pubkey in manager.active_connections:
        await manager.send_personal_message({
            "type": "support-reply",
            "text": request.text,
            "created_at": datetime.utcnow().isoformat(),
        }, pubkey)
    
    return {"id": msg_id, "status": "sent"}


@router.get("/chats/{pubkey}/logs")
async def get_user_logs(
    pubkey: str,
    current_admin = Depends(get_current_active_admin),
    limit: int = Query(10, le=50),
):
    """Получить debug-логи пользователя"""
    
    logs = await database.fetch_all(
        client_debug_logs.select()
        .where(client_debug_logs.c.pubkey == pubkey)
        .order_by(client_debug_logs.c.id.desc())
        .limit(limit)
    )
    
    return {"logs": [dict(l) for l in logs]}
```

### 5.2 UI шаблоны

```
app/templates/support/
  chats_list.html      # Список всех чатов (pubkey + последнее сообщение)
  chat_view.html       # Конкретный чат + форма ответа
  logs_modal.html      # Модальное окно с debug-логами
```

### 5.3 UI чата в админке (концепт)

```
┌─────────────────────────────────────────────────────────────────┐
│ ЧАТЫ ПОДДЕРЖКИ                                    [🔄 Обновить] │
├────────────────────────────┬────────────────────────────────────┤
│ ▼ НЕПРОЧИТАННЫЕ (2)        │                                    │
│ ┌────────────────────────┐ │  ← 7abc12f...                      │
│ │ 🔴 7abc12f...          │ │                                    │
│ │ "Не работают звонки"   │ │  ┌──────────────────────────────┐  │
│ │ 5 мин назад            │ │  │ Не работают звонки через    │  │
│ └────────────────────────┘ │  │ WiFi уже второй день         │  │
│ ┌────────────────────────┐ │  └──────────────────────────────┘  │
│ │ 🔴 9def45a...          │ │  14:32 • Пользователь              │
│ │ "📎 Логи отправлены"   │ │                                    │
│ │ 12 мин назад           │ │  ┌──────────────────────────────┐  │
│ └────────────────────────┘ │  │ 📎 Debug-логи (247 записей)  │  │
│                            │  │ [👁 Посмотреть логи]          │  │
│ ▼ ВСЕ ЧАТЫ                 │  └──────────────────────────────┘  │
│ ┌────────────────────────┐ │  14:35 • Пользователь              │
│ │ ⚪ 3ghi78b...          │ │                                    │
│ │ "Спасибо, работает!"   │ │  ────────────────────────────────  │
│ │ вчера                  │ │                                    │
│ └────────────────────────┘ │  [Ваш ответ...]          [Отправить]
│                            │                                    │
└────────────────────────────┴────────────────────────────────────┘
```

---

## 6. WebSocket типы сообщений

```json
// Пользователь → Сервер: отправка сообщения
{"type": "support-msg", "text": "Привет, у меня проблема..."}

// Сервер → Пользователь: ответ от разработчика
{
    "type": "support-reply", 
    "text": "Привет! Опиши подробнее...",
    "created_at": "2026-01-04T15:30:00Z"
}

// Сервер → Пользователь: подтверждение отправки логов
{
    "type": "support-logs-received",
    "log_id": 123,
    "lines_count": 247
}
```

---

## 7. План реализации

### Фаза 1: Бэкенд (orpheus) — 1-2 дня
- [ ] Создать таблицы `support_messages`, `client_debug_logs`
- [ ] API: GET/POST messages, POST logs
- [ ] WebSocket обработка `support-msg`
- [ ] Автоочистка логов старше 30 дней

### Фаза 2: Админка (OPHEUS_ADMIN) — 2 дня
- [ ] Роутер `support.py`
- [ ] UI: список чатов
- [ ] UI: просмотр чата + ответ
- [ ] UI: просмотр debug-логов

### Фаза 3: Клиент (orpheus_client) — 2-3 дня
- [ ] `SupportChatService`
- [ ] `SupportChatScreen`
- [ ] Кнопка "📎 Отправить логи"
- [ ] Интеграция в Settings
- [ ] Тесты

### Фаза 4: Тестирование — 1 день
- [ ] E2E: отправка сообщения, получение ответа
- [ ] E2E: отправка логов, просмотр в админке

**Итого: ~6-8 дней**

---

## 8. Преимущества нового подхода

| Аспект | Тикетная система | Постоянный чат |
|--------|------------------|----------------|
| UX | Сложный (создать → закрыть) | Простой (просто пиши) |
| Код | Больше (статусы, приоритеты) | Меньше |
| БД | 3 таблицы | 2 таблицы |
| Время реализации | 10-12 дней | 6-8 дней |
| Поддержка | Формальная | Дружественная |

---

## 9. Открытые вопросы

1. **Push-уведомления** о новом сообщении от разработчика?
2. **Уведомления админу** о новых сообщениях (email/Telegram)?
3. **Хранение истории**: вечно или N дней?

---

## 10. Заключение

Новый концепт:
- ✅ Проще для пользователя (один чат, всегда открыт)
- ✅ Проще в реализации (меньше сущностей)
- ✅ Кнопка "Отправить логи" прямо в чате
- ✅ Разработчик видит все чаты в одном месте
- ✅ Дружественная коммуникация вместо формальных тикетов
