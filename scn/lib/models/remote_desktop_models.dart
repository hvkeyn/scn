import 'dart:convert';

/// Текущий статус удалённой desktop-сессии.
enum RemoteDesktopSessionStatus {
  /// Сессия только что создана, ждём согласия хоста.
  pendingApproval,

  /// Хост согласовал, идёт обмен SDP/ICE.
  negotiating,

  /// Видео/аудио потоки активны.
  streaming,

  /// Сессия закрыта корректно.
  closed,

  /// Сессия отклонена хостом или пользователем.
  rejected,

  /// Ошибка в процессе.
  failed,
}

/// Роль текущего устройства в RD-сессии.
enum RemoteDesktopRole {
  host, // отдаёт экран
  viewer, // смотрит и/или управляет
}

/// Способ авторизации, по которому viewer был допущен.
enum RemoteDesktopAuthMode {
  /// Хост явно подтвердил подключение в диалоге.
  prompt,

  /// Viewer ввёл правильный пароль.
  password,

  /// Хост ранее добавил viewer в "trusted" peers.
  trusted,
}

/// Состояние входной плоскости (можно ли управлять).
enum RemoteDesktopInputMode {
  /// Полное управление (мышь + клавиатура).
  full,

  /// Только просмотр.
  viewOnly,
}

/// Тип события ввода, передаваемого по DataChannel.
enum RemoteInputEventKind {
  mouseMove,
  mouseDown,
  mouseUp,
  mouseScroll,
  keyDown,
  keyUp,
  textInput,
}

/// Кнопка мыши.
enum RemoteMouseButton { left, right, middle, x1, x2 }

/// Сериализуемое событие ввода с viewer на host.
class RemoteInputEvent {
  final RemoteInputEventKind kind;

  /// Нормализованные координаты [0..1] относительно области экрана хоста.
  final double? x;
  final double? y;

  /// Дельта прокрутки колеса.
  final double? scrollDeltaX;
  final double? scrollDeltaY;

  /// Кнопка для mouseDown/mouseUp.
  final RemoteMouseButton? button;

  /// Логический keycode (Flutter LogicalKeyboardKey.keyId).
  final int? keyCode;

  /// Физический keycode (USB HID).
  final int? physicalKeyCode;

  /// Введённый текст (для IME / charcode).
  final String? text;

  /// Модификаторы.
  final bool shift;
  final bool ctrl;
  final bool alt;
  final bool meta;

  /// Время на стороне отправителя в микросекундах.
  final int timestampUs;

