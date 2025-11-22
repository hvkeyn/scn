# Tech Context: LocalSend

## Технологический стек

### Frontend (UI)

- **Flutter** ^3.25.0
  - Кроссплатформенный UI фреймворк
  - Поддержка: Android, iOS, Windows, macOS, Linux, Web

- **Dart SDK** ^3.9.0
  - Язык программирования для Flutter

### Backend (Core Logic)

- **Rust** (Edition 2021)
  - Высокопроизводительная логика
  - HTTP сервер и клиент
  - Криптография
  - WebRTC

### State Management

- **Refena** 3.1.0
  - State management библиотека
  - Redux-подобный паттерн
  - Provider-based

### Ключевые зависимости Flutter

- **flutter_rust_bridge** 2.11.1 - мост между Flutter и Rust
- **routerino** 0.8.0 - навигация
- **slang** 4.9.0 - интернационализация
- **dart_mappable** 4.6.0 - сериализация
- **rhttp** 0.13.0 - HTTP клиент
- **connectivity_plus** 6.1.0 - проверка сетевого подключения
- **network_info_plus** 6.1.0 - информация о сети
- **permission_handler** 11.3.1 - управление разрешениями
- **file_picker** 8.1.4 - выбор файлов
- **path_provider** 2.1.5 - пути к системным директориям

### Ключевые зависимости Rust

#### Core библиотека
- **tokio** 1.46.1 - асинхронный runtime
- **hyper** 1.7.0 - HTTP библиотека
- **rustls** 0.23.32 - TLS реализация
- **reqwest** 0.12.23 - HTTP клиент
- **serde** 1.0.228 - сериализация
- **ed25519-dalek** 2.2.0 - криптография
- **webrtc** 0.13.0 - WebRTC поддержка

#### Server
- **axum** 0.8.1 - веб-фреймворк
- **tokio-cron-scheduler** 0.13.0 - планировщик задач

#### Flutter интеграция
- **flutter_rust_bridge** 2.11.1 - генерация биндингов

## Инструменты разработки

### Build Tools

- **build_runner** 2.7.1 - генерация кода
- **dart_mappable_builder** 4.6.0 - генерация мапперов
- **slang_build_runner** 4.9.0 - генерация локализаций
- **flutter_gen_runner** 5.12.0 - генерация assets

### Testing

- **test** ^1.26.2 - unit тесты
- **mockito** 5.5.0 - моки для тестов

### Linting

- **flutter_lints** 5.0.0 - линтер для Dart/Flutter
- **analysis_options.yaml** - правила анализа кода

## Настройка окружения

### Требования

1. **Flutter** 3.25.0 (рекомендуется через fvm)
2. **Rust** (последняя стабильная версия)
3. **Dart SDK** 3.9.0+

### Установка зависимостей

```bash
cd app
flutter pub get
flutter pub run build_runner build -d
```

### Запуск

```bash
cd app
flutter run
```

## Платформо-специфичные настройки

### Android

- **Min SDK**: 21 (Android 5.0)
- **Target SDK**: Современная версия
- **Gradle**: Настроен в `android/`
- **Permissions**: INTERNET, ACCESS_NETWORK_STATE, WRITE_EXTERNAL_STORAGE

### iOS

- **Min Version**: 12.0
- **Podfile**: Настроен в `ios/`
- **Permissions**: Local Network, Photo Library

### Windows

- **Min Version**: Windows 10
- **CMake**: Настроен в `windows/`
- **MSIX**: Поддержка для Microsoft Store

### macOS

- **Min Version**: 11 Big Sur
- **Xcode**: Требуется для сборки
- **App Store**: Поддержка через StoreKit

### Linux

- **Dependencies**: 
  - Gnome: `xdg-desktop-portal`, `xdg-desktop-portal-gtk`
  - KDE: `xdg-desktop-portal`, `xdg-desktop-portal-kde`
- **AppImage**: Поддержка через AppImageBuilder

## Сборка релизов

### Android

```bash
flutter build apk              # APK
flutter build appbundle        # App Bundle для Play Store
```

### iOS

```bash
flutter build ipa
```

### macOS

```bash
flutter build macos
```

### Windows

```bash
flutter build windows          # EXE
flutter pub run msix:create    # MSIX
```

### Linux

```bash
flutter build linux            # Стандартная сборка
appimage-builder --recipe AppImageBuilder.yml  # AppImage
```

## Конфигурация сети

### Порты

- **Основной порт**: 53317 (TCP, UDP)
- **Входящие**: TCP, UDP на порт 53317
- **Исходящие**: Любые порты

### Протоколы

- **HTTPS** - основной протокол передачи
- **Multicast DNS** - обнаружение устройств
- **WebRTC** - опционально для прямого соединения

## Интернационализация

- **Формат**: JSON файлы в `app/assets/i18n/`
- **Генерация**: `slang` package
- **Языки**: 106 поддерживаемых языков
- **Формат файлов**: `strings_<locale>.i18n.json`

## Безопасность

### Криптография

- **TLS/SSL**: rustls для безопасного соединения
- **Сертификаты**: самоподписанные, генерируемые на лету
- **Аутентификация**: токены для валидации запросов
- **Хеширование**: SHA-2 для проверки целостности

### Практики безопасности

- Проверка сертификатов получателя
- Валидация токенов перед передачей
- Шифрование всех данных в транзите
- Безопасное хранение настроек

## Производительность

### Оптимизации

- **Isolates** - изоляция тяжелых операций
- **Streaming** - потоковая передача файлов
- **Rust core** - высокопроизводительная логика
- **Lazy loading** - загрузка по требованию

### Мониторинг

- Логирование через `tracing` в Rust
- Логирование через `logging` в Dart
- Debug страницы для мониторинга сети

