import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/services/app_service.dart';
import 'package:scn/services/http_client_service.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/models/device.dart';
import 'package:scn/models/file_info.dart';
import 'package:scn/utils/file_opener.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _uuid = const Uuid();
  bool _isSendingFile = false;
  
  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    final appService = context.watch<AppService>();
    
    // Update participants from discovered devices
    for (final device in deviceProvider.devices) {
      chatProvider.updateParticipantFromDevice(device);
    }
    
    // If in a conversation, show chat view
    if (chatProvider.activeConversationId != null) {
      return _buildChatView(context, chatProvider, appService);
    }
    
    // Otherwise show main view with group chat and users
    return _buildMainView(context, chatProvider, deviceProvider, appService);
  }

  Widget _buildMainView(
    BuildContext context,
    ChatProvider chatProvider,
    DeviceProvider deviceProvider,
    AppService appService,
  ) {
    return Column(
      children: [
        // Group Chat Card
        _buildGroupChatCard(context, chatProvider),
        
        const Divider(height: 1),
        
        // Online Users Section
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.people, color: Colors.white.withOpacity(0.7), size: 20),
              const SizedBox(width: 8),
              Text(
                'Online Users (${chatProvider.onlineParticipants.length})',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        
        // Users List
        Expanded(
          child: chatProvider.participants.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: chatProvider.participants.length,
                  itemBuilder: (context, index) {
                    final participant = chatProvider.participants[index];
                    return _buildUserTile(context, chatProvider, participant);
                  },
                ),
        ),
      ],
    );
  }
  
  Widget _buildGroupChatCard(BuildContext context, ChatProvider chatProvider) {
    final groupChat = chatProvider.groupChat;
    final unread = groupChat?.unreadCount ?? 0;
    final lastMessage = groupChat?.messages.isNotEmpty == true 
        ? groupChat!.messages.last 
        : null;
    
    String lastMessageText = 'Start chatting with everyone!';
    if (lastMessage != null) {
      if (lastMessage.type == MessageType.image) {
        lastMessageText = '📷 Photo';
      } else if (lastMessage.type == MessageType.file) {
        lastMessageText = '📎 ${lastMessage.fileName}';
      } else {
        lastMessageText = lastMessage.message;
      }
    }
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => chatProvider.openGroupChat(),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.purple.withOpacity(0.3),
                Colors.blue.withOpacity(0.2),
              ],
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups, color: Colors.purple, size: 28),
              ),
              const SizedBox(width: 16),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Group Chat',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${chatProvider.onlineParticipants.length} online',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lastMessageText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Unread badge & arrow
              if (unread > 0) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.purple,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildUserTile(BuildContext context, ChatProvider chatProvider, ChatParticipant participant) {
    final conversation = chatProvider.conversations.firstWhere(
      (c) => c.deviceId == participant.deviceId,
      orElse: () => ChatConversation(
        deviceId: participant.deviceId,
        deviceAlias: participant.alias,
        messages: [],
        lastMessageTime: DateTime.now(),
      ),
    );
    
    String lastMessageText = _getStatusText(participant.status);
    if (conversation.messages.isNotEmpty) {
      final lastMsg = conversation.messages.last;
      if (lastMsg.type == MessageType.image) {
        lastMessageText = '📷 Photo';
      } else if (lastMsg.type == MessageType.file) {
        lastMessageText = '📎 ${lastMsg.fileName}';
      } else {
        lastMessageText = lastMsg.message;
      }
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => chatProvider.setActiveConversation(participant.deviceId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar with status
              Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    child: Text(
                      participant.alias[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _getStatusColor(participant.status),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF1a1a2e), width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          participant.alias,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!participant.isLocal) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.cloud, size: 14, color: Colors.blue.withOpacity(0.7)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastMessageText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // Time & unread
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (conversation.messages.isNotEmpty)
                    Text(
                      _formatTime(conversation.lastMessageTime),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  if (conversation.unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${conversation.unreadCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_find,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No devices found',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure devices are on the same network',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChatView(BuildContext context, ChatProvider chatProvider, AppService appService) {
    final conversation = chatProvider.getActiveConversation();
    if (conversation == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final isGroupChat = chatProvider.isGroupChatActive;
    final messages = conversation.messages;
    
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => chatProvider.closeChat(),
              ),
              const SizedBox(width: 8),
              
              // Avatar
              if (isGroupChat)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.groups, color: Colors.purple, size: 24),
                )
              else
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  child: Text(
                    conversation.deviceAlias[0].toUpperCase(),
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              const SizedBox(width: 12),
              
              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGroupChat ? 'Group Chat' : conversation.deviceAlias,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (isGroupChat)
                      Text(
                        '${chatProvider.onlineParticipants.length} participants',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Participants button for group
              if (isGroupChat)
                IconButton(
                  icon: const Icon(Icons.people_outline, color: Colors.white),
                  onPressed: () => _showParticipants(context, chatProvider),
                ),
            ],
          ),
        ),
        
        // Messages
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _buildMessageBubble(context, message, isGroupChat);
                  },
                ),
        ),
        
        // Input with file attachment
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: Row(
            children: [
              // Attachment button
              IconButton(
                icon: _isSendingFile 
                    ? const SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file, color: Colors.white54),
                onPressed: _isSendingFile 
                    ? null 
                    : () => _pickAndSendFile(context, chatProvider, appService, isGroupChat, conversation),
              ),
              
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: isGroupChat 
                        ? 'Message everyone...' 
                        : 'Message ${conversation.deviceAlias}...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(context, chatProvider, appService, isGroupChat, conversation),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () => _sendMessage(context, chatProvider, appService, isGroupChat, conversation),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildMessageBubble(BuildContext context, ChatMessage message, bool isGroupChat) {
    if (message.type == MessageType.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    
    // Image message
    if (message.type == MessageType.image && message.filePath != null) {
      return _buildImageBubble(context, message, isGroupChat);
    }
    
    // File message
    if (message.type == MessageType.file) {
      return _buildFileBubble(context, message, isGroupChat);
    }
    
    // Text message
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isFromMe
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isFromMe ? 16 : 4),
            bottomRight: Radius.circular(message.isFromMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show sender name in group chat
            if (isGroupChat && !message.isFromMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.deviceAlias,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            Text(
              message.message,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildImageBubble(BuildContext context, ChatMessage message, bool isGroupChat) {
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: message.isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name in group
            if (isGroupChat && !message.isFromMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Text(
                  message.deviceAlias,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            
            // Image
            GestureDetector(
              onTap: () => FileOpener.openFile(message.filePath!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(message.filePath!),
                  fit: BoxFit.cover,
                  width: 250,
                  height: 200,
                  errorBuilder: (_, __, ___) => Container(
                    width: 250,
                    height: 100,
                    color: Colors.white.withOpacity(0.1),
                    child: const Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              ),
            ),
            
            // Time
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFileBubble(BuildContext context, ChatMessage message, bool isGroupChat) {
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isFromMe
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: message.filePath != null 
                ? () => FileOpener.openFile(message.filePath!)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name in group
                  if (isGroupChat && !message.isFromMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        message.deviceAlias,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.insert_drive_file, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.fileName ?? 'File',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (message.fileSize != null)
                              Text(
                                _formatFileSize(message.fileSize!),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  // Time
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Future<void> _pickAndSendFile(
    BuildContext context,
    ChatProvider chatProvider,
    AppService appService,
    bool isGroupChat,
    ChatConversation conversation,
  ) async {
    final result = await file_picker.FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: file_picker.FileType.any,
    );
    
    if (result == null || result.files.isEmpty) return;
    
    final file = result.files.first;
    if (file.path == null) return;
    
    setState(() => _isSendingFile = true);
    
    try {
      // Determine file type
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp']
          .contains(file.extension?.toLowerCase());
      
      // Get target devices
      List<Device> targets = [];
      if (isGroupChat) {
        for (final p in chatProvider.onlineParticipants) {
          targets.add(Device(
            id: p.deviceId,
            alias: p.alias,
            ip: p.ip,
            port: p.port,
            type: DeviceType.desktop,
          ));
        }
      } else {
        final participant = chatProvider.getParticipant(conversation.deviceId);
        if (participant != null) {
          targets.add(Device(
            id: participant.deviceId,
            alias: participant.alias,
            ip: participant.ip,
            port: participant.port,
            type: DeviceType.desktop,
          ));
        }
      }
      
      if (targets.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recipients available')),
        );
        return;
      }
      
      // Send file to each target
      final httpClient = HttpClientService();
      final ext = file.extension?.toLowerCase() ?? '';
      final fileType = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext)
          ? FileType.image
          : ['mp4', 'avi', 'mov', 'mkv', 'webm'].contains(ext)
              ? FileType.video
              : FileType.other;
      final fileInfo = FileInfo(
        id: _uuid.v4(),
        fileName: file.name,
        size: file.size,
        fileType: fileType,
      );
      
      for (final target in targets) {
        try {
          // Send file with chat flag
          await httpClient.sendFileWithChat(
            target: target,
            filePath: file.path!,
            fileInfo: fileInfo,
            senderId: appService.deviceId,
            senderAlias: appService.deviceAlias,
            isGroupMessage: isGroupChat,
          );
        } catch (e) {
          debugPrint('Failed to send file to ${target.alias}: $e');
        }
      }
      
      // Add to local chat
      chatProvider.addMessage(ChatMessage.file(
        id: _uuid.v4(),
        deviceId: appService.deviceId,
        deviceAlias: appService.deviceAlias,
        fileName: file.name,
        fileSize: file.size,
        isFromMe: true,
        filePath: file.path,
        mimeType: isImage ? 'image/${file.extension}' : null,
        isGroupMessage: isGroupChat,
      ));
      
      _scrollToBottom();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send file: $e')),
      );
    } finally {
      setState(() => _isSendingFile = false);
    }
  }
  
  void _sendMessage(
    BuildContext context,
    ChatProvider chatProvider,
    AppService appService,
    bool isGroupChat,
    ChatConversation conversation,
  ) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    _messageController.clear();
    
    if (isGroupChat) {
      await chatProvider.sendToGroup(text, appService.deviceAlias);
    } else {
      final participant = chatProvider.getParticipant(conversation.deviceId);
      if (participant != null) {
        final device = Device(
          id: participant.deviceId,
          alias: participant.alias,
          ip: participant.ip,
          port: participant.port,
          type: DeviceType.desktop,
        );
        await chatProvider.sendMessage(
          conversation.deviceId,
          conversation.deviceAlias,
          text,
          device,
        );
      }
    }
    
    _scrollToBottom();
  }
  
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }
  
  void _showParticipants(BuildContext context, ChatProvider chatProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Participants (${chatProvider.participants.length})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chatProvider.participants.length,
              itemBuilder: (context, index) {
                final p = chatProvider.participants[index];
                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        child: Text(p.alias[0].toUpperCase()),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _getStatusColor(p.status),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF1a1a2e), width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  title: Text(p.alias, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _getStatusText(p.status),
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat, color: Colors.white54),
                    onPressed: () {
                      Navigator.pop(context);
                      chatProvider.setActiveConversation(p.deviceId);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Color _getStatusColor(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return Colors.green;
      case UserStatus.away:
        return Colors.orange;
      case UserStatus.busy:
        return Colors.red;
      case UserStatus.offline:
        return Colors.grey;
    }
  }
  
  String _getStatusText(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return 'Online';
      case UserStatus.away:
        return 'Away';
      case UserStatus.busy:
        return 'Busy';
      case UserStatus.offline:
        return 'Offline';
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inMinutes < 1) {
      return 'Now';
    } else if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(time);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }
  
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