  const RemoteInputEvent({
    required this.kind,
    this.x,
    this.y,
    this.scrollDeltaX,
    this.scrollDeltaY,
    this.button,
    this.keyCode,
    this.physicalKeyCode,
    this.text,
    this.shift = false,
    this.ctrl = false,
    this.alt = false,
    this.meta = false,
    required this.timestampUs,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (scrollDeltaX != null) 'sdx': scrollDeltaX,
        if (scrollDeltaY != null) 'sdy': scrollDeltaY,
        if (button != null) 'btn': button!.name,
        if (keyCode != null) 'kc': keyCode,
        if (physicalKeyCode != null) 'pkc': physicalKeyCode,
        if (text != null) 'tx': text,
        if (shift) 'sh': true,
        if (ctrl) 'ct': true,
        if (alt) 'al': true,
        if (meta) 'mt': true,
        'ts': timestampUs,
      };

  String toJsonString() => jsonEncode(toJson());

  factory RemoteInputEvent.fromJson(Map<String, dynamic> json) {
    return RemoteInputEvent(
      kind: RemoteInputEventKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => RemoteInputEventKind.mouseMove,
      ),
      x: (json['x'] as num?)?.toDouble(),
      y: (json['y'] as num?)?.toDouble(),
      scrollDeltaX: (json['sdx'] as num?)?.toDouble(),
      scrollDeltaY: (json['sdy'] as num?)?.toDouble(),
      button: json['btn'] != null
          ? RemoteMouseButton.values.firstWhere(
              (b) => b.name == json['btn'],
              orElse: () => RemoteMouseButton.left,
            )
          : null,
      keyCode: (json['kc'] as num?)?.toInt(),
      physicalKeyCode: (json['pkc'] as num?)?.toInt(),
      text: json['tx'] as String?,
      shift: json['sh'] == true,
      ctrl: json['ct'] == true,
      alt: json['al'] == true,
      meta: json['mt'] == true,
      timestampUs: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Запрос на разрешение от удалённого viewer'а.
class RemoteDesktopPermissionRequest {
  final String sessionId;
  final String viewerDeviceId;
  final String viewerAlias;
  final String viewerAddress;
  final RemoteDesktopAuthMode requestedMode;
  final bool wantsControl;
  final DateTime requestedAt;

  const RemoteDesktopPermissionRequest({
    required this.sessionId,
    required this.viewerDeviceId,
    required this.viewerAlias,
    required this.viewerAddress,
    required this.requestedMode,
    required this.wantsControl,
    required this.requestedAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'viewerDeviceId': viewerDeviceId,
        'viewerAlias': viewerAlias,
        'viewerAddress': viewerAddress,
        'requestedMode': requestedMode.name,
        'wantsControl': wantsControl,
        'requestedAt': requestedAt.toIso8601String(),
      };

  factory RemoteDesktopPermissionRequest.fromJson(Map<String, dynamic> json) {
    return RemoteDesktopPermissionRequest(
      sessionId: json['sessionId'] as String,
      viewerDeviceId: json['viewerDeviceId'] as String,
      viewerAlias: json['viewerAlias'] as String? ?? 'Unknown',
      viewerAddress: json['viewerAddress'] as String? ?? '',
      requestedMode: RemoteDesktopAuthMode.values.firstWhere(
        (m) => m.name == json['requestedMode'],
        orElse: () => RemoteDesktopAuthMode.prompt,
      ),
      wantsControl: json['wantsControl'] as bool? ?? false,
      requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Состояние одной сессии (одинаковое и на host'е, и на viewer'е).
class RemoteDesktopSession {
  final String sessionId;
  final RemoteDesktopRole role;

  /// Идентификатор второй стороны.
  final String peerId;
  final String peerAlias;
  final String peerAddress;
  final int peerPort;

  final RemoteDesktopSessionStatus status;
  final RemoteDesktopAuthMode authMode;
  final RemoteDesktopInputMode inputMode;

  /// Включён ли захват аудио.
  final bool audioEnabled;

  /// Битрейт видео (kbps), 0 = авто.
  final int videoBitrateKbps;

  /// Целевой FPS, 0 = авто.
  final int targetFps;

  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? errorMessage;

  /// Текущая статистика (заполняется в runtime).
  final RemoteDesktopStats? stats;

  const RemoteDesktopSession({
    required this.sessionId,
    required this.role,
    required this.peerId,
    required this.peerAlias,
    required this.peerAddress,
    required this.peerPort,
    required this.status,
    required this.authMode,
    this.inputMode = RemoteDesktopInputMode.viewOnly,
    this.audioEnabled = false,
    this.videoBitrateKbps = 0,
    this.targetFps = 0,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.errorMessage,
    this.stats,
  });

  RemoteDesktopSession copyWith({
    RemoteDesktopSessionStatus? status,
    RemoteDesktopAuthMode? authMode,
    RemoteDesktopInputMode? inputMode,
    bool? audioEnabled,
    int? videoBitrateKbps,
    int? targetFps,
    DateTime? startedAt,
    DateTime? endedAt,
    String? errorMessage,
    RemoteDesktopStats? stats,
  }) {
    return RemoteDesktopSession(
      sessionId: sessionId,
      role: role,
      peerId: peerId,
      peerAlias: peerAlias,
      peerAddress: peerAddress,
      peerPort: peerPort,
      status: status ?? this.status,
      authMode: authMode ?? this.authMode,
      inputMode: inputMode ?? this.inputMode,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
      targetFps: targetFps ?? this.targetFps,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      stats: stats ?? this.stats,
    );
  }
}

/// Live-статистика для UI (битрейт, потеря, framerate).
class RemoteDesktopStats {
  final double videoBitrateKbps;
  final double audioBitrateKbps;
  final double framesPerSecond;
  final int packetsLost;
  final int roundTripTimeMs;
  final int frameWidth;
  final int frameHeight;
  final DateTime updatedAt;

  const RemoteDesktopStats({
    this.videoBitrateKbps = 0,
    this.audioBitrateKbps = 0,
    this.framesPerSecond = 0,
    this.packetsLost = 0,
    this.roundTripTimeMs = 0,
    this.frameWidth = 0,
    this.frameHeight = 0,
    required this.updatedAt,
  });
}

/// Режим авторизации Remote Desktop, заданный в настройках хоста.
enum RemoteDesktopAccessMode {
  /// Удалённый desktop отключён полностью.
  disabled,

  /// Только по паролю (без подтверждения, как RustDesk по умолчанию).
  passwordOnly,

  /// Только подтверждение в диалоге.
  promptOnly,

  /// Любой из путей: пароль или подтверждение.
  passwordOrPrompt,
}

/// Настройки RD, хранятся внутри NetworkSettings.
class RemoteDesktopSettings {
  final bool enabled;
  final RemoteDesktopAccessMode accessMode;

  /// Постоянный пароль для RustDesk-стиля. Если null — генерируется при включении.
  final String? password;

  /// Включать ли передачу аудио по умолчанию.
  final bool shareAudio;

  /// Запрещать удалённое управление, разрешать только просмотр.
  final bool viewOnlyByDefault;

  /// Trusted peer ID — авто-приём без подтверждения.
  final List<String> trustedPeerIds;

  /// Целевой битрейт по умолчанию (kbps), 0 = авто.
  final int defaultVideoBitrateKbps;

  /// Желаемый FPS, 0 = авто.
  final int defaultFps;

  /// Предпочитаемый видео-кодек: 'auto'|'H264'|'VP8'|'VP9'|'AV1'.
  final String preferredVideoCodec;

  /// Включён ли удалённый файловый менеджер.
  final bool fileManagerEnabled;

  /// Только чтение для удалённого файлового менеджера (нельзя писать/удалять).
  final bool fileManagerReadOnly;

  /// Какие "корни" доступны через файловый менеджер. Пустой = все диски/$HOME.
  final List<String> fileManagerAllowedRoots;

  const RemoteDesktopSettings({
    this.enabled = false,
    this.accessMode = RemoteDesktopAccessMode.passwordOrPrompt,
    this.password,
    this.shareAudio = false,
    this.viewOnlyByDefault = false,
    this.trustedPeerIds = const [],
    this.defaultVideoBitrateKbps = 0,
    this.defaultFps = 0,
    this.preferredVideoCodec = 'auto',
    this.fileManagerEnabled = true,
    this.fileManagerReadOnly = false,
    this.fileManagerAllowedRoots = const [],
  });

  RemoteDesktopSettings copyWith({
    bool? enabled,
    RemoteDesktopAccessMode? accessMode,
    String? password,
    bool clearPassword = false,
    bool? shareAudio,
    bool? viewOnlyByDefault,
    List<String>? trustedPeerIds,
    int? defaultVideoBitrateKbps,
    int? defaultFps,
    String? preferredVideoCodec,
    bool? fileManagerEnabled,
    bool? fileManagerReadOnly,
    List<String>? fileManagerAllowedRoots,
  }) {
    return RemoteDesktopSettings(
      enabled: enabled ?? this.enabled,
      accessMode: accessMode ?? this.accessMode,
      password: clearPassword ? null : (password ?? this.password),
      shareAudio: shareAudio ?? this.shareAudio,
      viewOnlyByDefault: viewOnlyByDefault ?? this.viewOnlyByDefault,
      trustedPeerIds: trustedPeerIds ?? this.trustedPeerIds,
      defaultVideoBitrateKbps:
          defaultVideoBitrateKbps ?? this.defaultVideoBitrateKbps,
      defaultFps: defaultFps ?? this.defaultFps,
      preferredVideoCodec: preferredVideoCodec ?? this.preferredVideoCodec,
      fileManagerEnabled: fileManagerEnabled ?? this.fileManagerEnabled,
      fileManagerReadOnly: fileManagerReadOnly ?? this.fileManagerReadOnly,
      fileManagerAllowedRoots:
          fileManagerAllowedRoots ?? this.fileManagerAllowedRoots,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'accessMode': accessMode.name,
        'password': password,
        'shareAudio': shareAudio,
        'viewOnlyByDefault': viewOnlyByDefault,
        'trustedPeerIds': trustedPeerIds,
        'defaultVideoBitrateKbps': defaultVideoBitrateKbps,
        'defaultFps': defaultFps,
        'preferredVideoCodec': preferredVideoCodec,
        'fileManagerEnabled': fileManagerEnabled,
        'fileManagerReadOnly': fileManagerReadOnly,
        'fileManagerAllowedRoots': fileManagerAllowedRoots,
      };

  factory RemoteDesktopSettings.fromJson(Map<String, dynamic> json) {
    return RemoteDesktopSettings(
      enabled: json['enabled'] as bool? ?? false,
      accessMode: RemoteDesktopAccessMode.values.firstWhere(
        (m) => m.name == json['accessMode'],
        orElse: () => RemoteDesktopAccessMode.passwordOrPrompt,
      ),
      password: json['password'] as String?,
      shareAudio: json['shareAudio'] as bool? ?? false,
      viewOnlyByDefault: json['viewOnlyByDefault'] as bool? ?? false,
      trustedPeerIds: (json['trustedPeerIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      defaultVideoBitrateKbps: json['defaultVideoBitrateKbps'] as int? ?? 0,
      defaultFps: json['defaultFps'] as int? ?? 0,
      preferredVideoCodec: json['preferredVideoCodec'] as String? ?? 'auto',
      fileManagerEnabled: json['fileManagerEnabled'] as bool? ?? true,
      fileManagerReadOnly: json['fileManagerReadOnly'] as bool? ?? false,
      fileManagerAllowedRoots:
          (json['fileManagerAllowedRoots'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
    );
  }
}
