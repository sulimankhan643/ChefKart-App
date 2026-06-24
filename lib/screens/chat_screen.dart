import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../widgets/cached_chef_image.dart';

/// WhatsApp-style Chat Screen
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserName;
  final String? otherUserImage;
  final bool isChefView;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserName,
    this.otherUserImage,
    this.isChefView = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatService = ChatService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _auth = FirebaseAuth.instance;

  String? _myUserId;
  String? _myName;
  bool _isSending = false;
  bool _isChatClosed = false;
  String? _closureReason;

  // Stream subscription for chat status updates
  Stream<DocumentSnapshot>? _chatStream;

  @override
  void initState() {
    super.initState();
    _loadMyInfo();
    _markAsRead();
    _checkIfChatClosed();
    _listenToChatStatus();
  }

  /// Listen to chat document changes to detect real-time closure
  void _listenToChatStatus() {
    _chatStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots();

    _chatStream?.listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>?;
        final isClosed = data?['status'] == 'closed' || data?['chatEnabled'] == false;

        if (isClosed && !_isChatClosed) {
          setState(() {
            _isChatClosed = true;
            _closureReason = data?['closureReason'] as String?;
          });
        }
      }
    });
  }

  Future<void> _checkIfChatClosed() async {
    try {
      final isClosed = await _chatService.isChatClosed(widget.chatId);
      if (isClosed) {
        final closureInfo = await _chatService.getChatClosureInfo(widget.chatId);
        if (mounted) {
          setState(() {
            _isChatClosed = true;
            _closureReason = closureInfo?['closureReason'] as String?;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking chat closed status: $e');
    }
  }

  Future<void> _loadMyInfo() async {
    _myUserId = _auth.currentUser?.uid;
    if (_myUserId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUserId)
          .get();
      if (doc.exists) {
        setState(() {
          _myName = doc.data()?['name'] ?? 'User';
        });
      }
    }
  }

  Future<void> _markAsRead() async {
    if (_myUserId != null) {
      await _chatService.markMessagesAsRead(widget.chatId, _myUserId!);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _myUserId == null || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      await _chatService.sendMessage(
        chatId: widget.chatId,
        senderId: _myUserId!,
        text: text,
        senderName: _myName,
      );

      // Scroll to bottom after sending
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      setState(() => _isSending = false);
    }
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _buildMessagesList(),
          ),
          // Message Input
          _buildMessageInput(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      leadingWidth: 30,
      title: Row(
        children: [
          // Profile Picture
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade300,
            child: widget.otherUserImage != null && widget.otherUserImage!.isNotEmpty
                ? ClipOval(
                    child: CachedChefImage(
                      imageUrl: widget.otherUserImage!,
                      width: 40,
                      height: 40,
                    ),
                  )
                : Text(
                    widget.otherUserName.isNotEmpty
                        ? widget.otherUserName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Name and Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.isChefView ? 'Customer' : 'Chef',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Call feature coming soon')),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showChatOptions(),
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _chatService.getMessages(widget.chatId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final messages = snapshot.data?.docs ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Say hello! 👋',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        }

        // Auto scroll to bottom when new message arrives
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index].data() as Map<String, dynamic>;
            final isMe = message['senderId'] == _myUserId;
            // Use server createdAt, fallback to client timestamp if null (pending write)
            final timestamp = (message['createdAt'] ?? message['clientTimestamp']) as Timestamp?;

            // Check if we should show date separator
            bool showDate = false;
            if (index == 0) {
              showDate = true;
            } else {
              final prevMessage = messages[index - 1].data() as Map<String, dynamic>;
              final prevTimestamp = (prevMessage['createdAt'] ?? prevMessage['clientTimestamp']) as Timestamp?;
              if (timestamp != null && prevTimestamp != null) {
                final currentDate = timestamp.toDate();
                final prevDate = prevTimestamp.toDate();
                showDate = currentDate.day != prevDate.day ||
                    currentDate.month != prevDate.month ||
                    currentDate.year != prevDate.year;
              }
            }

            return Column(
              children: [
                if (showDate && timestamp != null)
                  _buildDateSeparator(timestamp.toDate()),
                _buildMessageBubble(message, isMe),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String dateText;

    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      dateText = 'Today';
    } else if (date.day == now.day - 1 && date.month == now.month && date.year == now.year) {
      dateText = 'Yesterday';
    } else {
      dateText = '${date.day}/${date.month}/${date.year}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        dateText,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isMe) {
    // Check if this is a system message (like chat closed)
    final isSystemMessage = message['isSystemMessage'] == true || message['senderId'] == 'system';

    if (isSystemMessage) {
      return _buildSystemMessage(message);
    }

    // Use server createdAt, fallback to client timestamp if null (pending write)
    final timestamp = (message['createdAt'] ?? message['clientTimestamp']) as Timestamp?;
    final timeText = timestamp != null
        ? '${timestamp.toDate().hour.toString().padLeft(2, '0')}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
        : '';
    final isRead = message['read'] ?? false;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message['text'] ?? '',
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 14,
                    color: isRead ? Colors.blue : Colors.grey.shade600,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build system message (like chat closed notification)
  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final messageType = message['messageType'] as String?;
    final isChatClosed = messageType == 'chat_closed';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isChatClosed ? Colors.red.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isChatClosed ? Colors.red.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isChatClosed ? Icons.lock : Icons.info_outline,
            color: isChatClosed ? Colors.red.shade400 : Colors.grey.shade600,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message['text'] ?? '',
              style: TextStyle(
                fontSize: 13,
                color: isChatClosed ? Colors.red.shade700 : Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    // Show closed chat banner if chat is closed
    if (_isChatClosed) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border(
            top: BorderSide(color: Colors.red.shade200),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Icon(Icons.lock, color: Colors.red.shade400, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chat Closed',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _closureReason ?? 'Order completed - messaging disabled',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'For new orders, please book through the app.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attachment button (for future)
            IconButton(
              icon: Icon(Icons.attach_file, color: Colors.grey.shade600),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('File sharing coming soon')),
                );
              },
            ),
            // Message TextField
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send Button
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF25D366), // WhatsApp green
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('View Profile'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  // TODO: Navigate to profile
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('View profile coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.orange),
                title: const Text('Block User'),
                onTap: () {
                  Navigator.pop(bottomSheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Block feature coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Chat', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  if (!mounted) return;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete Chat?'),
                      content: const Text('This will delete all messages. This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !mounted) return;
                  await _chatService.deleteChat(widget.chatId);
                  if (!mounted) return;
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

