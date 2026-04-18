import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';

/// Заглушка для платформ без `dart:ffi` (web).
InputInjector createNativeInjector() => _StubInjector();

class _StubInjector implements InputInjector {
  @override
  bool get isAvailable => false;
  @override
  void setTargetSize(int width, int height) {}
  @override
  void inject(event) {}
  @override
  void dispose() {}
}
