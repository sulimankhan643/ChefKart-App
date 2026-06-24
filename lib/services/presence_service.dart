import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service to manage chef's real-time online/offline presence.
/// Sets chef online when app is active, offline when app is closed/backgrounded.
class PresenceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Heartbeat timer — periodically updates lastOnlineAt so stale statuses can be detected
  static Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(minutes: 2);

  // Threshold: if lastOnlineAt is older than this, treat as offline
  static const Duration staleThreshold = Duration(minutes: 5);

  /// Set chef as online and start heartbeat
  static Future<void> goOnline() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('users').doc(uid).update({
        'isAvailable': true,
        'lastOnlineAt': FieldValue.serverTimestamp(),
      });
      debugPrint('PresenceService: Chef $uid is now ONLINE');

      // Start heartbeat to keep lastOnlineAt fresh
      _startHeartbeat();
    } catch (e) {
      debugPrint('PresenceService: Error going online: $e');
    }
  }

  /// Set chef as offline and stop heartbeat
  static Future<void> goOffline() async {
    _stopHeartbeat();

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _firestore.collection('users').doc(uid).update({
        'isAvailable': false,
        'lastOnlineAt': FieldValue.serverTimestamp(),
      });
      debugPrint('PresenceService: Chef $uid is now OFFLINE');
    } catch (e) {
      debugPrint('PresenceService: Error going offline: $e');
    }
  }

  /// Start periodic heartbeat to keep lastOnlineAt fresh
  static void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      try {
        await _firestore.collection('users').doc(uid).update({
          'lastOnlineAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('PresenceService: Heartbeat error: $e');
      }
    });
  }

  /// Stop heartbeat timer
  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Check if a chef is truly online based on lastOnlineAt timestamp.
  /// Returns false if the lastOnlineAt is stale (older than threshold).
  static bool isTrulyOnline(bool isAvailableFlag, Timestamp? lastOnlineAt) {
    if (!isAvailableFlag) return false;
    if (lastOnlineAt == null) return false;

    final lastOnline = lastOnlineAt.toDate();
    final now = DateTime.now();
    final difference = now.difference(lastOnline);

    // If the heartbeat is stale, the chef is not truly online
    return difference < staleThreshold;
  }

  /// Cleanup — call when chef logs out or app is fully terminated
  static Future<void> dispose() async {
    _stopHeartbeat();
    await goOffline();
  }
}

