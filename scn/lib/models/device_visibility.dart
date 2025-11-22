/// Device visibility settings
enum DeviceVisibility {
  disabled,  // Отключено
  favorites, // Избранное
  enabled,   // Включено (Все)
}

extension DeviceVisibilityExtension on DeviceVisibility {
  String get displayName {
    switch (this) {
      case DeviceVisibility.disabled:
        return 'Отключено';
      case DeviceVisibility.favorites:
        return 'Избранное';
      case DeviceVisibility.enabled:
        return 'Включено';
    }
  }
}

