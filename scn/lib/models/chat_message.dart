/// Chat message model
class ChatMessage {
  final String id;
  final String deviceId;
  final String deviceAlias;
  final String message;
  final DateTime timestamp;
  final bool isFromMe;
  
  ChatMessage({
    required this.id,
    required this.deviceId,
    required this.deviceAlias,
    required this.message,
    required this.timestamp,
    required this.isFromMe,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceId': deviceId,
    'deviceAlias': deviceAlias,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isFromMe': isFromMe,
  };
  
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    deviceId: json['deviceId'] as String,
    deviceAlias: json['deviceAlias'] as String,
    message: json['message'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isFromMe: json['isFromMe'] as bool,
  );
}

/// Chat conversation model
class ChatConversation {
  final String deviceId;
  final String deviceAlias;
  final List<ChatMessage> messages;
  final DateTime lastMessageTime;
  
  ChatConversation({
    required this.deviceId,
    required this.deviceAlias,
    required this.messages,
    required this.lastMessageTime,
  });
  
  ChatConversation copyWith({
    String? deviceId,
    String? deviceAlias,
    List<ChatMessage>? messages,
    DateTime? lastMessageTime,
  }) => ChatConversation(
    deviceId: deviceId ?? this.deviceId,
    deviceAlias: deviceAlias ?? this.deviceAlias,
    messages: messages ?? this.messages,
    lastMessageTime: lastMessageTime ?? this.lastMessageTime,
  );
}

