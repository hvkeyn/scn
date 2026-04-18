import 'dart:io';

import 'package:scn/services/remote_desktop/input_injector/input_injector.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector_linux.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector_macos.dart';
import 'package:scn/services/remote_desktop/input_injector/input_injector_windows.dart';

InputInjector createNativeInjector() {
  if (Platform.isWindows) return WindowsInputInjector();
  if (Platform.isMacOS) return MacOsInputInjector();
  if (Platform.isLinux) return LinuxInputInjector();
  return _PlatformStub();
}

class _PlatformStub implements InputInjector {
  @override
  bool get isAvailable => false;
  @override
  void setTargetSize(int width, int height) {}
  @override
  void inject(event) {}
  @override
  void dispose() {}
}
