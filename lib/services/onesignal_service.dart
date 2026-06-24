import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal Push Notification Service for ChefKart
/// Uses role-based Player IDs for proper multi-device notification handling
/// Structure: oneSignalPlayerIds: { chef: "ID", customer: "ID" }
class OneSignalService {
  static const String _appId = 'd653679f-c733-47a3-ab38-8137ab806807';
  static const String _restApiKey = String.fromEnvironment(
    'ONESIGNAL_REST_API_KEY',
  );

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Current logged in user ID and role
  static String? _currentUserId;
  static String? _currentUserRole; // 'chef' or 'customer'

  // Callback for notification handling
  static Function(String screen, Map<String, dynamic> data)? onNotificationOpened;

  // ==========================================
  // INITIALIZATION
  // ==========================================

  /// Initialize OneSignal - Call this in main.dart after Firebase init
  static Future<void> initialize() async {
    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(_appId);
      await _requestPermission();
      _setupNotificationHandlers();
      debugPrint('✅ OneSignal initialized successfully');
    } catch (e) {
      debugPrint('❌ OneSignal initialization error: $e');
    }
  }

  static Future<bool> _requestPermission() async {
    try {
      final granted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('Notification permission granted: $granted');
      return granted;
    } catch (e) {
      debugPrint('Error requesting permission: $e');
      return false;
    }
  }

  static void _setupNotificationHandlers() {
    OneSignal.Notifications.addClickListener((event) {
      debugPrint('📱 Notification clicked: ${event.notification.title}');
      final additionalData = event.notification.additionalData;
      if (additionalData != null) {
        final screen = additionalData['screen'] as String? ?? '';
        final data = Map<String, dynamic>.from(additionalData);
        if (onNotificationOpened != null) {
          onNotificationOpened!(screen, data);
        }
      }
    });

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      debugPrint('📬 Notification received in foreground: ${event.notification.title}');
      event.notification.display();
    });

    OneSignal.Notifications.addPermissionObserver((granted) {
      debugPrint('Notification permission changed: $granted');
    });

    // Save player ID when subscription changes
    OneSignal.User.pushSubscription.addObserver((state) {
      debugPrint('=== ONESIGNAL SUBSCRIPTION CHANGED ===');
      debugPrint('Subscription ID: ${state.current.id}');
      _savePlayerIdForCurrentRole(state.current.id);
    });
  }

  // ==========================================
  // ROLE-BASED PLAYER ID MANAGEMENT
  // ==========================================

  /// Save player ID for the current role (chef or customer)
  static Future<void> _savePlayerIdForCurrentRole(String? playerId) async {
    if (playerId == null || playerId.isEmpty) return;
    if (_currentUserId == null || _currentUserRole == null) return;

    try {
      await _firestore.collection('users').doc(_currentUserId).set({
        'oneSignalPlayerIds': {
          _currentUserRole: playerId,
        },
        'oneSignalUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('✅ Player ID saved for role $_currentUserRole: $playerId');
    } catch (e) {
      debugPrint('❌ Error saving player ID for role: $e');
    }
  }

  /// Login user to OneSignal with specific role
  /// This saves the player ID under oneSignalPlayerIds.{role}
  static Future<void> loginUserWithRole({
    required String uid,
    required String role, // 'chef' or 'customer'
    String? email,
    String? name,
  }) async {
    try {
      _currentUserId = uid;
      _currentUserRole = role;

      debugPrint('=== ONESIGNAL LOGIN WITH ROLE ===');
      debugPrint('UID: $uid');
      debugPrint('Role: $role');

      // Login to OneSignal
      await OneSignal.login(uid);
      debugPrint('✅ OneSignal user logged in: $uid');

      // Wait for subscription to be ready
      await Future.delayed(const Duration(seconds: 2));

      // Get player ID and save for this role
      String? playerId;
      try {
        playerId = OneSignal.User.pushSubscription.id;
      } catch (e) {
        debugPrint('⚠️ Could not get subscription ID: $e');
      }

      debugPrint('📱 OneSignal Player ID: $playerId');

      if (playerId != null && playerId.isNotEmpty) {
        // Save player ID under oneSignalPlayerIds.{role}
        await _firestore.collection('users').doc(uid).set({
          'oneSignalPlayerIds': {
            role: playerId,
          },
          'oneSignalUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Player ID saved for $role: $playerId');
      } else {
        // Retry after delay
        await Future.delayed(const Duration(seconds: 3));
        try {
          playerId = OneSignal.User.pushSubscription.id;
          if (playerId != null && playerId.isNotEmpty) {
            await _firestore.collection('users').doc(uid).set({
              'oneSignalPlayerIds': {
                role: playerId,
              },
              'oneSignalUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint('✅ Player ID saved on retry for $role: $playerId');
          }
        } catch (e) {
          debugPrint('❌ Failed to get player ID on retry: $e');
        }
      }

      // Set tags
      try {
        await OneSignal.User.addTags({
          'role': role,
          'uid': uid,
          if (email != null) 'email': email,
          if (name != null) 'name': name,
        });
      } catch (e) {
        debugPrint('⚠️ Could not set tags: $e');
      }

    } catch (e) {
      debugPrint('❌ OneSignal login error: $e');
    }
  }

  /// Update player ID when user switches mode (chef ↔ customer)
  /// This saves the current device's player ID for the new role
  static Future<void> updateRoleAndSavePlayerId(String uid, String newRole) async {
    try {
      _currentUserId = uid;
      _currentUserRole = newRole;

      debugPrint('=== ONESIGNAL MODE SWITCH ===');
      debugPrint('UID: $uid');
      debugPrint('New Role: $newRole');

      // Get current player ID
      String? playerId;
      try {
        playerId = OneSignal.User.pushSubscription.id;
      } catch (e) {
        debugPrint('⚠️ Could not get subscription ID: $e');
      }

      if (playerId != null && playerId.isNotEmpty) {
        // Save player ID for the new role
        await _firestore.collection('users').doc(uid).set({
          'oneSignalPlayerIds': {
            newRole: playerId,
          },
          'oneSignalUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Player ID updated for $newRole: $playerId');
      }

      // Update tags
      try {
        await OneSignal.User.addTags({
          'role': newRole,
          'currentMode': newRole,
        });
      } catch (e) {
        debugPrint('⚠️ Could not update tags: $e');
      }

    } catch (e) {
      debugPrint('❌ Error updating role: $e');
    }
  }

  /// Logout user from OneSignal
  static Future<void> logoutUser() async {
    try {
      _currentUserId = null;
      _currentUserRole = null;
      await OneSignal.logout();
      debugPrint('✅ OneSignal user logged out');
    } catch (e) {
      debugPrint('❌ OneSignal logout error: $e');
    }
  }

  // Keep old method for backward compatibility
  static Future<void> updateUserRole(String role) async {
    if (_currentUserId != null) {
      await updateRoleAndSavePlayerId(_currentUserId!, role);
    }
  }

  // Keep old method for backward compatibility
  static Future<void> loginUser({
    required String uid,
    required String role,
    String? email,
    String? name,
  }) async {
    await loginUserWithRole(uid: uid, role: role, email: email, name: name);
  }

  // ==========================================
  // GET PLAYER IDs FOR NOTIFICATIONS
  // ==========================================

  /// Get chef's player ID from user document
  static Future<String?> getChefPlayerId(String chefUid) async {
    try {
      final doc = await _firestore.collection('users').doc(chefUid).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      // Try new structure first: oneSignalPlayerIds.chef
      final playerIds = data['oneSignalPlayerIds'] as Map<String, dynamic>?;
      if (playerIds != null && playerIds['chef'] != null) {
        return playerIds['chef'] as String;
      }

      // Fallback to old structure: oneSignalPlayerId
      return data['oneSignalPlayerId'] as String?;
    } catch (e) {
      debugPrint('Error getting chef player ID: $e');
      return null;
    }
  }

  /// Get customer's player ID from user document
  static Future<String?> getCustomerPlayerId(String customerUid) async {
    try {
      final doc = await _firestore.collection('users').doc(customerUid).get();
      if (!doc.exists) return null;

      final data = doc.data();
      if (data == null) return null;

      // Try new structure first: oneSignalPlayerIds.customer
      final playerIds = data['oneSignalPlayerIds'] as Map<String, dynamic>?;
      if (playerIds != null && playerIds['customer'] != null) {
        return playerIds['customer'] as String;
      }

      // Fallback to old structure: oneSignalPlayerId
      return data['oneSignalPlayerId'] as String?;
    } catch (e) {
      debugPrint('Error getting customer player ID: $e');
      return null;
    }
  }

  /// Get multiple chef player IDs
  static Future<List<String>> getChefPlayerIds(List<String> chefUids) async {
    final List<String> playerIds = [];
    for (final uid in chefUids) {
      final playerId = await getChefPlayerId(uid);
      if (playerId != null && playerId.isNotEmpty) {
        playerIds.add(playerId);
      }
    }
    return playerIds;
  }

  // ==========================================
  // SEND NOTIFICATIONS
  // ==========================================

  /// Send notification to a chef (uses oneSignalPlayerIds.chef)
  static Future<bool> sendNotificationToChef({
    required String chefUid,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final playerId = await getChefPlayerId(chefUid);
    if (playerId == null || playerId.isEmpty) {
      debugPrint('❌ No chef player ID found for $chefUid');
      return false;
    }
    return await sendNotificationToPlayer(
      playerId: playerId,
      title: title,
      body: body,
      data: data,
    );
  }

  /// Send notification to a customer (uses oneSignalPlayerIds.customer)
  static Future<bool> sendNotificationToCustomer({
    required String customerUid,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final playerId = await getCustomerPlayerId(customerUid);
    if (playerId == null || playerId.isEmpty) {
      debugPrint('❌ No customer player ID found for $customerUid');
      return false;
    }
    return await sendNotificationToPlayer(
      playerId: playerId,
      title: title,
      body: body,
      data: data,
    );
  }

  /// Send notification to a single player ID
  static Future<bool> sendNotificationToPlayer({
    required String playerId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    return await sendNotificationToMultipleUsers(
      playerIds: [playerId],
      title: title,
      body: body,
      data: data,
    );
  }

  /// Send notification to multiple users by their player IDs
  static Future<bool> sendNotificationToMultipleUsers({
    required List<String> playerIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    if (playerIds.isEmpty) {
      debugPrint('❌ No player IDs provided');
      return false;
    }

    debugPrint('=== SENDING ONESIGNAL NOTIFICATION ===');
    debugPrint('Player IDs: $playerIds');
    debugPrint('Title: $title');
    debugPrint('Body: $body');

    try {
      final requestBody = {
        'app_id': _appId,
        'include_player_ids': playerIds,
        'headings': {'en': title},
        'contents': {'en': body},
        if (data != null) 'data': data,
      };

      debugPrint('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic $_restApiKey',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        debugPrint('✅ Notification sent! Recipients: ${responseData['recipients']}');
        return true;
      } else {
        debugPrint('❌ Failed to send notification: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      return false;
    }
  }

  /// Send notification to all chefs with player IDs
  static Future<bool> sendNotificationToAllChefs({
    required String title,
    required String body,
    Map<String, dynamic>? data,
    List<String>? excludeChefIds,
  }) async {
    try {
      // Get all chefs
      final chefsQuery = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'chef')
          .get();

      final List<String> chefPlayerIds = [];

      for (var doc in chefsQuery.docs) {
        if (excludeChefIds?.contains(doc.id) == true) continue;

        final data = doc.data();
        // Get chef player ID from nested structure
        final playerIds = data['oneSignalPlayerIds'] as Map<String, dynamic>?;
        String? playerId;

        if (playerIds != null && playerIds['chef'] != null) {
          playerId = playerIds['chef'] as String;
        } else {
          // Fallback to old structure
          playerId = data['oneSignalPlayerId'] as String?;
        }

        if (playerId != null && playerId.isNotEmpty) {
          chefPlayerIds.add(playerId);
        }
      }

      if (chefPlayerIds.isEmpty) {
        debugPrint('❌ No chef player IDs found');
        return false;
      }

      debugPrint('📤 Sending notification to ${chefPlayerIds.length} chefs');
      return await sendNotificationToMultipleUsers(
        playerIds: chefPlayerIds,
        title: title,
        body: body,
        data: data,
      );
    } catch (e) {
      debugPrint('❌ Error sending notification to all chefs: $e');
      return false;
    }
  }

  // ==========================================
  // SPECIFIC NOTIFICATION METHODS
  // ==========================================

  /// Notify chef when customer confirms their offer
  static Future<bool> notifyChefOfferConfirmed({
    required String chefId,
    required String orderId,
    required String customerName,
  }) async {
    debugPrint('=== NOTIFYING CHEF: OFFER CONFIRMED ===');
    debugPrint('Chef ID: $chefId');
    debugPrint('Order ID: $orderId');

    return await sendNotificationToChef(
      chefUid: chefId,
      title: 'Booking Confirmed!',
      body: '$customerName has confirmed your offer. Check your bookings.',
      data: {
        'screen': 'chef_bookings',
        'orderId': orderId,
        'type': 'offer_confirmed',
      },
    );
  }

  /// Notify customer when chef sends an offer
  static Future<bool> notifyCustomerOfChefOffer({
    required String customerId,
    required String chefName,
    required String requestId,
    required int offeredPrice,
  }) async {
    debugPrint('=== NOTIFYING CUSTOMER: NEW CHEF OFFER ===');
    debugPrint('Customer ID: $customerId');
    debugPrint('Chef: $chefName');

    return await sendNotificationToCustomer(
      customerUid: customerId,
      title: 'New Offer from $chefName!',
      body: 'Rs. $offeredPrice - Tap to view and accept.',
      data: {
        'screen': 'view_offers',
        'requestId': requestId,
        'type': 'new_chef_offer',
      },
    );
  }

  /// Notify customer when chef sends a counter offer
  static Future<bool> notifyCustomerCounterOffer({
    required String customerId,
    required String orderId,
    required String chefName,
    required int counterPrice,
  }) async {
    debugPrint('=== NOTIFYING CUSTOMER: COUNTER OFFER ===');
    debugPrint('Customer ID: $customerId');
    debugPrint('Chef: $chefName');
    debugPrint('Price: Rs. $counterPrice');

    return await sendNotificationToCustomer(
      customerUid: customerId,
      title: 'New Offer from $chefName!',
      body: 'Rs. $counterPrice - Tap to view and respond.',
      data: {
        'screen': 'view_offers',
        'requestId': orderId,
        'type': 'counter_offer',
      },
    );
  }

  /// Notify customer when chef accepts their order (direct request)
  static Future<bool> notifyCustomerOrderAccepted({
    required String customerId,
    required String orderId,
    required String chefName,
  }) async {
    debugPrint('=== NOTIFYING CUSTOMER: ORDER ACCEPTED ===');
    debugPrint('Customer ID: $customerId');
    debugPrint('Chef: $chefName');

    return await sendNotificationToCustomer(
      customerUid: customerId,
      title: 'Booking Accepted!',
      body: '$chefName has accepted your booking request.',
      data: {
        'screen': 'customer_bookings',
        'orderId': orderId,
        'type': 'order_accepted',
      },
    );
  }

  /// Notify customer when chef rejects their order
  static Future<bool> notifyCustomerOrderRejected({
    required String customerId,
    required String chefName,
  }) async {
    return await sendNotificationToCustomer(
      customerUid: customerId,
      title: 'Request Declined',
      body: '$chefName is not available. Try another chef.',
      data: {
        'screen': 'home',
        'type': 'order_rejected',
      },
    );
  }

  /// Notify customer when booking is completed
  static Future<bool> notifyCustomerBookingComplete({
    required String customerId,
    required String chefName,
    required String bookingId,
  }) async {
    return await sendNotificationToCustomer(
      customerUid: customerId,
      title: 'Service Complete!',
      body: '$chefName marked the service as complete. Please leave a review.',
      data: {
        'screen': 'booking_details',
        'bookingId': bookingId,
        'type': 'booking_complete',
      },
    );
  }

  /// Notify chef when they receive a direct booking request
  static Future<bool> notifyChefDirectRequest({
    required String chefId,
    required String customerName,
    required String requestId,
  }) async {
    return await sendNotificationToChef(
      chefUid: chefId,
      title: 'Direct Booking Request!',
      body: '$customerName wants to book you directly.',
      data: {
        'screen': 'chef_requests',
        'requestId': requestId,
        'type': 'direct_request',
      },
    );
  }

  /// Notify user of new chat message
  /// Determines the receiver's role based on sender and sends to appropriate player ID
  static Future<bool> notifyChatMessage({
    required String receiverId,
    required String senderId,
    required String senderName,
    required String message,
    required String chatRoomId,
  }) async {
    debugPrint('=== CHAT NOTIFICATION ===');
    debugPrint('Receiver: $receiverId');
    debugPrint('Sender: $senderId ($senderName)');

    try {
      // Get receiver's document to determine their role in this chat
      final receiverDoc = await _firestore.collection('users').doc(receiverId).get();
      if (!receiverDoc.exists) {
        debugPrint('❌ Receiver document not found');
        return false;
      }

      final receiverData = receiverDoc.data()!;
      final receiverCurrentMode = receiverData['currentMode'] ?? receiverData['role'] ?? '';

      // Get the appropriate player ID based on receiver's current mode
      String? playerId;
      final playerIds = receiverData['oneSignalPlayerIds'] as Map<String, dynamic>?;

      if (playerIds != null) {
        // Use the receiver's current mode to get the right player ID
        playerId = playerIds[receiverCurrentMode] as String?;
        debugPrint('Using oneSignalPlayerIds.$receiverCurrentMode: $playerId');
      }

      // Fallback to old structure
      if (playerId == null || playerId.isEmpty) {
        playerId = receiverData['oneSignalPlayerId'] as String?;
        debugPrint('Using fallback oneSignalPlayerId: $playerId');
      }

      if (playerId == null || playerId.isEmpty) {
        debugPrint('❌ No player ID found for receiver');
        return false;
      }

      return await sendNotificationToPlayer(
        playerId: playerId,
        title: senderName,
        body: message.length > 50 ? '${message.substring(0, 50)}...' : message,
        data: {
          'screen': 'chat',
          'chatId': chatRoomId,
          'type': 'chat_message',
        },
      );
    } catch (e) {
      debugPrint('❌ Error sending chat notification: $e');
      return false;
    }
  }
}
