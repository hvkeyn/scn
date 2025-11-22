import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scn/providers/chat_provider.dart';
import 'package:scn/providers/device_provider.dart';
import 'package:scn/models/chat_message.dart';
import 'package:scn/models/device.dart';
import 'package:intl/intl.dart';

class ChatTab extends StatelessWidget {
  const ChatTab({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final deviceProvider = context.watch<DeviceProvider>();
    final activeConversation = chatProvider.getActiveConversation();
    
    if (activeConversation != null) {
      return _buildChatView(context, chatProvider, activeConversation);
    }
    
    return _buildConversationsList(context, chatProvider, deviceProvider);
  }

  Widget _buildConversationsList(
    BuildContext context,
    ChatProvider chatProvider,
    DeviceProvider deviceProvider,
  ) {
    if (chatProvider.conversations.isEmpty && deviceProvider.devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 64),
            const SizedBox(height: 16),
            Text(
              'No conversations',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Start chatting with nearby devices',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        if (deviceProvider.devices.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Available Devices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: deviceProvider.devices.length,
              itemBuilder: (context, index) {
                final device = deviceProvider.devices[index];
                final conversation = chatProvider.conversations
                    .firstWhere(
                      (c) => c.deviceId == device.id,
                      orElse: () => ChatConversation(
                        deviceId: device.id,
                        deviceAlias: device.alias,
                        messages: [],
                        lastMessageTime: DateTime.now(),
                      ),
                    );
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(device.alias[0].toUpperCase()),
                    ),
                    title: Text(device.alias),
                    subtitle: conversation.messages.isNotEmpty
                        ? Text(
                            conversation.messages.last.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : Text('Tap to start chatting'),
                    trailing: conversation.messages.isNotEmpty
                        ? Text(
                            _formatTime(conversation.lastMessageTime),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    onTap: () {
                      chatProvider.setActiveConversation(device.id);
                    },
                  ),
                );
              },
            ),
          ),
        ],
        if (chatProvider.conversations.isNotEmpty && deviceProvider.devices.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Conversations',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: chatProvider.conversations.length,
              itemBuilder: (context, index) {
                final conversation = chatProvider.conversations[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(conversation.deviceAlias[0].toUpperCase()),
                    ),
                    title: Text(conversation.deviceAlias),
                    subtitle: Text(
                      conversation.messages.last.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      _formatTime(conversation.lastMessageTime),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    onTap: () {
                      chatProvider.setActiveConversation(conversation.deviceId);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChatView(
    BuildContext context,
    ChatProvider chatProvider,
    ChatConversation conversation,
  ) {
    final messages = conversation.messages;
    final textController = TextEditingController();
    
    return Column(
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              chatProvider.setActiveConversation('');
            },
          ),
          title: Text(conversation.deviceAlias),
        ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet. Start the conversation!',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return _buildMessageBubble(context, message);
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () async {
                  if (textController.text.trim().isNotEmpty) {
                    final deviceProvider = context.read<DeviceProvider>();
                    final device = deviceProvider.devices.firstWhere(
                      (d) => d.id == conversation.deviceId,
                      orElse: () => Device(
                        id: conversation.deviceId,
                        alias: conversation.deviceAlias,
                        ip: 'unknown',
                        port: 53317,
                        type: DeviceType.desktop,
                      ),
                    );
                    
                    await chatProvider.sendMessage(
                      conversation.deviceId,
                      conversation.deviceAlias,
                      textController.text.trim(),
                      device,
                    );
                    textController.clear();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    return Align(
      alignment: message.isFromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: message.isFromMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.message,
              style: TextStyle(
                color: message.isFromMe
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: message.isFromMe
                    ? Colors.white70
                    : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays == 0) {
      return DateFormat('HH:mm').format(time);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return DateFormat('MMM d').format(time);
    }
  }
}
