import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/cooking_request.dart';
import '../models/chef_offer.dart';
import 'onesignal_service.dart';
import 'commission_service.dart';
import 'chef_recommendation_service.dart';

/// Exception thrown when chef tries to accept orders but has pending commission
/// This allows UI to show proper popup message for commission payment
class CommissionBlockedException implements Exception {
  final String message;
  CommissionBlockedException(this.message);

  @override
  String toString() => message;
}

/// Service for InDrive-style deal negotiation between customers and chefs
class DealNegotiationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  static CollectionReference get _requestsCollection =>
      _firestore.collection('cookingRequests');
  static CollectionReference get _offersCollection =>
      _firestore.collection('chefOffers');
  static CollectionReference get _usersCollection =>
      _firestore.collection('users');
  static CollectionReference get _bookingsCollection =>
      _firestore.collection('bookings');
  static CollectionReference get _chatsCollection =>
      _firestore.collection('chats');
  static CollectionReference get _notificationsCollection =>
      _firestore.collection('notifications');

  // Default expiration time in minutes
  static const int defaultExpirationMinutes = 30;

  // ==========================================
  // CUSTOMER SIDE - Create & Manage Requests
  // ==========================================

  /// Customer creates a new broadcast cooking request
  static Future<String?> createBroadcastRequest({
    required String serviceType,
    required String date,
    required String time,
    required String address,
    required int guestCount,
    required int offeredPrice,
    String? note,
    List<String> cuisinePreferences = const [],
    double broadcastRadiusKm = 10.0,
    int expirationMinutes = defaultExpirationMinutes,
    GeoPoint? customerLocation,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('createBroadcastRequest: No user logged in');
        return null;
      }

      debugPrint('createBroadcastRequest: Starting for user ${user.uid}');

      // Get customer details
      final customerDoc = await _usersCollection.doc(user.uid).get();
      final customerData = customerDoc.data() as Map<String, dynamic>?;
      if (customerData == null) {
        debugPrint('createBroadcastRequest: Customer data not found');
        return null;
      }

      debugPrint('createBroadcastRequest: Customer name: ${customerData['name']}');

      // Calculate expiration time
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: expirationMinutes));

      // Get customer location if not provided
      GeoPoint? location = customerLocation;
      if (location == null && customerData['lat'] != null && customerData['lng'] != null) {
        location = GeoPoint(
          customerData['lat'].toDouble(),
          customerData['lng'].toDouble(),
        );
      }

      // Create request document
      final requestRef = _requestsCollection.doc();
      final requestData = {
        'customerId': user.uid,
        'customerName': customerData['name'] ?? 'Customer',
        'customerPhone': customerData['phone'] ?? '',
        'customerImage': customerData['image'],
        'serviceType': serviceType,
        'date': date,
        'time': time,
        'customerLocation': location,
        'address': address,
        'guestCount': guestCount,
        'offeredPrice': offeredPrice,
        'note': note,
        'cuisinePreferences': cuisinePreferences,
        'broadcastRadiusKm': broadcastRadiusKm,
        'expirationMinutes': expirationMinutes,
        'status': CookingRequestStatus.pending.name,
        'confirmedChefId': null,
        'confirmedChefName': null,
        'finalPrice': null,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'confirmedAt': null,
        'chatEnabled': false,
      };

      await requestRef.set(requestData);


      debugPrint('✅ Broadcast request created successfully: ${requestRef.id}');
      debugPrint('   - Service: $serviceType');
      debugPrint('   - Date: $date, Time: $time');
      debugPrint('   - Price: $offeredPrice');
      debugPrint('   - Expires: $expiresAt');

      // Notify nearby chefs (this would typically be done via Cloud Functions)
      await _notifyNearbyChefs(requestRef.id, requestData, location);

      return requestRef.id;
    } catch (e, stackTrace) {
      debugPrint('❌ Error creating broadcast request: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Notify nearby available chefs about the new request
  /// Uses oneSignalPlayerIds.chef for proper role-based notifications
  static Future<void> _notifyNearbyChefs(
    String requestId,
    Map<String, dynamic> requestData,
    GeoPoint? customerLocation,
  ) async {
    try {
      debugPrint('=== NOTIFYING CHEFS ABOUT NEW REQUEST ===');

      // Get all available chefs
      final chefsQuery = await _usersCollection
          .where('role', isEqualTo: 'chef')
          .get();

      debugPrint('Found ${chefsQuery.docs.length} total chefs');

      final broadcastRadius = (requestData['broadcastRadiusKm'] ?? 10.0) as double;
      final List<String> chefPlayerIds = [];
      int chefsWithPlayerId = 0;
      int chefsAvailable = 0;

      for (var chefDoc in chefsQuery.docs) {
        final chefData = chefDoc.data() as Map<String, dynamic>;
        final chefId = chefDoc.id;
        final isAvailable = chefData['isAvailable'] ?? false;

        debugPrint('Chef: ${chefData['name']} ($chefId)');
        debugPrint('  - isAvailable: $isAvailable');

        // Skip if chef is explicitly offline
        if (isAvailable == false) {
          debugPrint('  - SKIPPED: Chef is offline');
          continue;
        }
        chefsAvailable++;

        // Only check distance if both have locations
        if (customerLocation != null && chefData['lat'] != null && chefData['lng'] != null) {
          final distance = _calculateDistance(
            customerLocation.latitude,
            customerLocation.longitude,
            chefData['lat'].toDouble(),
            chefData['lng'].toDouble(),
          );

          if (distance > broadcastRadius) {
            debugPrint('  - SKIPPED: Outside radius (${distance.toStringAsFixed(1)} km > $broadcastRadius km)');
            continue;
          }
          debugPrint('  - Distance: ${distance.toStringAsFixed(1)} km (within radius)');
        } else {
          debugPrint('  - No location check (location missing)');
        }

        // Get chef's player ID from role-based structure
        String? playerId;
        final playerIds = chefData['oneSignalPlayerIds'] as Map<String, dynamic>?;
        if (playerIds != null && playerIds['chef'] != null) {
          playerId = playerIds['chef'] as String;
          debugPrint('  - oneSignalPlayerIds.chef: $playerId');
        } else {
          // Fallback to old structure
          playerId = chefData['oneSignalPlayerId'] as String?;
          debugPrint('  - oneSignalPlayerId (fallback): $playerId');
        }

        if (playerId != null && playerId.isNotEmpty) {
          chefPlayerIds.add(playerId);
          chefsWithPlayerId++;
          debugPrint('  - ✅ Added to notification list');
        } else {
          debugPrint('  - ⚠️ No OneSignal player ID');
        }

        // Create in-app notification for chef
        await _notificationsCollection.add({
          'userId': chefId,
          'type': 'new_broadcast_request',
          'title': 'New Cooking Request! 🍳',
          'body': '${requestData['customerName']} is looking for a chef for ${requestData['date']}',
          'data': {
            'screen': 'broadcast_requests',
            'requestId': requestId,
          },
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('=== NOTIFICATION SUMMARY ===');
      debugPrint('Total chefs: ${chefsQuery.docs.length}');
      debugPrint('Available chefs: $chefsAvailable');
      debugPrint('Chefs with OneSignal ID: $chefsWithPlayerId');
      debugPrint('Chefs to notify: ${chefPlayerIds.length}');

      // Send push notification to all nearby chefs via OneSignal
      if (chefPlayerIds.isNotEmpty) {
        final success = await OneSignalService.sendNotificationToMultipleUsers(
          playerIds: chefPlayerIds,
          title: '🍳 New Order Request!',
          body: '${requestData['customerName']} needs ${requestData['serviceType']} in ${requestData['address']}. Budget: Rs. ${requestData['offeredPrice']}',
          data: {
            'screen': 'chef_orders',
            'requestId': requestId,
            'type': 'new_broadcast_order',
          },
        );
        debugPrint('✅ Push notification sent: $success');
      } else {
        debugPrint('⚠️ No chefs to notify - no player IDs found');
      }
    } catch (e) {
      debugPrint('Error notifying chefs: $e');
    }
  }

  /// Calculate distance between two coordinates (Haversine formula)
  static double _calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  // ==========================================
  // AI RECOMMENDATION INTEGRATION
  // ==========================================

  /// Get AI-recommended chef for an order request
  /// This uses the ChefRecommendationService to find the best match
  /// based on rating, experience, specialty match, and fair distribution
  ///
  /// [requestId] - The cooking request ID to get recommendation for
  /// Returns a recommendation result map or null if no suitable chef found
  static Future<Map<String, dynamic>?> getAiRecommendedChefForRequest(
    String requestId,
  ) async {
    try {
      debugPrint('=== AI RECOMMENDATION FOR REQUEST ===');
      debugPrint('Request ID: $requestId');

      // Get the request details
      final requestDoc = await _requestsCollection.doc(requestId).get();
      if (!requestDoc.exists) {
        debugPrint('AI RECOMMENDATION: Request not found');
        return null;
      }

      final requestData = requestDoc.data() as Map<String, dynamic>;
      final cuisinePreferences = List<String>.from(requestData['cuisinePreferences'] ?? []);
      final customerLocation = requestData['customerLocation'] as GeoPoint?;

      // Get customer's city from their profile
      final customerId = requestData['customerId'] as String;
      String orderCity = 'Peshawar'; // Default

      final customerDoc = await _usersCollection.doc(customerId).get();
      if (customerDoc.exists) {
        final customerData = customerDoc.data() as Map<String, dynamic>;
        orderCity = customerData['city'] ?? 'Peshawar';
      }

      debugPrint('Order City: $orderCity');
      debugPrint('Cuisine Preferences: $cuisinePreferences');

      // Get AI recommendation
      final recommendation = await ChefRecommendationService.getRecommendedChef(
        orderCity: orderCity,
        requiredDishes: cuisinePreferences,
        orderLocation: customerLocation,
      );

      if (recommendation == null || recommendation['recommended_chef_id'] == null) {
        debugPrint('AI RECOMMENDATION: No suitable chef found');
        return null;
      }

      debugPrint('AI RECOMMENDATION: Best match - ${recommendation['chef_name']}');
      debugPrint('Final Score: ${recommendation['final_score']}');

      return recommendation;
    } catch (e) {
      debugPrint('Error getting AI recommendation: $e');
      return null;
    }
  }

  /// Get top N AI-recommended chefs for an order request
  /// Returns multiple recommendations sorted by score
  static Future<List<Map<String, dynamic>>> getTopAiRecommendedChefsForRequest(
    String requestId, {
    int count = 3,
  }) async {
    try {
      debugPrint('=== AI TOP $count RECOMMENDATIONS FOR REQUEST ===');

      // Get the request details
      final requestDoc = await _requestsCollection.doc(requestId).get();
      if (!requestDoc.exists) {
        debugPrint('AI RECOMMENDATION: Request not found');
        return [];
      }

      final requestData = requestDoc.data() as Map<String, dynamic>;
      final cuisinePreferences = List<String>.from(requestData['cuisinePreferences'] ?? []);
      final customerLocation = requestData['customerLocation'] as GeoPoint?;

      // Get customer's city
      final customerId = requestData['customerId'] as String;
      String orderCity = 'Peshawar';

      final customerDoc = await _usersCollection.doc(customerId).get();
      if (customerDoc.exists) {
        final customerData = customerDoc.data() as Map<String, dynamic>;
        orderCity = customerData['city'] ?? 'Peshawar';
      }

      // Get top recommendations
      final recommendations = await ChefRecommendationService.getTopRecommendedChefs(
        orderCity: orderCity,
        requiredDishes: cuisinePreferences,
        orderLocation: customerLocation,
        count: count,
      );

      debugPrint('AI RECOMMENDATION: Found ${recommendations.length} matches');
      return recommendations;
    } catch (e) {
      debugPrint('Error getting top AI recommendations: $e');
      return [];
    }
  }

  /// Customer cancels their pending request
  static Future<bool> cancelRequest(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Use transaction for atomicity
      await _firestore.runTransaction((transaction) async {
        final requestDoc = await transaction.get(_requestsCollection.doc(requestId));

        if (!requestDoc.exists) throw Exception('Request not found');

        final data = requestDoc.data() as Map<String, dynamic>;
        if (data['customerId'] != user.uid) throw Exception('Not authorized');
        if (data['status'] != CookingRequestStatus.pending.name) {
          throw Exception('Request is not pending');
        }

        // Update request status
        transaction.update(_requestsCollection.doc(requestId), {
          'status': CookingRequestStatus.cancelled.name,
        });

        // Expire all related offers
        final offersQuery = await _offersCollection
            .where('requestId', isEqualTo: requestId)
            .where('status', isEqualTo: ChefOfferStatus.pending.name)
            .get();

        for (var offerDoc in offersQuery.docs) {
          transaction.update(offerDoc.reference, {
            'status': ChefOfferStatus.expired.name,
            'respondedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      debugPrint('Request cancelled: $requestId');
      return true;
    } catch (e) {
      debugPrint('Error cancelling request: $e');
      return false;
    }
  }

  /// Customer confirms a chef's offer - FINAL DEAL
  static Future<bool> confirmChefOffer(String offerId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Use transaction for atomic confirmation
      return await _firestore.runTransaction<bool>((transaction) async {
        // Get the offer
        final offerDoc = await transaction.get(_offersCollection.doc(offerId));
        if (!offerDoc.exists) throw Exception('Offer not found');

        final offerData = offerDoc.data() as Map<String, dynamic>;
        final requestId = offerData['requestId'];
        final chefId = offerData['chefId'];

        // Get the request
        final requestDoc = await transaction.get(_requestsCollection.doc(requestId));
        if (!requestDoc.exists) throw Exception('Request not found');

        final requestData = requestDoc.data() as Map<String, dynamic>;

        // Verify ownership and status
        if (requestData['customerId'] != user.uid) {
          throw Exception('Not authorized');
        }
        if (requestData['status'] != CookingRequestStatus.pending.name) {
          throw Exception('Request is no longer pending');
        }
        if (offerData['status'] != ChefOfferStatus.pending.name) {
          throw Exception('Offer is no longer valid');
        }


        // 1. Update the accepted offer
        transaction.update(_offersCollection.doc(offerId), {
          'status': ChefOfferStatus.accepted.name,
          'respondedAt': FieldValue.serverTimestamp(),
        });

        // 2. Update the request to confirmed
        transaction.update(_requestsCollection.doc(requestId), {
          'status': CookingRequestStatus.confirmed.name,
          'confirmedChefId': chefId,
          'confirmedChefName': offerData['chefName'],
          'finalPrice': offerData['offeredPrice'],
          'confirmedAt': FieldValue.serverTimestamp(),
          'chatEnabled': true, // Enable chat after confirmation
        });

        // 3. Reject all other pending offers for this request
        final otherOffersQuery = await _offersCollection
            .where('requestId', isEqualTo: requestId)
            .where('status', isEqualTo: ChefOfferStatus.pending.name)
            .get();

        for (var otherOffer in otherOffersQuery.docs) {
          if (otherOffer.id != offerId) {
            transaction.update(otherOffer.reference, {
              'status': ChefOfferStatus.rejected.name,
              'respondedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        // 4. Create confirmed booking
        final bookingRef = _bookingsCollection.doc();

        // 5. Create chat for confirmed customer-chef pair
        final chatRef = _chatsCollection.doc();

        // Set booking with chat reference
        transaction.set(bookingRef, {
          'requestId': requestId,
          'offerId': offerId,
          'chefId': chefId,
          'chefName': offerData['chefName'],
          'chefImage': offerData['chefImage'],
          'customerId': user.uid,
          'customerName': requestData['customerName'],
          'customerPhone': requestData['customerPhone'],
          'customerImage': requestData['customerImage'],
          'serviceType': requestData['serviceType'],
          'date': requestData['date'],
          'time': requestData['time'],
          'location': requestData['customerLocation'],
          'address': requestData['address'],
          'guestCount': requestData['guestCount'],
          'price': offerData['offeredPrice'],
          'note': requestData['note'],
          'status': 'confirmed',
          'createdAt': FieldValue.serverTimestamp(),
          'reviewed': false,
          'chatId': chatRef.id, // Store chat reference in booking
        });

        // Set chat with booking reference
        transaction.set(chatRef, {
          'customerId': user.uid,
          'chefId': chefId,
          'requestId': requestId,
          'bookingId': bookingRef.id,
          'lastMessage': 'Deal confirmed! You can now chat.',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'customerUnread': 0,
          'chefUnread': 1,
          'chatEnabled': true,
        });

        // Send OneSignal push notification to chef about confirmation
        // Note: This is called after transaction completes
        Future.microtask(() async {
          await OneSignalService.notifyChefOfferConfirmed(
            chefId: chefId,
            orderId: requestId,
            customerName: requestData['customerName'] ?? 'Customer',
          );
        });

        return true;
      });
    } catch (e) {
      debugPrint('Error confirming chef offer: $e');
      return false;
    }
  }

  /// Customer rejects a specific chef offer
  static Future<bool> rejectChefOffer(String offerId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final offerDoc = await _offersCollection.doc(offerId).get();
      if (!offerDoc.exists) return false;

      final offerData = offerDoc.data() as Map<String, dynamic>;
      final requestDoc = await _requestsCollection.doc(offerData['requestId']).get();

      if (!requestDoc.exists) return false;
      final requestData = requestDoc.data() as Map<String, dynamic>;

      if (requestData['customerId'] != user.uid) return false;

      await _offersCollection.doc(offerId).update({
        'status': ChefOfferStatus.rejected.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // Notify chef about rejection
      await _notificationsCollection.add({
        'userId': offerData['chefId'],
        'type': 'offer_rejected',
        'title': 'Offer Not Selected',
        'body': '${requestData['customerName']} selected another chef.',
        'data': {'screen': 'chef_offers', 'offerId': offerId},
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Error rejecting offer: $e');
      return false;
    }
  }

  /// Get customer's pending broadcast requests
  static Stream<List<CookingRequest>> getCustomerPendingRequests() {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('getCustomerPendingRequests: No user logged in');
      return Stream.value([]);
    }

    debugPrint('getCustomerPendingRequests: Fetching for customer ${user.uid}');

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('customerId', isEqualTo: user.uid)
        .where('status', isEqualTo: CookingRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          debugPrint('getCustomerPendingRequests: Found ${snapshot.docs.length} requests');
          final requests = snapshot.docs
              .map((doc) {
                try {
                  return CookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>);
                } catch (e) {
                  debugPrint('Error parsing request ${doc.id}: $e');
                  return null;
                }
              })
              .where((r) => r != null && r.isPending)
              .cast<CookingRequest>()
              .toList();

          // Sort locally by createdAt
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          debugPrint('getCustomerPendingRequests: Returning ${requests.length} pending requests');
          return requests;
        });
  }

  /// Get all customer's requests (history)
  static Stream<List<CookingRequest>> getCustomerAllRequests() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('customerId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => CookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Stream offers for a specific request
  static Stream<List<ChefOffer>> streamOffersForRequest(String requestId) {
    // Simple query without orderBy to avoid index requirement
    return _offersCollection
        .where('requestId', isEqualTo: requestId)
        .snapshots()
        .map((snapshot) {
          final offers = snapshot.docs
              .map((doc) => ChefOffer.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          offers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return offers;
        });
  }

  /// Stream a single request
  static Stream<CookingRequest?> streamRequest(String requestId) {
    debugPrint('streamRequest: Streaming request $requestId');
    return _requestsCollection.doc(requestId).snapshots().map((doc) {
      if (!doc.exists) {
        debugPrint('streamRequest: Request $requestId not found');
        return null;
      }
      final data = doc.data() as Map<String, dynamic>?;
      debugPrint('streamRequest: Request $requestId exists, status: ${data?['status']}');
      return CookingRequest.fromMap(doc.id, data ?? {});
    });
  }

  // ==========================================
  // CHEF SIDE - View & Respond to Requests
  // ==========================================

  /// Get nearby broadcast requests for chef
  /// Shows ALL pending requests to ensure chef visibility
  static Stream<List<CookingRequest>> getChefNearbyRequests() {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('getChefNearbyRequests: No user logged in');
      return Stream.value([]);
    }

    debugPrint('getChefNearbyRequests: Fetching for chef ${user.uid}');

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('status', isEqualTo: CookingRequestStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          debugPrint('getChefNearbyRequests: Found ${snapshot.docs.length} pending requests');

          final requests = <CookingRequest>[];

          for (var doc in snapshot.docs) {
            try {
              final data = doc.data() as Map<String, dynamic>;
              final request = CookingRequest.fromMap(doc.id, data);

              // Only filter out truly expired requests (past expiration + still pending)
              if (request.isPending && request.expiresAt.isAfter(DateTime.now())) {
                requests.add(request);
                debugPrint('getChefNearbyRequests: Added request ${request.id} - ${request.serviceType}');
              } else {
                debugPrint('getChefNearbyRequests: Skipped expired request ${request.id}');
              }
            } catch (e) {
              debugPrint('getChefNearbyRequests: Error parsing request ${doc.id}: $e');
            }
          }

          // Sort locally by createdAt (newest first)
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          debugPrint('getChefNearbyRequests: Returning ${requests.length} active requests');
          return requests;
        });
  }

  /// Chef sends an offer (accept price or counter)
  ///
  /// EARNING CYCLE BASED BLOCKING:
  /// Chef cannot send offers if their current_cycle_earnings >= 5000 PKR
  /// They must pay commission to start a new cycle before accepting new orders.
  ///
  /// Throws [CommissionBlockedException] when orders are blocked due to pending commission.
  static Future<String?> sendChefOffer({
    required String requestId,
    required ChefOfferType offerType,
    required int offeredPrice,
    String? message,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      // CHECK FOR ORDER BLOCKING DUE TO EARNING CYCLE THRESHOLD
      // Orders are blocked when current_cycle_earnings >= 5000 PKR
      final shouldBlock = await CommissionService.shouldBlockNewOrders();
      if (shouldBlock) {
        debugPrint('sendChefOffer failed: Chef orders blocked - earning cycle threshold reached (5000 PKR)');
        debugPrint('Chef must pay commission to start new cycle before accepting new orders.');
        // Throw custom exception so UI can show proper popup
        throw CommissionBlockedException(
          'Order limit reached! Pay your pending commission to continue accepting orders.',
        );
      }

      // Check if chef already has pending offer for this request
      final existingOffer = await _offersCollection
          .where('requestId', isEqualTo: requestId)
          .where('chefId', isEqualTo: user.uid)
          .where('status', isEqualTo: ChefOfferStatus.pending.name)
          .limit(1)
          .get();

      if (existingOffer.docs.isNotEmpty) {
        debugPrint('Chef already has pending offer for this request');
        return null;
      }

      // Get request details
      final requestDoc = await _requestsCollection.doc(requestId).get();
      if (!requestDoc.exists) return null;

      final requestData = requestDoc.data() as Map<String, dynamic>;

      // Verify request is still pending
      if (requestData['status'] != CookingRequestStatus.pending.name) {
        debugPrint('Request is no longer pending');
        return null;
      }

      // Get chef details
      final chefDoc = await _usersCollection.doc(user.uid).get();
      final chefData = chefDoc.data() as Map<String, dynamic>?;
      if (chefData == null) return null;

      // Calculate distance to customer
      double? distance;
      if (chefData['lat'] != null && chefData['lng'] != null &&
          requestData['customerLocation'] != null) {
        final customerLoc = requestData['customerLocation'] as GeoPoint;
        distance = _calculateDistance(
          chefData['lat'].toDouble(),
          chefData['lng'].toDouble(),
          customerLoc.latitude,
          customerLoc.longitude,
        );
      }

      // Create offer document
      final offerRef = _offersCollection.doc();
      final offerData = {
        'requestId': requestId,
        'chefId': user.uid,
        'chefName': chefData['name'] ?? 'Chef',
        'chefImage': chefData['image'],
        'chefRating': chefData['rating'] ?? 4.0,
        'chefReviewCount': chefData['reviewCount'] ?? 0,
        'chefCuisines': List<String>.from(chefData['cuisines'] ?? []),
        'chefExperience': chefData['experience'],
        'chefDistanceKm': distance,
        'offerType': offerType.name,
        'offeredPrice': offeredPrice,
        'originalPrice': requestData['offeredPrice'],
        'message': message,
        'status': ChefOfferStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
      };

      await offerRef.set(offerData);

      // Notify customer about new offer (in-app notification)
      await _notificationsCollection.add({
        'userId': requestData['customerId'],
        'type': 'new_chef_offer',
        'title': 'New Offer! 💰',
        'body': offerType == ChefOfferType.accept
            ? '${chefData['name']} accepted your price of Rs. $offeredPrice'
            : '${chefData['name']} offered Rs. $offeredPrice',
        'data': {
          'screen': 'view_offers',
          'requestId': requestId,
          'offerId': offerRef.id,
        },
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Send OneSignal push notification to customer
      await OneSignalService.notifyCustomerCounterOffer(
        customerId: requestData['customerId'] ?? '',
        orderId: requestId,
        chefName: chefData['name'] ?? 'Chef',
        counterPrice: offeredPrice,
      );

      debugPrint('Chef offer sent: ${offerRef.id}');
      return offerRef.id;
    } on CommissionBlockedException {
      // Rethrow commission blocked exception so UI can handle it
      rethrow;
    } catch (e) {
      debugPrint('Error sending chef offer: $e');
      return null;
    }
  }

  /// Chef accepts customer's offered price (shortcut)
  static Future<String?> acceptCustomerPrice(String requestId) async {
    final requestDoc = await _requestsCollection.doc(requestId).get();
    if (!requestDoc.exists) return null;

    final data = requestDoc.data() as Map<String, dynamic>;
    return sendChefOffer(
      requestId: requestId,
      offerType: ChefOfferType.accept,
      offeredPrice: data['offeredPrice'],
    );
  }

  /// Chef sends counter offer
  static Future<String?> sendCounterOffer({
    required String requestId,
    required int counterPrice,
    String? message,
  }) async {
    return sendChefOffer(
      requestId: requestId,
      offerType: ChefOfferType.counter,
      offeredPrice: counterPrice,
      message: message,
    );
  }

  /// Chef withdraws their offer
  static Future<bool> withdrawOffer(String offerId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final offerDoc = await _offersCollection.doc(offerId).get();
      if (!offerDoc.exists) return false;

      final offerData = offerDoc.data() as Map<String, dynamic>;
      if (offerData['chefId'] != user.uid) return false;
      if (offerData['status'] != ChefOfferStatus.pending.name) return false;

      await _offersCollection.doc(offerId).update({
        'status': ChefOfferStatus.withdrawn.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('Error withdrawing offer: $e');
      return false;
    }
  }

  /// Get chef's pending offers
  static Stream<List<ChefOffer>> getChefPendingOffers() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _offersCollection
        .where('chefId', isEqualTo: user.uid)
        .where('status', isEqualTo: ChefOfferStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          final offers = snapshot.docs
              .map((doc) => ChefOffer.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          offers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return offers;
        });
  }

  /// Get chef's all offers (history)
  static Stream<List<ChefOffer>> getChefAllOffers() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _offersCollection
        .where('chefId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final offers = snapshot.docs
              .map((doc) => ChefOffer.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          offers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return offers;
        });
  }

  // ==========================================
  // CHAT CONTROL
  // ==========================================

  /// Check if chat is enabled for a request
  static Future<bool> isChatEnabled(String requestId) async {
    try {
      final requestDoc = await _requestsCollection.doc(requestId).get();
      if (!requestDoc.exists) return false;

      final data = requestDoc.data() as Map<String, dynamic>;
      return data['chatEnabled'] == true &&
             data['status'] == CookingRequestStatus.confirmed.name;
    } catch (e) {
      return false;
    }
  }

  /// Get chat for confirmed booking
  static Future<String?> getChatForRequest(String requestId) async {
    try {
      final chatQuery = await _chatsCollection
          .where('requestId', isEqualTo: requestId)
          .limit(1)
          .get();

      if (chatQuery.docs.isNotEmpty) {
        return chatQuery.docs.first.id;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting chat: $e');
      return null;
    }
  }

  // ==========================================
  // EXPIRATION HANDLING
  // ==========================================

  /// Expire a single request by ID (called when timer runs out in UI)
  static Future<bool> expireRequest(String requestId) async {
    try {
      debugPrint('Expiring request: $requestId');

      // Get the request
      final requestDoc = await _requestsCollection.doc(requestId).get();
      if (!requestDoc.exists) {
        debugPrint('Request not found for expiration: $requestId');
        return false;
      }

      final data = requestDoc.data() as Map<String, dynamic>;

      // Only expire if still pending
      if (data['status'] != CookingRequestStatus.pending.name) {
        debugPrint('Request $requestId is not pending, status: ${data['status']}');
        return false;
      }

      // Update request status to expired
      await _requestsCollection.doc(requestId).update({
        'status': CookingRequestStatus.expired.name,
      });

      // Expire all related offers
      final offersQuery = await _offersCollection
          .where('requestId', isEqualTo: requestId)
          .where('status', isEqualTo: ChefOfferStatus.pending.name)
          .get();

      for (var offerDoc in offersQuery.docs) {
        await offerDoc.reference.update({
          'status': ChefOfferStatus.expired.name,
          'respondedAt': FieldValue.serverTimestamp(),
        });
      }

      debugPrint('Request $requestId expired successfully');
      return true;
    } catch (e) {
      debugPrint('Error expiring request $requestId: $e');
      return false;
    }
  }

  /// Expire old pending requests (to be called periodically or via Cloud Functions)
  static Future<void> expireOldRequests() async {
    try {
      final now = Timestamp.now();

      final expiredRequests = await _requestsCollection
          .where('status', isEqualTo: CookingRequestStatus.pending.name)
          .where('expiresAt', isLessThan: now)
          .get();

      final batch = _firestore.batch();

      for (var doc in expiredRequests.docs) {
        // Update request status
        batch.update(doc.reference, {
          'status': CookingRequestStatus.expired.name,
        });

        // Expire related offers
        final offers = await _offersCollection
            .where('requestId', isEqualTo: doc.id)
            .where('status', isEqualTo: ChefOfferStatus.pending.name)
            .get();

        for (var offer in offers.docs) {
          batch.update(offer.reference, {
            'status': ChefOfferStatus.expired.name,
            'respondedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
      debugPrint('Expired ${expiredRequests.docs.length} requests');
    } catch (e) {
      debugPrint('Error expiring requests: $e');
    }
  }

  // ==========================================
  // UTILITY METHODS
  // ==========================================

  /// Check if customer has active pending request
  static Future<bool> hasActivePendingRequest() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Simple query without orderBy to avoid index requirement
      final requests = await _requestsCollection
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: CookingRequestStatus.pending.name)
          .limit(1)
          .get();

      return requests.docs.isNotEmpty;
    } catch (e) {
      debugPrint('hasActivePendingRequest ERROR: $e');
      return false;
    }
  }

  /// Get active pending request ID (for InDrive-style flow)
  /// Also checks if request has expired and updates status accordingly
  static Future<String?> getActivePendingRequestId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      debugPrint('getActivePendingRequestId: Checking for user ${user.uid}');

      // Simple query without orderBy to avoid index requirement
      final requests = await _requestsCollection
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: CookingRequestStatus.pending.name)
          .limit(5)
          .get();

      debugPrint('getActivePendingRequestId: Found ${requests.docs.length} pending requests');

      if (requests.docs.isEmpty) return null;

      // Sort locally by createdAt and find a valid non-expired request
      final docs = requests.docs.toList();
      docs.sort((a, b) {
        final aTime = (a.data() as Map)['createdAt'];
        final bTime = (b.data() as Map)['createdAt'];
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return (bTime as Timestamp).compareTo(aTime as Timestamp);
      });

      // Check each request to find one that hasn't expired
      final now = DateTime.now();
      for (var doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final expiresAt = data['expiresAt'];

        DateTime expireTime;
        if (expiresAt is Timestamp) {
          expireTime = expiresAt.toDate();
        } else {
          continue; // Skip if no expiration time
        }

        // If this request is still valid (not expired)
        if (now.isBefore(expireTime)) {
          debugPrint('getActivePendingRequestId: Returning valid request ${doc.id}');
          return doc.id;
        } else {
          // Request has expired, update its status in background
          debugPrint('getActivePendingRequestId: Request ${doc.id} has expired, marking as expired');
          expireRequest(doc.id); // Don't await, let it run in background
        }
      }

      debugPrint('getActivePendingRequestId: No valid active requests found');
      return null;
    } catch (e) {
      debugPrint('getActivePendingRequestId ERROR: $e');
      return null;
    }
  }

  /// Get count of offers for a request
  static Future<int> getOffersCount(String requestId) async {
    final offers = await _offersCollection
        .where('requestId', isEqualTo: requestId)
        .where('status', isEqualTo: ChefOfferStatus.pending.name)
        .get();
    return offers.docs.length;
  }
}

