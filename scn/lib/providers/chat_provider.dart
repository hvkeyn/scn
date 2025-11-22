import 'package:flutter/foundation.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/models/device.dart';
import 'package:scn/services/http_client_service.dart';

/// Provider for managing chat conversations
class ChatProvider extends ChangeNotifier {
  final Map<String, ChatConversation> _conversations = {};
  String? _activeConversationId;
  final HttpClientService _httpClient = HttpClientService();
  
  List<ChatConversation> get conversations => _conversations.values.toList()
    ..sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
  
  ChatConversation? getActiveConversation() {
    if (_activeConversationId == null) return null;
    return _conversations[_activeConversationId];
  }
  
  void setActiveConversation(String deviceId) {
    _activeConversationId = deviceId.isEmpty ? null : deviceId;
    notifyListeners();
  }
  
  void addMessage(ChatMessage message) {
    final conversation = _conversations[message.deviceId];
    
    if (conversation == null) {
      // Create new conversation
      _conversations[message.deviceId] = ChatConversation(
        deviceId: message.deviceId,
        deviceAlias: message.deviceAlias,
        messages: [message],
        lastMessageTime: message.timestamp,
      );
    } else {
      // Add to existing conversation
      final updatedMessages = [...conversation.messages, message];
      _conversations[message.deviceId] = conversation.copyWith(
        messages: updatedMessages,
        lastMessageTime: message.timestamp,
      );
    }
    
    notifyListeners();
  }
  
  Future<void> sendMessage(String deviceId, String deviceAlias, String message, Device device) async {
    // Add message locally first
    final chatMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deviceId: deviceId,
      deviceAlias: deviceAlias,
      message: message,
      timestamp: DateTime.now(),
      isFromMe: true,
    );
    
    addMessage(chatMessage);
    
    // Send via HTTP
    final success = await _httpClient.sendMessage(
      device: device,
      message: message,
    );
    
    if (!success) {
      // Mark message as failed (could add error state to ChatMessage)
      debugPrint('Failed to send message to ${device.alias}');
    }
  }
  
  List<ChatMessage> getMessages(String deviceId) {
    return _conversations[deviceId]?.messages ?? [];
  }
}

