/// Chat message types
enum MessageType {
  text,       // Regular text message
  system,     // System message (join/leave/status)
  file,       // File attachment
  image,      // Image attachment (shows preview)
}

/// User status
enum UserStatus {
  online,
  away,
  busy,
  offline,
}

/// Chat message model
class ChatMessage {
  final String id;
  final String deviceId;
  final String deviceAlias;
  final String message;
  final DateTime timestamp;
  final bool isFromMe;
  final MessageType type;
  final bool isGroupMessage;  // true for group chat, false for private
  
  // File/Media fields
  final String? fileName;
  final int? fileSize;
  final String? filePath;     // Local path after download
  final String? mimeType;
  
  ChatMessage({
    required this.id,
    required this.deviceId,
    required this.deviceAlias,
    required this.message,
    required this.timestamp,
    required this.isFromMe,
    this.type = MessageType.text,
    this.isGroupMessage = false,
    this.fileName,
    this.fileSize,
    this.filePath,
    this.mimeType,
  });
  
  /// Check if this is an image
  bool get isImage {
    if (type == MessageType.image) return true;
    if (mimeType?.startsWith('image/') ?? false) return true;
    final ext = fileName?.split('.').last.toLowerCase() ?? '';
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }
  
  /// Check if this is a video
  bool get isVideo {
    if (mimeType?.startsWith('video/') ?? false) return true;
    final ext = fileName?.split('.').last.toLowerCase() ?? '';
    return ['mp4', 'avi', 'mov', 'mkv', 'webm'].contains(ext);
  }
  
  ChatMessage copyWith({
    String? id,
    String? deviceId,
    String? deviceAlias,
    String? message,
    DateTime? timestamp,
    bool? isFromMe,
    MessageType? type,
    bool? isGroupMessage,
    String? fileName,
    int? fileSize,
    String? filePath,
    String? mimeType,
  }) => ChatMessage(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    deviceAlias: deviceAlias ?? this.deviceAlias,
    message: message ?? this.message,
    timestamp: timestamp ?? this.timestamp,
    isFromMe: isFromMe ?? this.isFromMe,
    type: type ?? this.type,
    isGroupMessage: isGroupMessage ?? this.isGroupMessage,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    filePath: filePath ?? this.filePath,
    mimeType: mimeType ?? this.mimeType,
  );
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'deviceAlias': deviceAlias,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isFromMe': isFromMe,
    'type': type.name,
    'isGroupMessage': isGroupMessage,
    if (fileName != null) 'fileName': fileName,
    if (fileSize != null) 'fileSize': fileSize,
    if (filePath != null) 'filePath': filePath,
    if (mimeType != null) 'mimeType': mimeType,
  };
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    deviceId: json['deviceId'] as String,
    deviceAlias: json['deviceAlias'] as String,
    message: json['message'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isFromMe: json['isFromMe'] as bool,
    type: MessageType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => MessageType.text,
    ),
    isGroupMessage: json['isGroupMessage'] as bool? ?? false,
    fileName: json['fileName'] as String?,
    fileSize: json['fileSize'] as int?,
    filePath: json['filePath'] as String?,
    mimeType: json['mimeType'] as String?,
  );
  
  /// Create a system message
  factory ChatMessage.system(String message, {String? deviceId}) => ChatMessage(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    deviceId: deviceId ?? 'system',
    deviceAlias: 'System',
    message: message,
    timestamp: DateTime.now(),
    isFromMe: false,
    type: MessageType.system,
    isGroupMessage: true,
  );
  
  /// Create a file message
  factory ChatMessage.file({
    required String id,
    required String deviceId,
    required String deviceAlias,
    required String fileName,
    required int fileSize,
    required bool isFromMe,
    String? filePath,
    String? mimeType,
    bool isGroupMessage = false,
  }) {
    final isImage = mimeType?.startsWith('image/') ?? false ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
            .contains(fileName.split('.').last.toLowerCase());
    
    return ChatMessage(
      id: id,
      deviceId: deviceId,
      deviceAlias: deviceAlias,
      message: fileName,
      timestamp: DateTime.now(),
      isFromMe: isFromMe,
      type: isImage ? MessageType.image : MessageType.file,
      isGroupMessage: isGroupMessage,
      fileName: fileName,
      fileSize: fileSize,
      filePath: filePath,
      mimeType: mimeType,
    );
  }
}

/// Chat participant with status
class ChatParticipant {
  final String deviceId;
  final String alias;
  final String ip;
  final int port;
  final UserStatus status;
  final DateTime lastSeen;
  final bool isLocal;  // true if on local network
  
  ChatParticipant({
    required this.deviceId,
    required this.alias,
    required this.ip,
    required this.port,
    this.status = UserStatus.online,
    DateTime? lastSeen,
    this.isLocal = true,
  }) : lastSeen = lastSeen ?? DateTime.now();
  
  ChatParticipant copyWith({
    String? deviceId,
    String? alias,
    String? ip,
    int? port,
    UserStatus? status,
    DateTime? lastSeen,
    bool? isLocal,
  }) => ChatParticipant(
    deviceId: deviceId ?? this.deviceId,
    alias: alias ?? this.alias,
    ip: ip ?? this.ip,
    port: port ?? this.port,
    status: status ?? this.status,
    lastSeen: lastSeen ?? this.lastSeen,
    isLocal: isLocal ?? this.isLocal,
  );
  
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'alias': alias,
    'ip': ip,
    'port': port,
    'status': status.name,
    'lastSeen': lastSeen.toIso8601String(),
    'isLocal': isLocal,
  };
  
  factory ChatParticipant.fromJson(Map<String, dynamic> json) => ChatParticipant(
    deviceId: json['deviceId'] as String,
    alias: json['alias'] as String,
    ip: json['ip'] as String,
    port: json['port'] as int,
    status: UserStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => UserStatus.offline,
    ),
    lastSeen: DateTime.parse(json['lastSeen'] as String),
    isLocal: json['isLocal'] as bool? ?? true,
  );
}

/// Chat conversation model
class ChatConversation {
  final String deviceId;
  final String deviceAlias;
  final List<ChatMessage> messages;
  final DateTime lastMessageTime;
  final int unreadCount;
  
  ChatConversation({
    required this.deviceId,
    required this.deviceAlias,
    required this.messages,
    required this.lastMessageTime,
    this.unreadCount = 0,
  });
  
  ChatConversation copyWith({
    String? deviceId,
    String? deviceAlias,
    List<ChatMessage>? messages,
    DateTime? lastMessageTime,
    int? unreadCount,
  }) => ChatConversation(
    deviceId: deviceId ?? this.deviceId,
    deviceAlias: deviceAlias ?? this.deviceAlias,
    messages: messages ?? this.messages,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}
