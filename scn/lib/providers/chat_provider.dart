import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/models/device.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/utils/logger.dart';

/// Special ID for group chat
const String groupChatId = 'group_chat';

/// Provider for managing chat conversations
class ChatProvider extends ChangeNotifier {
  final Map<String, ChatConversation> _conversations = {};
  final Map<String, ChatParticipant> _participants = {};
  String? _activeConversationId;
  final HttpClientService _httpClient = HttpClientService();
  UserStatus _myStatus = UserStatus.online;
  String _myDeviceId = '';
  String _myAlias = '';
  bool _historyLoaded = false;
  
  // Storage key is unique per device
  String get _storageKey => 'chat_history_$_myDeviceId';
  
  /// Set current user info for message sending
  void setMyInfo({required String deviceId, required String alias}) {
    final wasEmpty = _myDeviceId.isEmpty;
    AppLogger.log('🔑 ChatProvider.setMyInfo: deviceId=$deviceId, alias=$alias');
    _myDeviceId = deviceId;
    _myAlias = alias;
    _httpClient.setMyInfo(deviceId: deviceId, alias: alias);
    
    // Load history after we have deviceId (for unique storage key)
    if (wasEmpty && !_historyLoaded) {
      _loadHistory();
    }
  }
  
  // Getters
  List<ChatConversation> get conversations => _conversations.values.toList()
    ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
  
  List<ChatParticipant> get participants => _participants.values.toList()
    ..sort((a, b) => a.alias.compareTo(b.alias));
  
  List<ChatParticipant> get onlineParticipants => 
    _participants.values.where((p) => p.status != UserStatus.offline).toList();
  
  ChatConversation? get groupChat => _conversations[groupChatId];
  
  List<ChatMessage> get groupMessages => groupChat?.messages ?? [];
  
  UserStatus get myStatus => _myStatus;
  
  String? get activeConversationId => _activeConversationId;
  
  ChatConversation? getActiveConversation() {
    if (_activeConversationId == null) return null;
    return _conversations[_activeConversationId];
  }
  
  bool get isGroupChatActive => _activeConversationId == groupChatId;
  
  ChatProvider() {
    _initGroupChat();
    // History is loaded in setMyInfo after deviceId is set
  }
  
  void _initGroupChat() {
    if (!_conversations.containsKey(groupChatId)) {
      _conversations[groupChatId] = ChatConversation(
        deviceId: groupChatId,
        deviceAlias: 'Group Chat',
        messages: [
          ChatMessage.system('Welcome to SCN Group Chat! All connected users can see messages here.'),
        ],
        lastMessageTime: DateTime.now(),
      );
    }
  }
  
