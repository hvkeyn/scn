import 'dart:io';

import 'package:scn/models/remote_desktop_models.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector_stub.dart'
    if (dart.library.ffi) 'package:scn/services/remote_desktop/input_injector/input_injector_native.dart'
    as factory_;

/// Контракт инжектора ввода. Каждое событие [RemoteInputEvent] должно
/// мапиться на соответствующий нативный системный вызов.
///
/// Координаты x/y приходят нормализованными в диапазоне [0..1] относительно
/// активной поверхности захвата хоста; реализация конвертирует их в
/// абсолютные пиксели текущего экрана.
abstract class InputInjector {
  /// Включён ли инжектор. Если false — вызовы [inject] игнорируются.
  bool get isAvailable;

  /// Размер целевой поверхности в пикселях. Используется для конверсии
  /// нормализованных координат. Если `null` — считаем размер виртуального экрана.
  void setTargetSize(int width, int height);

  /// Применить событие. Реализация должна быть НЕ блокирующей (или быстрой).
  void inject(RemoteInputEvent event);

  /// Освободить нативные ресурсы (если есть).
  void dispose();
}

/// Создать платформо-специфичный инжектор. Вернёт безопасный noop-инжектор
/// для платформ, где нет реализации.
InputInjector createInputInjector() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return factory_.createNativeInjector();
  }
  return _NoopInjector();
}

class _NoopInjector implements InputInjector {
  @override
  bool get isAvailable => false;
  @override
  void setTargetSize(int width, int height) {}
  @override
  void inject(RemoteInputEvent event) {}
  @override
  void dispose() {}
}
