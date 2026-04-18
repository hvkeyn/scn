/// Протокол сообщений LAN signaling для Remote Desktop.
///
/// Между viewer и host идёт два уровня сообщений:
///   1) HTTP REST для request/end:
///      POST /api/rd/request  -> создание сессии
///      POST /api/rd/end      -> завершение сессии
///   2) WebSocket /api/rd/ws?sessionId=..&token=..&role=..
///      обмен JSON-сообщениями типа [RemoteDesktopSignalType] (см. ниже).
///
/// Дополнительно DataChannel внутри WebRTC используется для:
///   - событий ввода (см. RemoteInputEvent)
///   - cursor/clipboard sync (запланировано в PR #2-#3)
library;

/// Тип сообщения signaling-канала.
enum RemoteDesktopSignalType {
  /// Хост объявляет готовность принять offer.
  hostReady,

  /// Viewer прислал WebRTC offer.
  offer,

  /// Хост прислал WebRTC answer.
  answer,

  /// Любая сторона прислала ICE candidate.
  iceCandidate,

  /// Просьба сменить input mode (host -> viewer или viewer -> host).
  inputMode,

  /// Просьба о смене bitrate / FPS.
  qualityChange,

  /// Heartbeat.
  ping,
  pong,

  /// Запланированный обрыв сессии.
  bye,

  /// Запрос статистики (из UI).
  statsRequest,

  /// Сообщение со статистикой.
  stats,

  /// Произвольная ошибка.
  error,
}

/// Конверт сигнального сообщения.
class RemoteDesktopSignal {
  final RemoteDesktopSignalType type;
  final Map<String, dynamic> payload;

  const RemoteDesktopSignal({
    required this.type,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'payload': payload,
      };

  factory RemoteDesktopSignal.fromJson(Map<String, dynamic> json) {
    return RemoteDesktopSignal(
      type: RemoteDesktopSignalType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RemoteDesktopSignalType.error,
      ),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

/// Стандартные поля для request.
class RemoteDesktopRequest {
  final String viewerDeviceId;
  final String viewerAlias;
  final String? password;
  final bool wantsControl;
  final bool wantsAudio;

  const RemoteDesktopRequest({
    required this.viewerDeviceId,
    required this.viewerAlias,
    this.password,
    this.wantsControl = false,
    this.wantsAudio = false,
  });

  Map<String, dynamic> toJson() => {
        'viewerDeviceId': viewerDeviceId,
        'viewerAlias': viewerAlias,
        if (password != null) 'password': password,
        'wantsControl': wantsControl,
        'wantsAudio': wantsAudio,
      };

  factory RemoteDesktopRequest.fromJson(Map<String, dynamic> json) {
    return RemoteDesktopRequest(
      viewerDeviceId: json['viewerDeviceId'] as String,
      viewerAlias: json['viewerAlias'] as String? ?? 'Unknown',
      password: json['password'] as String?,
      wantsControl: json['wantsControl'] as bool? ?? false,
      wantsAudio: json['wantsAudio'] as bool? ?? false,
    );
  }
}

/// Ответ на /api/rd/request.
enum RemoteDesktopRequestStatus {
  /// Сессия создана, можно подключаться к WS.
  accepted,

  /// Нужно подождать подтверждения хоста через диалог.
  waitingApproval,

  /// Отказано в доступе (неверный пароль / отключено).
  rejected,

  /// Хост занят другой сессией.
  busy,
}

class RemoteDesktopRequestResponse {
  final RemoteDesktopRequestStatus status;
  final String? sessionId;
  final String? sessionToken;
  final String? wsPath; // например, /api/rd/ws
  final String? errorMessage;
  final bool grantsControl;
  final bool grantsAudio;

  const RemoteDesktopRequestResponse({
    required this.status,
    this.sessionId,
    this.sessionToken,
    this.wsPath,
    this.errorMessage,
    this.grantsControl = false,
    this.grantsAudio = false,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        if (sessionId != null) 'sessionId': sessionId,
        if (sessionToken != null) 'sessionToken': sessionToken,
        if (wsPath != null) 'wsPath': wsPath,
        if (errorMessage != null) 'errorMessage': errorMessage,
        'grantsControl': grantsControl,
        'grantsAudio': grantsAudio,
      };

  factory RemoteDesktopRequestResponse.fromJson(Map<String, dynamic> json) {
    return RemoteDesktopRequestResponse(
      status: RemoteDesktopRequestStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => RemoteDesktopRequestStatus.rejected,
      ),
      sessionId: json['sessionId'] as String?,
      sessionToken: json['sessionToken'] as String?,
      wsPath: json['wsPath'] as String?,
      errorMessage: json['errorMessage'] as String?,
      grantsControl: json['grantsControl'] as bool? ?? false,
      grantsAudio: json['grantsAudio'] as bool? ?? false,
    );
  }
}
