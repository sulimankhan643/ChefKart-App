import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'supabase_storage_service.dart';

/// ===========================================
/// ChefKart Commission Service
/// ===========================================
///
/// This service implements a real-world Cash on Delivery (COD) commission model
/// with EARNING CYCLE BASED BLOCKING.
///
/// KEY BUSINESS RULE:
/// "Chef lifetime earnings are permanent. Orders are blocked only when unpaid
/// cycle earnings reach 5000 PKR, and unblocked after commission settlement."
///
/// Business Logic:
/// - Customers pay the chef directly in cash when service is completed.
/// - The chef collects the full amount from the customer.
/// - ChefKart platform charges a commission (default 10%) on each completed order.
/// - Chef pays the accumulated commission to the platform via EasyPaisa.
/// - Commission payments require proof upload and admin approval.
///
/// Earning Cycle Logic:
/// - total_earnings: Lifetime earnings, NEVER reset
/// - current_cycle_earnings: Temporary bucket, resets after commission cleared
/// - When current_cycle_earnings >= 5000 PKR, next order is BLOCKED
/// - After commission payment approval, current_cycle_earnings resets to 0
/// - New cycle starts, chef can earn again from 0 to 5000 PKR
///
/// This model is commonly used in gig economy apps in Pakistan where:
/// - Digital payment adoption is limited
/// - Cash transactions are preferred
/// - Platform fees are collected separately from service providers
/// ===========================================

