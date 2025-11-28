import 'package:flutter/foundation.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/models/device.dart';
import 'package:scn/services/http_client_service.dart';

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
  
  /// Set current user info for message sending
  void setMyInfo({required String deviceId, required String alias}) {
    _myDeviceId = deviceId;
    _myAlias = alias;
    _httpClient.setMyInfo(deviceId: deviceId, alias: alias);
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
    // Initialize group chat
    _conversations[groupChatId] = ChatConversation(
      deviceId: groupChatId,
      deviceAlias: 'Group Chat',
      messages: [
        ChatMessage.system('Welcome to SCN Group Chat! All connected users can see messages here.'),
      ],
      lastMessageTime: DateTime.now(),
    );
  }
  
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
  
  void openGroupChat() {
    setActiveConversation(groupChatId);
  }
  
  void closeChat() {
    setActiveConversation(null);
  }
  
  // Add or update participant
  void addParticipant(ChatParticipant participant) {
    final existing = _participants[participant.deviceId];
    _participants[participant.deviceId] = participant;
    
    // Add system message to group chat if new participant
    if (existing == null) {
      _addSystemMessage('${participant.alias} joined the network');
    } else if (existing.status == UserStatus.offline && 
               participant.status != UserStatus.offline) {
      _addSystemMessage('${participant.alias} is now online');
    }
    
    notifyListeners();
  }
  
  // Update participant from Device
  void updateParticipantFromDevice(Device device) {
    addParticipant(ChatParticipant(
      deviceId: device.id,
      alias: device.alias,
      ip: device.ip,
      port: device.port,
      status: UserStatus.online,
    ));
  }
  
  // Mark participant as offline
  void setParticipantOffline(String deviceId) {
    final participant = _participants[deviceId];
    if (participant != null && participant.status != UserStatus.offline) {
      _participants[deviceId] = participant.copyWith(
        status: UserStatus.offline,
        lastSeen: DateTime.now(),
      );
      _addSystemMessage('${participant.alias} went offline');
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
    final conversation = _conversations[targetId];
    
    if (conversation == null) {
      // Create new private conversation
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
      
      _conversations[targetId] = conversation.copyWith(
        messages: updatedMessages,
        lastMessageTime: message.timestamp,
        unreadCount: newUnread,
      );
    }
    
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
    Device device, {
    bool toGroup = false,
  }) async {
    // Add message locally first
    final chatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceId: deviceId,
      deviceAlias: deviceAlias,
      message: message,
      timestamp: DateTime.now(),
      isFromMe: true,
      isGroupMessage: toGroup,
    );
    
    addMessage(chatMessage);
    
    if (toGroup) {
      // Send to all online participants
      bool allSuccess = true;
      for (final participant in onlineParticipants) {
        final participantDevice = Device(
          id: participant.deviceId,
          alias: participant.alias,
          ip: participant.ip,
          port: participant.port,
          type: DeviceType.desktop,
        );
        
        final success = await _httpClient.sendMessage(
          device: participantDevice,
          message: message,
          isGroupMessage: true,
        );
        
        if (!success) allSuccess = false;
      }
      return allSuccess;
    } else {
      // Send to specific device
      final success = await _httpClient.sendMessage(
        device: device,
        message: message,
        isGroupMessage: false,
      );
      
      if (!success) {
        debugPrint('Failed to send message to ${device.alias}');
      }
      return success;
    }
  }
  
  // Send to group chat
  Future<bool> sendToGroup(String message, String myAlias) async {
    final chatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceId: 'me',
      deviceAlias: myAlias,
      message: message,
      timestamp: DateTime.now(),
      isFromMe: true,
      isGroupMessage: true,
    );
    
    addMessage(chatMessage);
    
    // Send to all online participants
    bool allSuccess = true;
    for (final participant in onlineParticipants) {
      final device = Device(
        id: participant.deviceId,
        alias: participant.alias,
        ip: participant.ip,
        port: participant.port,
        type: DeviceType.desktop,
      );
      
      final success = await _httpClient.sendMessage(
        device: device,
        message: message,
        isGroupMessage: true,
      );
      
      if (!success) allSuccess = false;
    }
    
    return allSuccess;
  }
  
  // Get messages for a conversation
  List<ChatMessage> getMessages(String deviceId) {
    return _conversations[deviceId]?.messages ?? [];
  }
  
  // Get participant by ID
  ChatParticipant? getParticipant(String deviceId) {
    return _participants[deviceId];
  }
  
  // Get total unread count
  int get totalUnreadCount {
    return _conversations.values.fold(0, (sum, c) => sum + c.unreadCount);
  }
  
  // Mark all conversations as read
  void markAllAsRead() {
    bool changed = false;
    for (final key in _conversations.keys) {
      if (_conversations[key]!.unreadCount > 0) {
        _conversations[key] = _conversations[key]!.copyWith(unreadCount: 0);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }
  
  // Clear all data
  void clear() {
    _conversations.clear();
    _participants.clear();
    _activeConversationId = null;
    
    // Re-initialize group chat
    _conversations[groupChatId] = ChatConversation(
      deviceId: groupChatId,
      deviceAlias: 'Group Chat',
      messages: [],
      lastMessageTime: DateTime.now(),
    );
    
    notifyListeners();
  }
}
