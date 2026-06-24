import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service for handling in-app notifications
/// Push notifications are handled by Firebase Cloud Functions
class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // ==========================================
  // TOKEN MANAGEMENT (for FCM)
  // ==========================================

  /// Save FCM token to user's document
  static Future<void> saveToken(String token) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('FCM token saved');
    } catch (e) {
      debugPrint('Error saving FCM token: $e');
    }
  }

  /// Clear FCM token on logout
  static Future<void> clearToken() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _firestore.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });

      debugPrint('FCM token cleared');
    } catch (e) {
      debugPrint('Error clearing FCM token: $e');
    }
  }

  // ==========================================
  // IN-APP NOTIFICATIONS
  // ==========================================

  /// Get user's notifications stream
  static Stream<List<Map<String, dynamic>>> getUserNotifications() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  /// Get unread notification count
  static Stream<int> getUnreadCount() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Mark notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('Marked ${snapshot.docs.length} notifications as read');
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  /// Delete old notifications (cleanup)
  static Future<void> deleteOldNotifications({int daysOld = 30}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));

      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      debugPrint('Deleted ${snapshot.docs.length} old notifications');
    } catch (e) {
      debugPrint('Error deleting old notifications: $e');
    }
  }

  // ==========================================
  // NOTIFICATION TYPES (for manual triggering if needed)
  // Cloud Functions handle actual push notifications
  // ==========================================

  /// Create a notification in Firestore
  static Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'body': body,
        'data': data ?? {},
        'read': false,
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Notification created for $userId: $title');
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  // ==========================================
  // NOTIFICATION HELPERS
  // ==========================================

  /// Notify customer - request accepted
  static Future<void> notifyRequestAccepted({
    required String customerId,
    required String chefName,
    required String date,
    required String requestId,
  }) async {
    await createNotification(
      userId: customerId,
      type: 'request_accepted',
      title: 'Booking Confirmed! ✅',
      body: '$chefName has accepted your booking for $date',
      data: {
        'screen': 'booking_details',
        'requestId': requestId,
      },
    );
  }

  /// Notify customer - request rejected
  static Future<void> notifyRequestRejected({
    required String customerId,
    required String chefName,
    required String requestId,
  }) async {
    await createNotification(
      userId: customerId,
      type: 'request_rejected',
      title: 'Chef Unavailable',
      body: '$chefName is unavailable. Try another chef!',
      data: {
        'screen': 'find_chefs',
        'requestId': requestId,
      },
    );
  }

  /// Notify chef - new booking request
  static Future<void> notifyNewRequest({
    required String chefId,
    required String customerName,
    required String date,
    required String requestId,
  }) async {
    await createNotification(
      userId: chefId,
      type: 'new_request',
      title: 'New Booking Request! 🎉',
      body: '$customerName wants to book you for $date',
      data: {
        'screen': 'chef_requests',
        'requestId': requestId,
      },
    );
  }

  /// Notify chef - booking cancelled by customer
  static Future<void> notifyBookingCancelledByCustomer({
    required String chefId,
    required String customerName,
    required String date,
    required String bookingId,
  }) async {
    await createNotification(
      userId: chefId,
      type: 'booking_cancelled_by_customer',
      title: 'Booking Cancelled',
      body: '$customerName has cancelled the booking for $date',
      data: {
        'screen': 'chef_bookings',
        'bookingId': bookingId,
      },
    );
  }

  /// Notify customer - booking cancelled by chef
  static Future<void> notifyBookingCancelledByChef({
    required String customerId,
    required String chefName,
    required String date,
    required String bookingId,
  }) async {
    await createNotification(
      userId: customerId,
      type: 'booking_cancelled_by_chef',
      title: 'Booking Cancelled by Chef',
      body: '$chefName had to cancel. Please try another chef.',
      data: {
        'screen': 'find_chefs',
        'bookingId': bookingId,
      },
    );
  }

  /// Notify customer - booking completed (prompt for review)
  static Future<void> notifyBookingCompleted({
    required String customerId,
    required String chefName,
    required String bookingId,
  }) async {
    await createNotification(
      userId: customerId,
      type: 'booking_completed',
      title: 'Service Completed! 🌟',
      body: 'How was your experience with $chefName? Leave a review!',
      data: {
        'screen': 'leave_review',
        'bookingId': bookingId,
      },
    );
  }

  /// Notify user - new chat message
  static Future<void> notifyChatMessage({
    required String userId,
    required String senderName,
    required String message,
    required String chatId,
  }) async {
    await createNotification(
      userId: userId,
      type: 'chat_message',
      title: senderName,
      body: message.length > 50 ? '${message.substring(0, 50)}...' : message,
      data: {
        'screen': 'chat',
        'chatId': chatId,
      },
    );
  }
}
