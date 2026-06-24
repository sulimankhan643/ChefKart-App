import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'onesignal_service.dart';

/// WhatsApp-style Chat Service for ChefKart
class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Create a new chat between customer and chef
  /// Returns existing chat ID if already exists
  Future<String> getOrCreateChat({
    required String customerId,
    required String chefId,
  }) async {
    debugPrint('ChatService.getOrCreateChat: customerId=$customerId, chefId=$chefId');

    // Check if chat already exists
    final existingChat = await _firestore
        .collection('chats')
        .where('customerId', isEqualTo: customerId)
        .where('chefId', isEqualTo: chefId)
        .limit(1)
        .get();

    if (existingChat.docs.isNotEmpty) {
      debugPrint('ChatService.getOrCreateChat: Found existing chat=${existingChat.docs.first.id}');
      return existingChat.docs.first.id;
    }

    // Create new chat
    final chatRef = await _firestore.collection('chats').add({
      'customerId': customerId,
      'chefId': chefId,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'customerUnread': 0,
      'chefUnread': 0,
    });

    debugPrint('ChatService.getOrCreateChat: Created new chat=${chatRef.id}');
    return chatRef.id;
  }

  /// Check if chat is enabled (for deal negotiation flow)
  Future<bool> isChatEnabled(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return false;

      final chatData = chatDoc.data();
      // Chat is enabled if chatEnabled field is true or not present (legacy chats)
      return chatData?['chatEnabled'] ?? true;
    } catch (e) {
      debugPrint('Error checking chat enabled: $e');
      return false;
    }
  }

  /// Send a message in a chat
  /// Returns false if chat is not enabled (during price negotiation)
  Future<bool> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    String? senderName,
    bool skipChatEnabledCheck = false,
  }) async {
    if (text.trim().isEmpty) return false;

    // Check if chat is enabled (skip for system messages)
    if (!skipChatEnabledCheck) {
      final chatEnabled = await isChatEnabled(chatId);
      if (!chatEnabled) {
        debugPrint('Chat not enabled - messages disabled during price negotiation');
        return false;
      }
    }

    // Add message to subcollection
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'clientTimestamp': Timestamp.now(),
      'senderName': senderName ?? 'User',
      'read': false,
    });

    // Update chat document with last message info
    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    final chatData = chatDoc.data();

    if (chatData != null) {
      final isCustomer = senderId == chatData['customerId'];

      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': text.trim(),
        'lastMessageTime': FieldValue.serverTimestamp(),
        if (isCustomer) 'chefUnread': FieldValue.increment(1),
        if (!isCustomer) 'customerUnread': FieldValue.increment(1),
      });

      // Send push notification to the other user
      final receiverId = isCustomer ? chatData['chefId'] : chatData['customerId'];
      if (receiverId != null) {
        await OneSignalService.notifyChatMessage(
          receiverId: receiverId,
          senderId: senderId,
          senderName: senderName ?? 'User',
          message: text.trim(),
          chatRoomId: chatId,
        );
      }
    }

    return true;
  }

  /// Get real-time messages stream for a chat
  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots(includeMetadataChanges: true);
  }

  /// Get all chats for current user (as customer or chef)
  Stream<QuerySnapshot> getMyChats(String userId, {required bool isChef}) {
    final field = isChef ? 'chefId' : 'customerId';

    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots();
  }

  /// Mark messages as read when user opens chat
  Future<void> markMessagesAsRead(String chatId, String readerId) async {
    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    final chatData = chatDoc.data();

    if (chatData != null) {
      final isCustomer = readerId == chatData['customerId'];

      // Reset unread count for this user
      await _firestore.collection('chats').doc(chatId).update({
        if (isCustomer) 'customerUnread': 0,
        if (!isCustomer) 'chefUnread': 0,
      });

      // Mark individual messages as read
      // We filter by 'read' first and then check senderId in code to avoid complex inequality queries
      final unreadMessages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('read', isEqualTo: false)
          .get();

      for (var doc in unreadMessages.docs) {
        final msgData = doc.data();
        // Only mark as read if the message was sent by someone else
        if (msgData['senderId'] != readerId) {
          await doc.reference.update({'read': true});
        }
      }
    }
  }

  /// Get chat details
  Future<Map<String, dynamic>?> getChatDetails(String chatId) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    return doc.data();
  }

  /// Get total unread count for a user
  /// Excludes closed chats (order completed) from the count
  Stream<int> getUnreadCount(String userId, {required bool isChef}) {
    return _firestore
        .collection('chats')
        .where(isChef ? 'chefId' : 'customerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      int total = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();

        // Skip closed chats - don't count their unread messages
        final status = data['status'] as String?;
        final chatEnabled = data['chatEnabled'];
        if (status == 'closed' || chatEnabled == false) {
          continue;
        }

        total += (isChef ? data['chefUnread'] : data['customerUnread']) as int? ?? 0;
      }
      return total;
    });
  }

  /// Delete a chat (optional)
  Future<void> deleteChat(String chatId) async {
    // Delete all messages first
    final messages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();

    for (var doc in messages.docs) {
      await doc.reference.delete();
    }

    // Delete the chat document
    await _firestore.collection('chats').doc(chatId).delete();
  }

  /// ===========================================
  /// CLOSE CHAT WHEN ORDER COMPLETED
  /// ===========================================
  /// This prevents customer and chef from chatting after order is done
  /// to avoid bypassing the app for future orders.
  ///
  /// When chat is closed:
  /// - chatEnabled is set to false
  /// - closedAt timestamp is recorded
  /// - closureReason is stored
  /// - A system message is sent informing both parties
  /// ===========================================

  /// Close chat after order completion
  /// This disables further messaging between customer and chef
  Future<bool> closeChatAfterOrderComplete({
    required String chatId,
    required String bookingId,
    String? closureReason,
  }) async {
    try {
      debugPrint('ChatService: Closing chat $chatId for completed booking $bookingId');

      // Get chat details first
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) {
        debugPrint('ChatService: Chat not found: $chatId');
        return false;
      }

      // Update chat status to closed
      await _firestore.collection('chats').doc(chatId).update({
        'chatEnabled': false,
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'closedForBookingId': bookingId,
        'closureReason': closureReason ?? 'Order completed - chat closed',
      });

      // Send a system message informing both parties
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': 'system',
        'text': '🔒 This chat has been closed as the order is now complete. Thank you for using ChefKart!\n\nFor future orders, please book through the app.',
        'createdAt': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.now(),
        'senderName': 'ChefKart System',
        'read': false,
        'isSystemMessage': true,
        'messageType': 'chat_closed',
      });

      // Update last message
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': '🔒 Chat closed - Order complete',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      debugPrint('ChatService: Chat $chatId successfully closed');
      return true;
    } catch (e) {
      debugPrint('ChatService: Error closing chat: $e');
      return false;
    }
  }

  /// Static method to close chat (can be called from BookingRequestService)
  static Future<bool> closeChat({
    required String customerId,
    required String chefId,
    required String bookingId,
    String? closureReason,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;

      debugPrint('ChatService.closeChat: Looking for chat between customer=$customerId and chef=$chefId');

      // Find the chat between customer and chef
      final chatsQuery = await firestore
          .collection('chats')
          .where('customerId', isEqualTo: customerId)
          .where('chefId', isEqualTo: chefId)
          .limit(1)
          .get();

      if (chatsQuery.docs.isEmpty) {
        debugPrint('ChatService.closeChat: No chat found between these users');
        return true; // No chat to close, that's fine
      }

      final chatId = chatsQuery.docs.first.id;
      debugPrint('ChatService.closeChat: Found chat $chatId, closing...');

      // Close the chat
      await firestore.collection('chats').doc(chatId).update({
        'chatEnabled': false,
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'closedForBookingId': bookingId,
        'closureReason': closureReason ?? 'Order completed - chat closed',
      });

      // Send system message
      await firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': 'system',
        'text': '🔒 This chat has been closed as the order is now complete. Thank you for using ChefKart!\n\nFor future orders, please book through the app.',
        'createdAt': FieldValue.serverTimestamp(),
        'clientTimestamp': Timestamp.now(),
        'senderName': 'ChefKart System',
        'read': false,
        'isSystemMessage': true,
        'messageType': 'chat_closed',
      });

      // Update last message
      await firestore.collection('chats').doc(chatId).update({
        'lastMessage': '🔒 Chat closed - Order complete',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      debugPrint('ChatService.closeChat: Successfully closed chat $chatId');
      return true;
    } catch (e) {
      debugPrint('ChatService.closeChat: Error closing chat: $e');
      return false;
    }
  }

  /// Check if a chat is closed
  Future<bool> isChatClosed(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return true; // Non-existent chat is considered closed

      final chatData = chatDoc.data();
      return chatData?['status'] == 'closed' || chatData?['chatEnabled'] == false;
    } catch (e) {
      debugPrint('Error checking chat closed status: $e');
      return true; // On error, assume closed for safety
    }
  }

  /// Get closure info for a chat
  Future<Map<String, dynamic>?> getChatClosureInfo(String chatId) async {
    try {
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return null;

      final chatData = chatDoc.data();
      if (chatData?['status'] != 'closed') return null;

      return {
        'closedAt': chatData?['closedAt'],
        'closureReason': chatData?['closureReason'],
        'closedForBookingId': chatData?['closedForBookingId'],
      };
    } catch (e) {
      debugPrint('Error getting chat closure info: $e');
      return null;
    }
  }

  /// Get other user's info from chat
  Future<Map<String, dynamic>?> getOtherUserInfo(String chatId, String myUserId) async {
    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    final chatData = chatDoc.data();

    if (chatData == null) return null;

    final otherUserId = myUserId == chatData['customerId']
        ? chatData['chefId']
        : chatData['customerId'];

    final userDoc = await _firestore.collection('users').doc(otherUserId).get();
    return userDoc.data();
  }

  /// Fix old chat documents where chefId might be wrong
  /// This checks if chefId is a valid user document and updates if needed
  static Future<void> fixOldChats() async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Get all chats
      final chatsSnapshot = await firestore.collection('chats').get();

      for (var chatDoc in chatsSnapshot.docs) {
        final chatData = chatDoc.data();
        final chefId = chatData['chefId'] as String?;

        if (chefId == null) continue;

        // Check if chef exists in users collection
        final chefDoc = await firestore.collection('users').doc(chefId).get();

        if (!chefDoc.exists) {
          // chefId is invalid - this chat has wrong data
          // We need to find correct chef by looking at user with this document ID
          // For now, just log it
          debugPrint('Chat ${chatDoc.id} has invalid chefId: $chefId');
        }
      }
    } catch (e) {
      debugPrint('Error fixing chats: $e');
    }
  }
}

