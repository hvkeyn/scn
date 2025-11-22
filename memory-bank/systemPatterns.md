# System Patterns: LocalSend

## Архитектура системы

LocalSend использует гибридную архитектуру с разделением на несколько компонентов:

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (UI)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  Pages   │  │ Providers│  │  Widgets │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└────────────────────┬────────────────────────────────────┘
                     │ Flutter Rust Bridge
┌────────────────────▼────────────────────────────────────┐
│              Rust Library (app/rust/)                    │
│  ┌──────────────────────────────────────────┐           │
│  │  HTTP Server, Discovery, File Transfer   │           │
│  └──────────────────────────────────────────┘           │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│              Core Library (core/)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │  HTTP    │  │  Crypto  │  │  WebRTC  │              │
│  └──────────┘  └──────────┘  └──────────┘              │
└─────────────────────────────────────────────────────────┘
```

## Структура проекта

### Основные компоненты

1. **app/** - Flutter приложение
   - `lib/pages/` - экраны приложения
   - `lib/provider/` - state management (Refena)
   - `lib/widget/` - переиспользуемые виджеты
   - `lib/util/` - утилиты
   - `lib/rust/` - сгенерированные биндинги для Rust
   - `rust/` - Rust код, интегрированный в Flutter

2. **core/** - Rust core библиотека
   - `src/http/` - HTTP клиент и сервер
   - `src/crypto/` - криптография (сертификаты, токены)
   - `src/webrtc/` - WebRTC поддержка
   - `src/model/` - модели данных

3. **server/** - Отдельный Rust сервер (Axum)
   - WebSocket поддержка
   - REST API endpoints

4. **common/** - Общий Dart код
   - Модели данных
   - API route builder
   - Isolate utilities

5. **cli/** - CLI инструмент на Dart

## Паттерны проектирования

### State Management

Используется **Refena** для state management:

```dart
// Provider pattern
final settingsProvider = ReduxNotifier<SettingsState, SettingsAction>(
  (state, action) => state.copyWith(...)
);

// Использование
final settings = ref.watch(settingsProvider);
ref.redux(settingsProvider).dispatch(UpdateAction(...));
```

### Архитектура страниц

- **Pages** - основные экраны
- **Controllers** - логика управления состоянием страниц
- **ViewModels** - преобразование данных для отображения
- **Tabs** - вкладки внутри главной страницы

### Коммуникация Flutter ↔ Rust

Используется **flutter_rust_bridge**:

1. Rust функции экспортируются через FFI
2. Генерируются Dart биндинги
3. Асинхронные вызовы через Future

### Сетевое взаимодействие

1. **Discovery** - multicast DNS для обнаружения устройств
2. **HTTP Server** - встроенный HTTPS сервер на Rust
3. **HTTP Client** - клиент для отправки запросов
4. **WebRTC** - опционально для прямого соединения

### Обработка файлов

- **CrossFile** - абстракция для работы с файлами на разных платформах
- **Streaming** - потоковая передача больших файлов
- **Progress tracking** - отслеживание прогресса через providers

## Ключевые технические решения

### Безопасность

- **TLS/SSL** - самоподписанные сертификаты, генерируемые на лету
- **Token-based auth** - токены для аутентификации запросов
- **Certificate pinning** - проверка сертификатов получателя

### Производительность

- **Isolates** - изоляция тяжелых операций
- **Streaming** - потоковая передача без загрузки в память
- **Rust core** - высокопроизводительная логика на Rust

### Кроссплатформенность

- **Flutter** - единый UI код для всех платформ
- **Platform channels** - нативные функции через method channels
- **Conditional compilation** - платформо-специфичный код

## Структура данных

### Модели

- **Device** - информация об устройстве
- **File** - метаданные файла
- **Transfer** - состояние передачи
- **Settings** - настройки приложения

### Персистентность

- **SharedPreferences** - простые настройки
- **Hive/Isar** - сложные структуры данных (если используется)
- **File system** - сохранение полученных файлов

## API Design

### REST API (v2, v3)

- `POST /api/v2/info` - информация об устройстве
- `POST /api/v2/send` - отправка файлов
- `POST /api/v2/receive` - получение файлов
- `GET /api/v2/register` - регистрация для получения

### WebSocket API

- `/v1/ws` - WebSocket соединение для real-time коммуникации

## Обработка ошибок

- **Result types** - использование Result<T, E> в Rust
- **Exception handling** - try-catch в Dart
- **Error providers** - централизованная обработка ошибок
- **User feedback** - показ ошибок пользователю через SnackBar

