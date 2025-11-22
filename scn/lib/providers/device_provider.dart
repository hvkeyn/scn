import 'package:flutter/foundation.dart';
import 'package:scn/models/device.dart';

/// Provider for managing discovered devices
class DeviceProvider extends ChangeNotifier {
  final List<Device> _devices = [];
  final Map<String, Device> _deviceMap = {};
  
  List<Device> get devices => List.unmodifiable(_devices);
  
  void addDevice(Device device) {
    if (_deviceMap.containsKey(device.id)) {
      // Update existing device
      final index = _devices.indexWhere((d) => d.id == device.id);
      if (index != -1) {
        _devices[index] = device;
        _deviceMap[device.id] = device;
        notifyListeners();
      }
    } else {
      // Add new device
      _devices.add(device);
      _deviceMap[device.id] = device;
      notifyListeners();
    }
  }
  
  void removeDevice(String deviceId) {
    if (_deviceMap.containsKey(deviceId)) {
      _devices.removeWhere((d) => d.id == deviceId);
      _deviceMap.remove(deviceId);
      notifyListeners();
    }
  }
  
  void clearDevices() {
    _devices.clear();
    _deviceMap.clear();
    notifyListeners();
  }
  
  Device? getDevice(String deviceId) => _deviceMap[deviceId];
}

