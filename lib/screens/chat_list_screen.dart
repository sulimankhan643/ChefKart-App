import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../widgets/cached_chef_image.dart';
import 'chat_screen.dart';

/// Chat List Screen - Shows all conversations (WhatsApp style)
class ChatListScreen extends StatefulWidget {
  final bool isChefView;

  const ChatListScreen({
    super.key,
    this.isChefView = false,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _chatService = ChatService();
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view chats')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search coming soon')),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatService.getMyChats(userId, isChef: widget.isChefView),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  const Text('Error loading chats'),
                  const SizedBox(height: 8),
                  Text('Your ID: $userId', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final chats = snapshot.data?.docs ?? [];

          // Filter out closed chats (order completed)
          // This prevents customer and chef from seeing old chats after order is done
          final activeChats = chats.where((chatDoc) {
            final chatData = chatDoc.data() as Map<String, dynamic>;
            final status = chatData['status'] as String?;
            final chatEnabled = chatData['chatEnabled'];

            // Hide chat if it's closed or chatEnabled is explicitly false
            if (status == 'closed') return false;
            if (chatEnabled == false) return false;

            return true;
          }).toList();

          if (activeChats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No conversations yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isChefView
                        ? 'Customers will message you here'
                        : 'Book a chef to start chatting',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            itemCount: activeChats.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 76,
              color: Colors.grey.shade200,
            ),
            itemBuilder: (context, index) {
              final chat = activeChats[index].data() as Map<String, dynamic>;
              final chatId = activeChats[index].id;

              return _ChatListTile(
                chatId: chatId,
                chatData: chat,
                isChefView: widget.isChefView,
                currentUserId: userId,
              );
            },
          );
        },
      ),
    );
  }
}

/// Individual chat list tile with user info
class _ChatListTile extends StatelessWidget {
  final String chatId;
  final Map<String, dynamic> chatData;
  final bool isChefView;
  final String currentUserId;

  const _ChatListTile({
    required this.chatId,
    required this.chatData,
    required this.isChefView,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    // Get the other user's ID
    final otherUserId = isChefView ? chatData['customerId'] : chatData['chefId'];
    final unreadCount = isChefView
        ? (chatData['chefUnread'] ?? 0)
        : (chatData['customerUnread'] ?? 0);

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
      builder: (context, snapshot) {
        String userName = 'Loading...';
        String? userImage;

        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>;
          userName = userData['name'] ?? 'User';
          userImage = userData['image'];
        }

        final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
        final timeText = _formatTime(lastMessageTime);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade300,
                child: userImage != null && userImage.isNotEmpty
                    ? ClipOval(
                        child: CachedChefImage(
                          imageUrl: userImage,
                          width: 56,
                          height: 56,
                        ),
                      )
                    : Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
              // Online indicator (optional)
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  userName,
                  style: TextStyle(
                    fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w500,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 12,
                  color: unreadCount > 0 ? const Color(0xFF25D366) : Colors.grey.shade500,
                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  chatData['lastMessage'] ?? 'No messages yet',
                  style: TextStyle(
                    color: unreadCount > 0 ? Colors.black87 : Colors.grey.shade600,
                    fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  chatId: chatId,
                  otherUserName: userName,
                  otherUserImage: userImage,
                  isChefView: isChefView,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';

    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      // Today - show time
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      // This week - show day name
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    } else {
      // Older - show date
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

