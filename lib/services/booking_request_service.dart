import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/booking_request.dart';
import 'onesignal_service.dart';
import 'commission_service.dart';
import 'chat_service.dart';

/// Service for handling InDrive-style booking requests
class BookingRequestService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  static CollectionReference get _requestsCollection =>
      _firestore.collection('bookingRequests');
  static CollectionReference get _bookingsCollection =>
      _firestore.collection('bookings');
  static CollectionReference get _usersCollection =>
      _firestore.collection('users');

  // ==========================================
  // CUSTOMER SIDE - Send Request
  // ==========================================

  /// Customer sends a booking request to chef
  static Future<String?> sendRequest({
    required String chefId,
    required String serviceType,
    required String date,
    required String time,
    required String location,
    required String address,
    required int guestCount,
    required int offeredPrice,
    String note = '',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      debugPrint('=== SENDING REQUEST ===');
      debugPrint('Received chefId: $chefId');
      debugPrint('Customer ID: ${user.uid}');

      // Fetch customer and chef details in parallel for faster order placement
      final results = await Future.wait([
        _usersCollection.doc(user.uid).get(),
        _usersCollection.doc(chefId).get(),
      ]);
      final customerDoc = results[0];
      final chefDoc = results[1];
      final customerData = customerDoc.data() as Map<String, dynamic>?;
      final chefData = chefDoc.data() as Map<String, dynamic>?;

      debugPrint('Chef doc exists: ${chefDoc.exists}');
      debugPrint('Chef data: $chefData');

      if (customerData == null || chefData == null) {
        debugPrint('Error: Customer or Chef data is null');
        return null;
      }

      // Create request document
      final requestRef = _requestsCollection.doc();

      final requestData = {
        'chefId': chefId,  // This should be the Firebase Auth UID of chef
        'chefName': chefData['name'] ?? '',
        'chefImage': chefData['image'] ?? '',
        'customerId': user.uid,
        'customerName': customerData['name'] ?? 'Customer',
        'customerPhone': customerData['phone'] ?? '',
        'customerImage': customerData['image'] ?? '',
        'serviceType': serviceType,
        'date': date,
        'time': time,
        'location': location,
        'address': address,
        'guestCount': guestCount,
        'offeredPrice': offeredPrice,
        'note': note,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
      };

      debugPrint('Request data being saved: $requestData');

      await requestRef.set(requestData);

      debugPrint('Booking request sent successfully: ${requestRef.id}');
      return requestRef.id;
    } catch (e) {
      debugPrint('Error sending booking request: $e');
      return null;
    }
  }

  /// Customer cancels their pending request
  static Future<bool> cancelRequest(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Verify ownership
      final requestDoc = await _requestsCollection.doc(requestId).get();
      final requestData = requestDoc.data() as Map<String, dynamic>?;

      if (requestData == null || requestData['customerId'] != user.uid) {
        return false;
      }

      // Only cancel if pending
      if (requestData['status'] != 'pending') {
        return false;
      }

      await _requestsCollection.doc(requestId).update({
        'status': 'cancelled_by_customer',
        'respondedAt': FieldValue.serverTimestamp(),
        'cancellationReason': 'Cancelled by customer before chef response',
      });

      return true;
    } catch (e) {
      debugPrint('Error cancelling request: $e');
      return false;
    }
  }

  /// Customer cancels an ACCEPTED booking (before service date)
  static Future<bool> cancelAcceptedBooking(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Get the request
      final requestDoc = await _requestsCollection.doc(requestId).get();
      final requestData = requestDoc.data() as Map<String, dynamic>?;

      if (requestData == null || requestData['customerId'] != user.uid) {
        return false;
      }

      // Only cancel if accepted
      if (requestData['status'] != 'accepted') {
        return false;
      }

      // Start batch for atomicity
      final batch = _firestore.batch();

      // Update request status
      batch.update(_requestsCollection.doc(requestId), {
        'status': 'cancelled_by_customer',
        'respondedAt': FieldValue.serverTimestamp(),
        'cancellationReason': 'Cancelled by customer after acceptance',
      });

      // Find and update the confirmed booking
      final bookingQuery = await _bookingsCollection
          .where('requestId', isEqualTo: requestId)
          .limit(1)
          .get();

      if (bookingQuery.docs.isNotEmpty) {
        batch.update(bookingQuery.docs.first.reference, {
          'status': 'cancelled',
          'cancelledBy': 'customer',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // TODO: Send notification to chef about cancellation

      debugPrint('Accepted booking cancelled by customer: $requestId');
      return true;
    } catch (e) {
      debugPrint('Error cancelling accepted booking: $e');
      return false;
    }
  }

  /// Chef cancels an ACCEPTED booking (before service date)
  static Future<bool> chefCancelBooking(String requestId, {String reason = ''}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Get the request
      final requestDoc = await _requestsCollection.doc(requestId).get();
      final requestData = requestDoc.data() as Map<String, dynamic>?;

      if (requestData == null || requestData['chefId'] != user.uid) {
        return false;
      }

      // Only cancel if accepted
      if (requestData['status'] != 'accepted') {
        return false;
      }

      // Start batch for atomicity
      final batch = _firestore.batch();

      // Update request status
      batch.update(_requestsCollection.doc(requestId), {
        'status': 'cancelled_by_chef',
        'respondedAt': FieldValue.serverTimestamp(),
        'cancellationReason': reason.isNotEmpty ? reason : 'Cancelled by chef',
      });

      // Find and update the confirmed booking
      final bookingQuery = await _bookingsCollection
          .where('requestId', isEqualTo: requestId)
          .limit(1)
          .get();

      if (bookingQuery.docs.isNotEmpty) {
        batch.update(bookingQuery.docs.first.reference, {
          'status': 'cancelled',
          'cancelledBy': 'chef',
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancellationReason': reason,
        });
      }

      await batch.commit();

      // TODO: Send notification to customer about cancellation

      debugPrint('Booking cancelled by chef: $requestId');
      return true;
    } catch (e) {
      debugPrint('Error chef cancelling booking: $e');
      return false;
    }
  }

  /// Get customer's booking requests (pending, accepted, rejected)
  static Stream<List<BookingRequest>> getCustomerRequests() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('customerId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => BookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Get customer's PENDING requests only (waiting for chef response)
  static Stream<List<Map<String, dynamic>>> getCustomerPendingRequests() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('customerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();

          // Sort locally by createdAt
          requests.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });

          return requests;
        });
  }

  // ==========================================
  // CHEF SIDE - Receive & Respond
  // ==========================================

  /// Get chef's pending booking requests (InDrive style cards)
  static Stream<List<BookingRequest>> getChefPendingRequests() {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('getChefPendingRequests: No user logged in');
      return Stream.value([]);
    }

    debugPrint('=== FETCHING CHEF PENDING REQUESTS ===');
    debugPrint('Chef UID: ${user.uid}');

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('chefId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          debugPrint('Found ${snapshot.docs.length} pending requests for chef ${user.uid}');
          for (var doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            debugPrint('Request: ${doc.id}, chefId in doc: ${data['chefId']}, status: ${data['status']}');
          }
          final requests = snapshot.docs
              .map((doc) => BookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Get chef's all requests (history)
  static Stream<List<BookingRequest>> getChefAllRequests() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _requestsCollection
        .where('chefId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => BookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
          // Sort locally by createdAt
          requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return requests;
        });
  }

  /// Chef accepts the booking request
  ///
  /// EARNING CYCLE BASED BLOCKING:
  /// Chef cannot accept requests if their current_cycle_earnings >= 5000 PKR
  /// They must pay commission to start a new cycle before accepting new orders.
  static Future<bool> acceptRequest(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('Accept failed: No user logged in');
        return false;
      }

      debugPrint('Attempting to accept request: $requestId by user: ${user.uid}');

      // CHECK FOR ORDER BLOCKING DUE TO EARNING CYCLE THRESHOLD
      // Orders are blocked when current_cycle_earnings >= 5000 PKR
      final shouldBlock = await CommissionService.shouldBlockNewOrders();
      if (shouldBlock) {
        debugPrint('Accept failed: Chef orders blocked - earning cycle threshold reached (5000 PKR)');
        debugPrint('Chef must pay commission to start new cycle before accepting new orders.');
        return false;
      }

      // Get the request
      final requestDoc = await _requestsCollection.doc(requestId).get();

      if (!requestDoc.exists) {
        debugPrint('Accept failed: Request document does not exist');
        return false;
      }

      final requestData = requestDoc.data() as Map<String, dynamic>?;

      if (requestData == null) {
        debugPrint('Accept failed: Request data is null');
        return false;
      }

      debugPrint('Request chefId: ${requestData['chefId']}, Current user: ${user.uid}');
      debugPrint('Request status: ${requestData['status']}');

      if (requestData['chefId'] != user.uid) {
        debugPrint('Accept failed: Chef ID mismatch');
        return false;
      }

      // Only accept if pending
      if (requestData['status'] != 'pending') {
        debugPrint('Accept failed: Status is not pending, it is: ${requestData['status']}');
        return false;
      }

      // Update request status to accepted
      await _requestsCollection.doc(requestId).update({
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Request status updated to accepted');

      // Create a confirmed booking
      await _bookingsCollection.add({
        'requestId': requestId,
        'chefId': requestData['chefId'],
        'chefName': requestData['chefName'],
        'chefImage': requestData['chefImage'],
        'customerId': requestData['customerId'],
        'customerName': requestData['customerName'],
        'customerPhone': requestData['customerPhone'],
        'customerImage': requestData['customerImage'],
        'serviceType': requestData['serviceType'],
        'date': requestData['date'],
        'time': requestData['time'],
        'location': requestData['location'],
        'address': requestData['address'],
        'guestCount': requestData['guestCount'],
        'price': requestData['offeredPrice'],
        'note': requestData['note'],
        'status': 'confirmed',
        'createdAt': FieldValue.serverTimestamp(),
        'reviewed': false,
      });

      // Send push notification to customer about acceptance
      await OneSignalService.notifyCustomerOrderAccepted(
        customerId: requestData['customerId'] ?? '',
        orderId: requestId,
        chefName: requestData['chefName'] ?? 'Chef',
      );

      debugPrint('Booking request accepted successfully: $requestId');
      return true;
    } catch (e) {
      debugPrint('Error accepting request: $e');
      return false;
    }
  }

  /// Chef rejects the booking request
  static Future<bool> rejectRequest(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('Reject failed: No user logged in');
        return false;
      }

      debugPrint('Attempting to reject request: $requestId by user: ${user.uid}');

      // Get the request
      final requestDoc = await _requestsCollection.doc(requestId).get();

      if (!requestDoc.exists) {
        debugPrint('Reject failed: Request document does not exist');
        return false;
      }

      final requestData = requestDoc.data() as Map<String, dynamic>?;

      if (requestData == null) {
        debugPrint('Reject failed: Request data is null');
        return false;
      }

      debugPrint('Request chefId: ${requestData['chefId']}, Current user: ${user.uid}');
      debugPrint('Request status: ${requestData['status']}');

      if (requestData['chefId'] != user.uid) {
        debugPrint('Reject failed: Chef ID mismatch');
        return false;
      }

      // Only reject if pending
      if (requestData['status'] != 'pending') {
        debugPrint('Reject failed: Status is not pending, it is: ${requestData['status']}');
        return false;
      }

      await _requestsCollection.doc(requestId).update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Booking request rejected successfully: $requestId');
      return true;
    } catch (e) {
      debugPrint('Error rejecting request: $e');
      return false;
    }
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  /// Get a single request by ID
  static Future<BookingRequest?> getRequestById(String requestId) async {
    try {
      final doc = await _requestsCollection.doc(requestId).get();
      if (doc.exists) {
        return BookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting request: $e');
      return null;
    }
  }

  /// Stream a single request for real-time status updates
  static Stream<BookingRequest?> streamRequest(String requestId) {
    return _requestsCollection.doc(requestId).snapshots().map((doc) {
      if (doc.exists) {
        return BookingRequest.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  /// Get count of pending requests for chef (for badge)
  static Stream<int> getChefPendingRequestCount() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _requestsCollection
        .where('chefId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Check if customer has pending request to this chef
  static Future<bool> hasPendingRequestToChef(String chefId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final snapshot = await _requestsCollection
          .where('customerId', isEqualTo: user.uid)
          .where('chefId', isEqualTo: chefId)
          .where('status', isEqualTo: 'pending')
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // CONFIRMED BOOKINGS - Customer Side
  // ==========================================

  /// Get customer's confirmed bookings
  static Stream<List<Map<String, dynamic>>> getCustomerBookings() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _bookingsCollection
        .where('customerId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final bookings = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
              .toList();
          // Sort locally by createdAt
          bookings.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });
          return bookings;
        });
  }

  /// Get customer's upcoming bookings (confirmed, not completed)
  static Stream<List<Map<String, dynamic>>> getCustomerUpcomingBookings() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _bookingsCollection
        .where('customerId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .map((snapshot) {
          final bookings = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
              .toList();
          // Sort locally by createdAt
          bookings.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });
          return bookings;
        });
  }

  // ==========================================
  // CONFIRMED BOOKINGS - Chef Side
  // ==========================================

  /// Get chef's confirmed bookings
  static Stream<List<Map<String, dynamic>>> getChefBookings() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _bookingsCollection
        .where('chefId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final bookings = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
              .toList();
          // Sort locally by createdAt
          bookings.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });
          return bookings;
        });
  }

  /// Get chef's upcoming bookings
  static Stream<List<Map<String, dynamic>>> getChefUpcomingBookings() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Simple query without orderBy to avoid index requirement
    return _bookingsCollection
        .where('chefId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .map((snapshot) {
          final bookings = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
              .toList();
          // Sort locally by createdAt
          bookings.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return (bTime as Timestamp).compareTo(aTime as Timestamp);
          });
          return bookings;
        });
  }

  /// Chef marks booking as completed
  /// This also processes platform commission (COD model)
  static Future<bool> markBookingCompleted(String bookingId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('markBookingCompleted: No user logged in');
        return false;
      }

      // Get booking
      final bookingDoc = await _bookingsCollection.doc(bookingId).get();
      final bookingData = bookingDoc.data() as Map<String, dynamic>?;

      if (bookingData == null) {
        debugPrint('markBookingCompleted: Booking not found: $bookingId');
        return false;
      }

      if (bookingData['chefId'] != user.uid) {
        debugPrint('markBookingCompleted: Not authorized. Chef ID mismatch.');
        return false;
      }

      if (bookingData['status'] != 'confirmed') {
        debugPrint('markBookingCompleted: Booking not confirmed. Status: ${bookingData['status']}');
        return false;
      }

      // Get order amount for commission calculation
      final orderAmount = (bookingData['price'] ?? bookingData['total'] ?? 0).toDouble();

      // Update booking status
      await _bookingsCollection.doc(bookingId).update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
      });

      // Process commission (COD model - chef collects cash, pays platform commission later)
      // Import and use CommissionService
      try {
        // Calculate and process commission
        final commissionResult = await _processOrderCommission(
          bookingId: bookingId,
          orderAmount: orderAmount,
          chefId: user.uid,
        );
        debugPrint('markBookingCompleted: Commission processed: $commissionResult');
      } catch (e) {
        debugPrint('markBookingCompleted: Commission processing error (non-blocking): $e');
        // Continue even if commission processing fails - it can be recalculated later
      }

      // Update the original request if exists
      final requestId = bookingData['requestId'];
      if (requestId != null) {
        // Try to update in bookingRequests first (direct booking flow)
        try {
          final directRequestDoc = await _requestsCollection.doc(requestId).get();
          if (directRequestDoc.exists) {
            await _requestsCollection.doc(requestId).update({
              'status': 'completed',
            });
            debugPrint('markBookingCompleted: Updated bookingRequests/$requestId');
          }
        } catch (e) {
          debugPrint('markBookingCompleted: Could not update bookingRequests: $e');
        }

        // Also try to update in cookingRequests (InDrive-style broadcast flow)
        try {
          final cookingRequestDoc = await _firestore.collection('cookingRequests').doc(requestId).get();
          if (cookingRequestDoc.exists) {
            await _firestore.collection('cookingRequests').doc(requestId).update({
              'status': 'completed',
            });
            debugPrint('markBookingCompleted: Updated cookingRequests/$requestId');
          }
        } catch (e) {
          debugPrint('markBookingCompleted: Could not update cookingRequests: $e');
        }
      }

      debugPrint('Booking marked as completed: $bookingId');

      // ===========================================
      // CLOSE CHAT AFTER ORDER COMPLETION
      // ===========================================
      // This prevents customer and chef from chatting after order is done
      // to avoid bypassing the app for future orders.
      // ===========================================
      try {
        final customerId = bookingData['customerId'] as String?;
        final chefId = bookingData['chefId'] as String?;

        if (customerId != null && chefId != null) {
          await ChatService.closeChat(
            customerId: customerId,
            chefId: chefId,
            bookingId: bookingId,
            closureReason: 'Order completed - Thank you for using ChefKart!',
          );
          debugPrint('markBookingCompleted: Chat closed between customer and chef');
        }
      } catch (e) {
        // Non-blocking - continue even if chat closing fails
        debugPrint('markBookingCompleted: Could not close chat (non-blocking): $e');
      }

      return true;
    } catch (e) {
      debugPrint('Error marking booking completed: $e');
      return false;
    }
  }

  /// ===========================================
  /// COMMISSION PROCESSING (COD Model)
  /// ===========================================
  ///
  /// This method delegates to CommissionService for proper commission processing
  /// with EARNING CYCLE BASED BLOCKING logic.
  ///
  /// Business Model:
  /// - Customer pays chef in cash (Cash on Delivery)
  /// - Chef collects full payment amount
  /// - Platform charges 10% commission
  /// - Commission is tracked and chef pays it separately via EasyPaisa
  /// - Orders are blocked when current_cycle_earnings >= 5000 PKR
  ///
  /// KEY BUSINESS RULE:
  /// "Chef lifetime earnings are permanent. Orders are blocked only when unpaid
  /// cycle earnings reach 5000 PKR, and unblocked after commission settlement."
  /// ===========================================

  static Future<bool> _processOrderCommission({
    required String bookingId,
    required double orderAmount,
    required String chefId,
  }) async {
    try {
      debugPrint('Processing commission for booking: $bookingId, amount: $orderAmount');

      // Use CommissionService for proper cycle-based tracking
      // This updates:
      // - total_earnings (LIFETIME - NEVER reset)
      // - current_cycle_earnings (resets when commission paid)
      // - commission_pending
      // - is_order_blocked (when cycle earnings >= 5000)
      final result = await CommissionService.processOrderCommission(
        bookingId: bookingId,
        orderAmount: orderAmount,
        chefId: chefId,
      );

      debugPrint('Commission processed via CommissionService: $result');
      return result;
    } catch (e) {
      debugPrint('Error processing commission: $e');
      return false;
    }
  }

  /// Get booking by ID
  static Future<Map<String, dynamic>?> getBookingById(String bookingId) async {
    try {
      final doc = await _bookingsCollection.doc(bookingId).get();
      if (doc.exists) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }
      return null;
    } catch (e) {
      debugPrint('Error getting booking: $e');
      return null;
    }
  }

  /// Stream a single booking for real-time updates
  static Stream<Map<String, dynamic>?> streamBooking(String bookingId) {
    return _bookingsCollection.doc(bookingId).snapshots().map((doc) {
      if (doc.exists) {
        return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
      }
      return null;
    });
  }

  /// Get booking count for chef
  static Stream<int> getChefActiveBookingCount() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(0);

    return _bookingsCollection
        .where('chefId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // ==========================================
  // REQUEST EXPIRY & AUTO-CLEANUP
  // ==========================================

  /// Check if request is expired (30 minutes without response)
  static bool isRequestExpired(DateTime createdAt, {int expiryMinutes = 30}) {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    return diff.inMinutes >= expiryMinutes;
  }

  /// Auto-expire old pending requests
  static Future<void> expireOldRequests() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final thirtyMinutesAgo = DateTime.now().subtract(const Duration(minutes: 30));

      // Get old pending requests for this chef
      final snapshot = await _requestsCollection
          .where('chefId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isLessThan: Timestamp.fromDate(thirtyMinutesAgo))
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'status': 'expired',
          'respondedAt': FieldValue.serverTimestamp(),
        });
      }

      if (snapshot.docs.isNotEmpty) {
        await batch.commit();
        debugPrint('Expired ${snapshot.docs.length} old requests');
      }
    } catch (e) {
      debugPrint('Error expiring old requests: $e');
    }
  }

  // ==========================================
  // STATISTICS & ANALYTICS
  // ==========================================

  /// Get chef's booking statistics
  static Future<Map<String, dynamic>> getChefStats() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final bookingsSnapshot = await _bookingsCollection
          .where('chefId', isEqualTo: user.uid)
          .get();

      int totalBookings = bookingsSnapshot.docs.length;
      int completedBookings = 0;
      int cancelledBookings = 0;
      int totalEarnings = 0;

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        final price = data['price'] as int? ?? 0;

        if (status == 'completed') {
          completedBookings++;
          totalEarnings += price;
        } else if (status.contains('cancelled')) {
          cancelledBookings++;
        }
      }

      // Get pending requests count
      final pendingSnapshot = await _requestsCollection
          .where('chefId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      return {
        'totalBookings': totalBookings,
        'completedBookings': completedBookings,
        'cancelledBookings': cancelledBookings,
        'pendingRequests': pendingSnapshot.docs.length,
        'totalEarnings': totalEarnings,
        'completionRate': totalBookings > 0
            ? (completedBookings / totalBookings * 100).toStringAsFixed(1)
            : '0.0',
      };
    } catch (e) {
      debugPrint('Error getting chef stats: $e');
      return {};
    }
  }

  /// Get customer's booking statistics
  static Future<Map<String, dynamic>> getCustomerStats() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final bookingsSnapshot = await _bookingsCollection
          .where('customerId', isEqualTo: user.uid)
          .get();

      int totalBookings = bookingsSnapshot.docs.length;
      int completedBookings = 0;
      int totalSpent = 0;
      Set<String> uniqueChefs = {};

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        final price = data['price'] as int? ?? 0;
        final chefId = data['chefId'] as String? ?? '';

        if (status == 'completed') {
          completedBookings++;
          totalSpent += price;
        }
        if (chefId.isNotEmpty) {
          uniqueChefs.add(chefId);
        }
      }

      return {
        'totalBookings': totalBookings,
        'completedBookings': completedBookings,
        'totalSpent': totalSpent,
        'uniqueChefs': uniqueChefs.length,
      };
    } catch (e) {
      debugPrint('Error getting customer stats: $e');
      return {};
    }
  }

  // ==========================================
  // REBOOKING & REPEAT ORDERS
  // ==========================================

  /// Rebook a previous booking (same chef, new date/time)
  static Future<String?> rebookPreviousBooking({
    required String previousBookingId,
    required String newDate,
    required String newTime,
    String? newNote,
  }) async {
    try {
      final booking = await getBookingById(previousBookingId);
      if (booking == null) return null;

      return sendRequest(
        chefId: booking['chefId'],
        serviceType: booking['serviceType'] ?? 'one-time',
        date: newDate,
        time: newTime,
        location: booking['location'] ?? '',
        address: booking['address'] ?? '',
        guestCount: booking['guestCount'] ?? 4,
        offeredPrice: booking['price'] ?? 0,
        note: newNote ?? booking['note'] ?? '',
      );
    } catch (e) {
      debugPrint('Error rebooking: $e');
      return null;
    }
  }

  // ==========================================
  // NOTIFICATION HELPERS (for FCM integration)
  // ==========================================

  /// Create notification data for new request (to chef)
  static Map<String, dynamic> createNewRequestNotification(BookingRequest request) {
    return {
      'type': 'new_request',
      'title': 'New Booking Request! 🎉',
      'body': '${request.customerName} wants to book you for ${request.date}',
      'data': {
        'requestId': request.id,
        'customerId': request.customerId,
        'screen': 'chef_requests',
      },
    };
  }

  /// Create notification data for accepted request (to customer)
  static Map<String, dynamic> createAcceptedNotification(BookingRequest request) {
    return {
      'type': 'request_accepted',
      'title': 'Booking Confirmed! ✅',
      'body': '${request.chefName} has accepted your booking for ${request.date}',
      'data': {
        'requestId': request.id,
        'chefId': request.chefId,
        'screen': 'booking_details',
      },
    };
  }

  /// Create notification data for rejected request (to customer)
  static Map<String, dynamic> createRejectedNotification(BookingRequest request) {
    return {
      'type': 'request_rejected',
      'title': 'Chef Unavailable',
      'body': '${request.chefName} is unavailable. Try another chef!',
      'data': {
        'requestId': request.id,
        'screen': 'find_chefs',
      },
    };
  }

  /// Create notification data for cancelled booking (to other party)
  static Map<String, dynamic> createCancellationNotification({
    required BookingRequest request,
    required bool cancelledByCustomer,
  }) {
    if (cancelledByCustomer) {
      return {
        'type': 'booking_cancelled',
        'title': 'Booking Cancelled',
        'body': '${request.customerName} has cancelled the booking for ${request.date}',
        'data': {
          'requestId': request.id,
          'screen': 'chef_bookings',
        },
      };
    } else {
      return {
        'type': 'booking_cancelled',
        'title': 'Booking Cancelled by Chef',
        'body': '${request.chefName} had to cancel. Please try another chef.',
        'data': {
          'requestId': request.id,
          'screen': 'find_chefs',
        },
      };
    }
  }

  /// Create notification data for completed booking (to customer)
  static Map<String, dynamic> createCompletedNotification(Map<String, dynamic> booking) {
    return {
      'type': 'booking_completed',
      'title': 'Service Completed! 🌟',
      'body': 'How was your experience with ${booking['chefName']}? Leave a review!',
      'data': {
        'bookingId': booking['id'],
        'chefId': booking['chefId'],
        'screen': 'leave_review',
      },
    };
  }

  // ==========================================
  // CHAT UNLOCK CHECK
  // ==========================================

  /// Check if chat is unlocked between customer and chef
  static Future<bool> isChatUnlocked(String chefId, String customerId) async {
    try {
      // Chat is unlocked if there's an accepted booking between them
      final snapshot = await _requestsCollection
          .where('chefId', isEqualTo: chefId)
          .where('customerId', isEqualTo: customerId)
          .where('status', isEqualTo: 'accepted')
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get active chat pairs for user
  static Future<List<Map<String, dynamic>>> getActiveChatPairs() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      // Get all accepted bookings for this user
      final asCustomer = await _requestsCollection
          .where('customerId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final asChef = await _requestsCollection
          .where('chefId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      List<Map<String, dynamic>> chatPairs = [];

      for (var doc in asCustomer.docs) {
        final data = doc.data() as Map<String, dynamic>;
        chatPairs.add({
          'partnerId': data['chefId'],
          'partnerName': data['chefName'],
          'partnerImage': data['chefImage'],
          'requestId': doc.id,
          'type': 'chef',
        });
      }

      for (var doc in asChef.docs) {
        final data = doc.data() as Map<String, dynamic>;
        chatPairs.add({
          'partnerId': data['customerId'],
          'partnerName': data['customerName'],
          'partnerImage': data['customerImage'],
          'requestId': doc.id,
          'type': 'customer',
        });
      }

      return chatPairs;
    } catch (e) {
      debugPrint('Error getting chat pairs: $e');
      return [];
    }
  }
}