  // Load history from storage
  Future<void> _loadHistory() async {
    if (_myDeviceId.isEmpty) {
      AppLogger.log('⚠️ Cannot load history: deviceId not set');
      return;
    }
    
    _historyLoaded = true;
    AppLogger.log('📂 Loading history with key: $_storageKey');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_storageKey);
      if (json != null) {
        final data = jsonDecode(json) as Map<String, dynamic>;
        final convs = data['conversations'] as Map<String, dynamic>?;
        if (convs != null) {
          for (final entry in convs.entries) {
            final conv = _conversationFromJson(entry.value as Map<String, dynamic>);
            _conversations[entry.key] = conv;
          }
        }
        AppLogger.log('📱 Loaded ${_conversations.length} chat conversations');
      } else {
        AppLogger.log('📱 No saved history found');
      }
    } catch (e) {
      AppLogger.log('Failed to load chat history: $e');
    }
    _initGroupChat();
    notifyListeners();
  }
  
  // Save history to storage
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final convs = <String, dynamic>{};
      for (final entry in _conversations.entries) {
        convs[entry.key] = _conversationToJson(entry.value);
      }
      final json = jsonEncode({'conversations': convs});
      await prefs.setString(_storageKey, json);
    } catch (e) {
      AppLogger.log('Failed to save chat history: $e');
    }
  }
  
  Map<String, dynamic> _conversationToJson(ChatConversation conv) => {
    'deviceId': conv.deviceId,
    'deviceAlias': conv.deviceAlias,
    'lastMessageTime': conv.lastMessageTime.toIso8601String(),
    'unreadCount': conv.unreadCount,
    'messages': conv.messages.map((m) => m.toJson()).toList(),
  };
  
  ChatConversation _conversationFromJson(Map<String, dynamic> json) => ChatConversation(
    deviceId: json['deviceId'] as String,
    deviceAlias: json['deviceAlias'] as String,
    lastMessageTime: DateTime.parse(json['lastMessageTime'] as String),
    unreadCount: json['unreadCount'] as int? ?? 0,
    messages: (json['messages'] as List<dynamic>?)
        ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
  );
  
  // Set active conversation
  void setActiveConversation(String? deviceId) {
    _activeConversationId = deviceId;
    
    if (deviceId != null) {
      // Create conversation if doesn't exist
      if (!_conversations.containsKey(deviceId)) {
        final participant = _participants[deviceId];
        _conversations[deviceId] = ChatConversation(
          deviceId: deviceId,
          deviceAlias: participant?.alias ?? 'Unknown',
          messages: [],
          lastMessageTime: DateTime.now(),
        );
      }
      
      // Mark as read
      _conversations[deviceId] = _conversations[deviceId]!.copyWith(unreadCount: 0);
    }
    
    notifyListeners();
  }
  
  // Mark all as read
  void markAllAsRead() {
    for (final key in _conversations.keys) {
      _conversations[key] = _conversations[key]!.copyWith(unreadCount: 0);
    }
    notifyListeners();
  }
  
  // Total unread count
  int get totalUnreadCount => _conversations.values
      .fold(0, (sum, c) => sum + c.unreadCount);
  
  // Close chat
  void closeChat() {
    _activeConversationId = null;
    notifyListeners();
  }
  
  // Open group chat
  void openGroupChat() {
    setActiveConversation(groupChatId);
  }
  
  // Get participant by device ID
  ChatParticipant? getParticipant(String deviceId) => _participants[deviceId];
  
  // Update participant from device
  void updateParticipantFromDevice(Device device) {
    final existing = _participants[device.id];
    if (existing == null || existing.alias != device.alias || existing.ip != device.ip) {
      AppLogger.log('👤 Adding/updating participant: ${device.alias} (${device.id}) at ${device.ip}:${device.port}');
      _participants[device.id] = ChatParticipant(
        deviceId: device.id,
        alias: device.alias,
        ip: device.ip,
        port: device.port,
        status: UserStatus.online,
        isLocal: true,
      );
      notifyListeners();
    }
  }
  
  // Update participant status
  void updateParticipantStatus(String deviceId, UserStatus status) {
    final participant = _participants[deviceId];
    if (participant != null) {
      _participants[deviceId] = participant.copyWith(status: status);
      notifyListeners();
    }
  }
  
  // Set my status
  Future<void> setMyStatus(UserStatus status) async {
    _myStatus = status;
    notifyListeners();
    // TODO: Broadcast status to all participants
  }
  
  // Add message to conversation
  void addMessage(ChatMessage message) {
    final targetId = message.isGroupMessage ? groupChatId : message.deviceId;
    AppLogger.log('💬 addMessage: targetId=$targetId, from=${message.deviceAlias}, isFromMe=${message.isFromMe}');
    AppLogger.log('   Text: ${message.message}');
    
    final conversation = _conversations[targetId];
    
    if (conversation == null) {
      // Create new private conversation
      AppLogger.log('   Creating new conversation for $targetId');
      _conversations[targetId] = ChatConversation(
        deviceId: message.deviceId,
        deviceAlias: message.deviceAlias,
        messages: [message],
        lastMessageTime: message.timestamp,
        unreadCount: message.isFromMe ? 0 : 1,
      );
    } else {
      // Add to existing conversation
      final updatedMessages = [...conversation.messages, message];
      final newUnread = (targetId != _activeConversationId && !message.isFromMe) 
          ? conversation.unreadCount + 1 
          : conversation.unreadCount;
      
      AppLogger.log('   Adding to existing conversation (${conversation.messages.length} -> ${updatedMessages.length} msgs)');
      _conversations[targetId] = conversation.copyWith(
        messages: updatedMessages,
        lastMessageTime: message.timestamp,
        unreadCount: newUnread,
      );
    }
    
    AppLogger.log('   Total conversations: ${_conversations.length}');
    _saveHistory();
    notifyListeners();
  }
  
  // Add system message to group chat
  void _addSystemMessage(String text) {
    addMessage(ChatMessage.system(text));
  }
  
  // Send message to specific device or group
  Future<bool> sendMessage(
    String deviceId,
    String deviceAlias,
    String message,
    Device targetDevice, {
    bool isGroupMessage = false,
  }) async {
    AppLogger.log('📤 ChatProvider.sendMessage:');
    AppLogger.log('   To: $deviceAlias ($deviceId)');
    AppLogger.log('   Message: $message');
    AppLogger.log('   My ID: $_myDeviceId, My Alias: $_myAlias');
    AppLogger.log('   Target URL: ${targetDevice.url}');
    
    // Add local message first
    // For private chats, deviceId should be the recipient's ID (for conversation grouping)
    // But deviceAlias should be OUR alias (the sender)
    final chatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceId: deviceId,  // Target device ID for proper conversation grouping
      deviceAlias: _myAlias ?? 'Me',  // OUR alias as sender
      message: message,
      timestamp: DateTime.now(),
      isFromMe: true,
      isGroupMessage: isGroupMessage,
    );
    
    addMessage(chatMessage);
    AppLogger.log('   ✅ Local message added');
    
    // Send to remote device
    final success = await _httpClient.sendMessage(
      device: targetDevice,
      message: message,
      isGroupMessage: isGroupMessage,
    );
    
    AppLogger.log('   ${success ? "✅" : "❌"} HTTP send: $success');
    return success;
  }
  
  // Send to group (all participants)
  Future<void> sendToGroup(String message, String senderAlias) async {
    // Add local message
    final chatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceId: _myDeviceId,
      deviceAlias: senderAlias,
      message: message,
      timestamp: DateTime.now(),
      isFromMe: true,
      isGroupMessage: true,
    );
    
    addMessage(chatMessage);
    
    // Send to all online participants
    for (final participant in onlineParticipants) {
      try {
        final device = Device(
          id: participant.deviceId,
          alias: participant.alias,
          ip: participant.ip,
          port: participant.port,
          type: DeviceType.desktop,
        );
        
        await _httpClient.sendMessage(
          device: device,
          message: message,
          isGroupMessage: true,
        );
      } catch (e) {
        AppLogger.log('Failed to send group message to ${participant.alias}: $e');
      }
    }
  }
  
  // Clear conversation
  void clearConversation(String deviceId) {
    if (deviceId == groupChatId) {
      _conversations[groupChatId] = ChatConversation(
        deviceId: groupChatId,
        deviceAlias: 'Group Chat',
        messages: [
          ChatMessage.system('Chat history cleared'),
        ],
        lastMessageTime: DateTime.now(),
      );
    } else {
      _conversations.remove(deviceId);
    }
    _saveHistory();
    notifyListeners();
  }
  
  // Delete conversation
  void deleteConversation(String deviceId) {
    if (deviceId != groupChatId) {
      _conversations.remove(deviceId);
      if (_activeConversationId == deviceId) {
        _activeConversationId = null;
      }
      _saveHistory();
      notifyListeners();
    }
  }
  
  // Clear all history
  Future<void> clearAllHistory() async {
    _conversations.clear();
    _initGroupChat();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    notifyListeners();
  }
  
  // Remove participant
  void removeParticipant(String deviceId) {
    _participants.remove(deviceId);
    notifyListeners();
  }
}