class CommissionService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Commission configuration
  // Platform takes 10% commission from each completed order
  static const double commissionPercentage = 10.0;

  // EasyPaisa account details for commission payment
  // These are the platform's official payment details
  static const String easypaisaNumber = '03439758616';
  static const String easypaisaAccountName = 'Ishtiaq Afzal';

  // EARNING CYCLE THRESHOLD - orders blocked when cycle earnings reach this limit
  // This is based on EARNINGS not commission
  static const double earningCycleThreshold = 5000.0;

  // Commission limit (kept for backward compatibility)
  static const double commissionLimit = earningCycleThreshold;

  // Collection references
  static CollectionReference get _usersCollection =>
      _firestore.collection('users');
  static CollectionReference get _commissionsCollection =>
      _firestore.collection('commission_payments');
  static CollectionReference get _bookingsCollection =>
      _firestore.collection('bookings');

  /// ===========================================
  /// COMMISSION CALCULATION
  /// ===========================================

  /// Calculate commission for a given order amount
  /// Returns a map with commission_amount and chef_earning
  static Map<String, double> calculateCommission(double orderAmount) {
    final commissionAmount = (orderAmount * commissionPercentage) / 100;
    final chefEarning = orderAmount - commissionAmount;

    return {
      'commission_amount': double.parse(commissionAmount.toStringAsFixed(2)),
      'chef_earning': double.parse(chefEarning.toStringAsFixed(2)),
      'order_amount': orderAmount,
      'commission_percentage': commissionPercentage,
    };
  }

  /// Process commission when an order is marked as completed
  /// This is called automatically when chef marks a booking as complete
  ///
  /// EARNING CYCLE BASED BLOCKING LOGIC:
  /// - Add order amount to total_earnings (LIFETIME - NEVER reset)
  /// - Add order amount to current_cycle_earnings (resets after commission paid)
  /// - Calculate commission from current_cycle_earnings
  /// - If current_cycle_earnings >= 5000 PKR, set is_order_blocked = true
  ///
  /// NOTE: Even if a single order is 10,000 or 20,000 PKR:
  /// - Still allow that order to complete
  /// - Immediately block NEXT order
  static Future<bool> processOrderCommission({
    required String bookingId,
    required double orderAmount,
    required String chefId,
  }) async {
    try {
      debugPrint('CommissionService: Processing commission for booking $bookingId');

      final commissionData = calculateCommission(orderAmount);
      final commissionAmount = commissionData['commission_amount']!;
      final chefEarning = commissionData['chef_earning']!;

      // Update booking with commission details
      await _bookingsCollection.doc(bookingId).update({
        'commission_amount': commissionAmount,
        'chef_earning': chefEarning,
        'commission_percentage': commissionPercentage,
        'commission_processed': true,
        'commission_processed_at': FieldValue.serverTimestamp(),
      });

      // Update chef's commission tracking and earnings using CYCLE-BASED logic
      await _updateChefCommissionBalance(chefId, commissionAmount, orderAmount: orderAmount);

      debugPrint('CommissionService: Commission processed - Amount: Rs. $commissionAmount, Order: Rs. $orderAmount');
      return true;
    } catch (e) {
      debugPrint('CommissionService: Error processing commission: $e');
      return false;
    }
  }

  /// Update chef's commission balance and earnings in their user document
  ///
  /// EARNING CYCLE BASED BLOCKING IMPLEMENTATION:
  ///
  /// KEY BUSINESS RULE (add this as comment in code):
  /// "Chef lifetime earnings are permanent. Orders are blocked only when unpaid
  /// cycle earnings reach 5000 PKR, and unblocked after commission settlement."
  ///
  /// Data Model:
  /// - total_earnings: Lifetime earnings, NEVER reset
  /// - current_cycle_earnings: Temporary bucket for current commission cycle
  /// - commission_pending: Calculated from current_cycle_earnings (10%)
  /// - commission_paid: Total commission paid history
  /// - is_order_blocked: true when current_cycle_earnings >= 5000
  static Future<void> _updateChefCommissionBalance(String chefId, double commissionAmount, {double? orderAmount}) async {
    try {
      final chefDoc = await _usersCollection.doc(chefId).get();
      final chefData = chefDoc.data() as Map<String, dynamic>?;

      // Get current values
      final currentPending = (chefData?['commission_pending'] ?? 0.0).toDouble();
      final currentTotalEarnings = (chefData?['total_earnings'] ?? 0.0).toDouble();
      final currentCycleEarnings = (chefData?['current_cycle_earnings'] ?? 0.0).toDouble();

      // Calculate new values
      // NOTE: total_earnings is LIFETIME and is NEVER reset
      // NOTE: current_cycle_earnings tracks earnings until commission is paid
      final newPending = currentPending + commissionAmount;
      final newTotalEarnings = orderAmount != null
          ? currentTotalEarnings + orderAmount
          : currentTotalEarnings;
      final newCycleEarnings = orderAmount != null
          ? currentCycleEarnings + orderAmount
          : currentCycleEarnings;

      // Determine commission status and order blocking based on CYCLE EARNINGS
      // Orders are blocked when current_cycle_earnings >= 5000 PKR
      final status = newPending > 0 ? 'due' : 'clear';
      final shouldBlockOrders = newCycleEarnings >= earningCycleThreshold;

      await _usersCollection.doc(chefId).update({
        // Commission tracking (commission_pending is cleared on payment approval)
        'commission_pending': newPending,
        'commission_status': status,
        'commission_last_updated': FieldValue.serverTimestamp(),

        // Earnings tracking
        // total_earnings: LIFETIME - NEVER reset
        // current_cycle_earnings: Resets when commission is paid
        'total_earnings': newTotalEarnings,
        'current_cycle_earnings': newCycleEarnings,

        // Order blocking - based on CYCLE EARNINGS reaching threshold
        'is_order_blocked': shouldBlockOrders,
      });

      debugPrint('CommissionService: Chef $chefId updated:');
      debugPrint('  - Pending commission: Rs. $newPending');
      debugPrint('  - Total earnings (lifetime): Rs. $newTotalEarnings');
      debugPrint('  - Current cycle earnings: Rs. $newCycleEarnings');
      debugPrint('  - Orders blocked: $shouldBlockOrders (threshold: $earningCycleThreshold)');
    } catch (e) {
      debugPrint('CommissionService: Error updating chef commission balance: $e');
    }
  }

  /// ===========================================
  /// COMMISSION PAYMENT (Chef -> Platform)
  /// ===========================================

  /// Submit commission payment with proof
  /// Chef uploads EasyPaisa payment screenshot as proof
  static Future<bool> submitCommissionPayment({
    required double amount,
    required String transactionId,
    File? proofFile,
    Uint8List? proofBytes,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('CommissionService: No user logged in');
        return false;
      }

      debugPrint('CommissionService: Submitting commission payment of Rs. $amount');

      // Upload proof to Supabase
      String? proofUrl;
      if (proofFile != null || proofBytes != null) {
        proofUrl = await SupabaseStorageService.uploadCommissionProof(
          file: proofFile,
          bytes: proofBytes,
          userId: user.uid,
        );

        if (proofUrl == null) {
          debugPrint('CommissionService: Failed to upload payment proof');
          return false;
        }
        debugPrint('CommissionService: Proof uploaded successfully');
      }

      // Get current pending commission
      final userDoc = await _usersCollection.doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final pendingCommission = (userData?['commission_pending'] ?? 0.0).toDouble();

      // Create commission payment record
      final paymentRef = _commissionsCollection.doc();
      await paymentRef.set({
        'id': paymentRef.id,
        'chefId': user.uid,
        'chefName': userData?['name'] ?? 'Chef',
        'amount': amount,
        'pending_before_payment': pendingCommission,
        'payment_method': 'EasyPaisa',
        'easypaisa_number': easypaisaNumber,
        'easypaisa_account_name': easypaisaAccountName,
        'transaction_id': transactionId,
        'proof_url': proofUrl,
        'status': 'submitted', // submitted -> approved/rejected by admin
        'submitted_at': FieldValue.serverTimestamp(),
        'reviewed_at': null,
        'reviewed_by': null,
        'rejection_reason': null,
      });

      // Update chef's document with payment submission
      await _usersCollection.doc(user.uid).update({
        'commission_payment_pending': true,
        'commission_last_payment_id': paymentRef.id,
        'commission_last_payment_amount': amount,
        'commission_last_payment_submitted_at': FieldValue.serverTimestamp(),
      });

      debugPrint('CommissionService: Payment submitted successfully - ID: ${paymentRef.id}');
      return true;
    } catch (e) {
      debugPrint('CommissionService: Error submitting payment: $e');
      return false;
    }
  }

  /// ===========================================
  /// COMMISSION PAYMENT APPROVAL (Admin Action)
  /// ===========================================
  ///
  /// This method is called when admin approves a commission payment.
  /// IMPORTANT: This is the ONLY place where commission cycle is cleared.
  ///
  /// Commission Payment Approval Logic (EARNING CYCLE BASED):
  /// - Reset current_cycle_earnings = 0 (START NEW CYCLE)
  /// - Reset commission_pending = 0
  /// - Increase commission_paid by the paid amount
  /// - Set commission_status = "clear"
  /// - Set is_order_blocked = false (chef can receive new orders)
  ///
  /// ❌ DO NOT:
  /// - Reset total_earnings (it's lifetime income - NEVER RESET)
  /// - Delete order history
  /// - Modify past completed orders
  ///
  /// After this, chef starts a NEW EARNING CYCLE:
  /// - Orders are allowed again
  /// - Earnings count again from 0 → 5000 PKR
  /// - Same blocking rules apply every cycle
  static Future<bool> approveCommissionPayment({
    required String paymentId,
    required String chefId,
    required double paidAmount,
    String? adminId,
  }) async {
    try {
      debugPrint('CommissionService: Approving payment $paymentId for chef $chefId');

      // Use a transaction to ensure data consistency
      await _firestore.runTransaction((transaction) async {
        // Get current chef data
        final chefDoc = await transaction.get(_usersCollection.doc(chefId));
        final chefData = chefDoc.data() as Map<String, dynamic>?;

        if (chefData == null) {
          throw Exception('Chef document not found');
        }

        // Get current values
        final currentPaid = (chefData['commission_paid'] ?? 0.0).toDouble();
        final totalEarnings = (chefData['total_earnings'] ?? 0.0).toDouble();
        final currentCycleEarnings = (chefData['current_cycle_earnings'] ?? 0.0).toDouble();

        // Calculate new values
        // NOTE: total_earnings is NEVER modified here - it's lifetime income
        // NOTE: current_cycle_earnings is RESET to 0 to start new cycle
        final newPending = 0.0; // Full reset - commission cleared
        final newPaid = currentPaid + paidAmount;

        // New cycle starts - orders are unblocked
        const newStatus = 'clear';
        const shouldBlockOrders = false;

        // Update chef document
        // IMPORTANT: total_earnings is NOT touched - only cycle is reset
        transaction.update(_usersCollection.doc(chefId), {
          // Commission tracking - cleared
          'commission_pending': newPending,
          'commission_paid': newPaid,
          'commission_status': newStatus,
          'commission_payment_pending': false,

          // CYCLE RESET - Start new earning cycle
          'current_cycle_earnings': 0.0, // RESET to 0 for new cycle

          // Order blocking - cleared
          'is_order_blocked': shouldBlockOrders,
          'commission_last_cleared_at': FieldValue.serverTimestamp(),

          // NOTE: total_earnings is intentionally NOT modified
          // Earnings represent lifetime income and are NEVER reset
        });

        // Update payment record
        transaction.update(_commissionsCollection.doc(paymentId), {
          'status': 'approved',
          'reviewed_at': FieldValue.serverTimestamp(),
          'reviewed_by': adminId,
          'pending_after_approval': newPending,
          'cycle_earnings_before_reset': currentCycleEarnings, // For audit trail
        });

        debugPrint('CommissionService: Payment approved successfully - NEW CYCLE STARTED');
        debugPrint('  - Commission cleared: Rs. $paidAmount');
        debugPrint('  - Cycle earnings reset: Rs. $currentCycleEarnings → Rs. 0');
        debugPrint('  - Total paid: Rs. $newPaid');
        debugPrint('  - Total earnings (unchanged): Rs. $totalEarnings');
        debugPrint('  - Orders blocked: $shouldBlockOrders');
      });

      return true;
    } catch (e) {
      debugPrint('CommissionService: Error approving payment: $e');
      return false;
    }
  }

  /// Reject commission payment
  /// Chef can re-upload payment proof after rejection
  static Future<bool> rejectCommissionPayment({
    required String paymentId,
    required String chefId,
    String? adminId,
    String? rejectionReason,
  }) async {
    try {
      debugPrint('CommissionService: Rejecting payment $paymentId');

      // Update payment record
      await _commissionsCollection.doc(paymentId).update({
        'status': 'rejected',
        'reviewed_at': FieldValue.serverTimestamp(),
        'reviewed_by': adminId,
        'rejection_reason': rejectionReason,
      });

      // Update chef document to allow re-upload
      await _usersCollection.doc(chefId).update({
        'commission_payment_pending': false,
        'commission_last_rejection_reason': rejectionReason,
        // NOTE: commission_pending is NOT cleared - chef still owes the amount
        // NOTE: total_earnings is NOT modified
      });

      debugPrint('CommissionService: Payment rejected - reason: $rejectionReason');
      return true;
    } catch (e) {
      debugPrint('CommissionService: Error rejecting payment: $e');
      return false;
    }
  }

  /// ===========================================
  /// COMMISSION DATA RETRIEVAL
  /// ===========================================

  /// Get chef's commission summary
  static Future<Map<String, dynamic>> getChefCommissionSummary() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return _getDefaultCommissionSummary();
      }

      final userDoc = await _usersCollection.doc(user.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>?;

      if (userData == null) {
        return _getDefaultCommissionSummary();
      }

      // Get current cycle earnings for threshold checking
      final currentCycleEarnings = (userData['current_cycle_earnings'] ?? 0.0).toDouble();
      final commissionPending = (userData['commission_pending'] ?? 0.0).toDouble();

      // IMPORTANT: total_earnings is lifetime income and is NEVER reset
      // current_cycle_earnings resets when commission is paid
      // Orders are blocked when current_cycle_earnings >= EARNING_CYCLE_THRESHOLD (5000 PKR)
      return {
        // Earnings (LIFETIME - NEVER RESET)
        'total_earnings': (userData['total_earnings'] ?? 0.0).toDouble(),

        // Current Cycle Earnings (RESETS after commission paid)
        'current_cycle_earnings': currentCycleEarnings,

        // Commission tracking
        'commission_pending': commissionPending,
        'commission_paid': (userData['commission_paid'] ?? 0.0).toDouble(),
        'commission_status': userData['commission_status'] ?? 'clear',
        'commission_payment_pending': userData['commission_payment_pending'] ?? false,
        'last_payment_amount': (userData['commission_last_payment_amount'] ?? 0.0).toDouble(),

        // Order blocking - based on CYCLE EARNINGS threshold (5000 PKR)
        // IMPORTANT: Only block if cycle earnings >= threshold AND commission is pending
        // After payment approval, commission_pending = 0 and current_cycle_earnings = 0
        // So orders should NOT be blocked after payment
        'should_block_orders': currentCycleEarnings >= earningCycleThreshold && commissionPending > 0,
        'is_order_blocked': userData['is_order_blocked'] ?? false,

        // Configuration
        'earning_cycle_threshold': earningCycleThreshold,
        'commission_limit': commissionLimit,
        'commission_percentage': commissionPercentage,

        // Cycle progress info
        'cycle_progress_percentage': (currentCycleEarnings / earningCycleThreshold * 100).clamp(0.0, 100.0),
        'earnings_until_block': (earningCycleThreshold - currentCycleEarnings).clamp(0.0, earningCycleThreshold),
      };
    } catch (e) {
      debugPrint('CommissionService: Error getting commission summary: $e');
      return _getDefaultCommissionSummary();
    }
  }

  static Map<String, dynamic> _getDefaultCommissionSummary() {
    return {
      // Earnings (LIFETIME - NEVER RESET)
      'total_earnings': 0.0,

      // Current Cycle Earnings (RESETS after commission paid)
      'current_cycle_earnings': 0.0,

      // Commission tracking
      'commission_pending': 0.0,
      'commission_paid': 0.0,
      'commission_status': 'clear',
      'commission_payment_pending': false,
      'last_payment_amount': 0.0,

      // Order blocking
      'should_block_orders': false,
      'is_order_blocked': false,

      // Configuration
      'earning_cycle_threshold': earningCycleThreshold,
      'commission_limit': commissionLimit,
      'commission_percentage': commissionPercentage,

      // Cycle progress info
      'cycle_progress_percentage': 0.0,
      'earnings_until_block': earningCycleThreshold,
    };
  }

  /// Get chef's commission payment history
  static Stream<List<Map<String, dynamic>>> getChefPaymentHistory() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _commissionsCollection
        .where('chefId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final payments = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
              .toList();

          // Sort by submitted_at descending
          payments.sort((a, b) {
            final aTime = a['submitted_at'] as Timestamp?;
            final bTime = b['submitted_at'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          return payments;
        });
  }

  /// Get completed bookings with commission details for chef
  static Future<List<Map<String, dynamic>>> getChefBookingsWithCommission() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final snapshot = await _bookingsCollection
          .where('chefId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'completed')
          .get();

      final bookings = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
          // Ensure commission fields exist
          'commission_amount': data['commission_amount'] ??
              calculateCommission((data['price'] ?? data['total'] ?? 0).toDouble())['commission_amount'],
          'chef_earning': data['chef_earning'] ??
              calculateCommission((data['price'] ?? data['total'] ?? 0).toDouble())['chef_earning'],
        };
      }).toList();

      // Sort by completedAt descending
      bookings.sort((a, b) {
        final aTime = a['completedAt'] as Timestamp?;
        final bTime = b['completedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return bookings;
    } catch (e) {
      debugPrint('CommissionService: Error getting bookings with commission: $e');
      return [];
    }
  }

  /// ===========================================
  /// ORDER BLOCKING CHECK
  /// ===========================================

  /// Check if chef should be blocked from receiving new orders
  /// Returns true if pending commission exceeds limit
  static Future<bool> shouldBlockNewOrders() async {
    try {
      final summary = await getChefCommissionSummary();
      return summary['should_block_orders'] == true;
    } catch (e) {
      debugPrint('CommissionService: Error checking order block status: $e');
      return false;
    }
  }

  /// Get commission warning message if applicable
  /// Based on EARNING CYCLE threshold (5000 PKR)
  static Future<String?> getCommissionWarningMessage() async {
    try {
      final summary = await getChefCommissionSummary();
      final cycleEarnings = summary['current_cycle_earnings'] as double;
      final threshold = summary['earning_cycle_threshold'] as double;
      final pending = summary['commission_pending'] as double;

      // Only show limit reached message if BOTH cycle earnings >= threshold AND commission pending
      // After payment, both values reset so no warning should show
      if (cycleEarnings >= threshold && pending > 0) {
        return 'Your cycle earnings (Rs. ${cycleEarnings.toStringAsFixed(0)}) have reached the Rs. ${threshold.toStringAsFixed(0)} limit. Pay commission (Rs. ${pending.toStringAsFixed(0)}) to continue receiving orders.';
      } else if (cycleEarnings >= threshold * 0.8 && pending > 0) {
        final remaining = threshold - cycleEarnings;
        return 'Warning: Only Rs. ${remaining.toStringAsFixed(0)} left in this cycle. Pay commission soon to avoid order restrictions.';
      } else if (cycleEarnings >= threshold * 0.6 && pending > 0) {
        return 'You have earned Rs. ${cycleEarnings.toStringAsFixed(0)} in this cycle. Commission pending: Rs. ${pending.toStringAsFixed(0)}';
      } else if (pending > 0 && cycleEarnings > 0) {
        return 'Current cycle: Rs. ${cycleEarnings.toStringAsFixed(0)} / Rs. ${threshold.toStringAsFixed(0)}. Commission pending: Rs. ${pending.toStringAsFixed(0)}';
      }

      return null;
    } catch (e) {
      debugPrint('CommissionService: Error getting warning message: $e');
      return null;
    }
  }

  /// Stream chef's commission data for real-time updates
  ///
  /// EARNING CYCLE BASED BLOCKING:
  /// - total_earnings: LIFETIME income, NEVER reset
  /// - current_cycle_earnings: Temporary bucket, resets after commission paid
  /// - Orders blocked when current_cycle_earnings >= 5000 PKR
  static Stream<Map<String, dynamic>> streamChefCommissionData() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value(_getDefaultCommissionSummary());
    }

    return _usersCollection.doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return _getDefaultCommissionSummary();

      final data = doc.data() as Map<String, dynamic>;
      final currentCycleEarnings = (data['current_cycle_earnings'] ?? 0.0).toDouble();
      final commissionPending = (data['commission_pending'] ?? 0.0).toDouble();

      return {
        // Earnings (LIFETIME - NEVER RESET)
        'total_earnings': (data['total_earnings'] ?? 0.0).toDouble(),

        // Current Cycle Earnings (RESETS after commission paid)
        'current_cycle_earnings': currentCycleEarnings,

        // Commission tracking
        'commission_pending': commissionPending,
        'commission_paid': (data['commission_paid'] ?? 0.0).toDouble(),
        'commission_status': data['commission_status'] ?? 'clear',
        'commission_payment_pending': data['commission_payment_pending'] ?? false,

        // Order blocking - based on CYCLE EARNINGS threshold AND commission pending
        // IMPORTANT: Only block if cycle earnings >= threshold AND commission is pending
        // After payment approval, both values reset to 0 so orders are NOT blocked
        'should_block_orders': currentCycleEarnings >= earningCycleThreshold && commissionPending > 0,
        'is_order_blocked': data['is_order_blocked'] ?? false,

        // Configuration
        'earning_cycle_threshold': earningCycleThreshold,

        // Cycle progress info
        'cycle_progress_percentage': (currentCycleEarnings / earningCycleThreshold * 100).clamp(0.0, 100.0),
        'earnings_until_block': (earningCycleThreshold - currentCycleEarnings).clamp(0.0, earningCycleThreshold),
      };
    });
  }
}
