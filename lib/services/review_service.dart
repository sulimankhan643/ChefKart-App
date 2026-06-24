import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/review.dart';

/// Service for handling ratings and reviews
class ReviewService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection references
  static CollectionReference get _reviewsCollection =>
      _firestore.collection('reviews');
  static CollectionReference get _usersCollection =>
      _firestore.collection('users');
  static CollectionReference get _bookingsCollection =>
      _firestore.collection('bookings');

  // ==========================================
  // CUSTOMER SIDE - Submit Review
  // ==========================================

  /// Customer submits a review for chef after completed booking
  static Future<bool> submitReview({
    required String chefId,
    required String bookingId,
    required int rating,
    String review = '',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // Validate rating
      if (rating < 1 || rating > 5) {
        debugPrint('Invalid rating: $rating');
        return false;
      }

      // Check if booking exists and belongs to this customer
      final bookingDoc = await _bookingsCollection.doc(bookingId).get();
      final bookingData = bookingDoc.data() as Map<String, dynamic>?;

      if (bookingData == null || bookingData['customerId'] != user.uid) {
        debugPrint('Booking not found or not owned by user');
        return false;
      }

      // Check if booking is completed
      if (bookingData['status'] != 'completed') {
        debugPrint('Booking not completed yet');
        return false;
      }

      // Check if already reviewed
      if (bookingData['reviewed'] == true) {
        debugPrint('Booking already reviewed');
        return false;
      }

      // Get customer details
      final customerDoc = await _usersCollection.doc(user.uid).get();
      final customerData = customerDoc.data() as Map<String, dynamic>?;

      // Create review document
      final reviewRef = _reviewsCollection.doc();

      // Start batch for atomic updates
      final batch = _firestore.batch();

      // Add review
      batch.set(reviewRef, {
        'chefId': chefId,
        'customerId': user.uid,
        'customerName': customerData?['name'] ?? 'Customer',
        'customerImage': customerData?['image'] ?? '',
        'bookingId': bookingId,
        'rating': rating,
        'review': review,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mark booking as reviewed
      batch.update(_bookingsCollection.doc(bookingId), {
        'reviewed': true,
        'reviewId': reviewRef.id,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      // Update chef's rating stats
      await _updateChefRating(chefId, rating, batch);

      await batch.commit();

      debugPrint('Review submitted successfully: ${reviewRef.id}');
      return true;
    } catch (e) {
      debugPrint('Error submitting review: $e');
      return false;
    }
  }

  /// Update chef's average rating (called after new review)
  static Future<void> _updateChefRating(
    String chefId,
    int newRating,
    WriteBatch batch,
  ) async {
    try {
      final chefDoc = await _usersCollection.doc(chefId).get();
      final chefData = chefDoc.data() as Map<String, dynamic>?;

      if (chefData == null) return;

      final currentRating = (chefData['rating'] ?? 0.0).toDouble();
      final currentCount = (chefData['reviewCount'] ?? 0) as int;

      // Calculate new average
      final totalRating = currentRating * currentCount + newRating;
      final newCount = currentCount + 1;
      final newAverage = totalRating / newCount;

      // Update chef profile with new rating
      batch.update(_usersCollection.doc(chefId), {
        'rating': double.parse(newAverage.toStringAsFixed(1)),
        'reviewCount': newCount,
        'lastReviewAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating chef rating: $e');
    }
  }

  // ==========================================
  // GET REVIEWS
  // ==========================================

  /// Get all reviews for a chef (sorted by newest first)
  static Stream<List<Review>> getChefReviews(String chefId) {
    return _reviewsCollection
        .where('chefId', isEqualTo: chefId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Review.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  /// Get paginated reviews for a chef
  static Future<List<Review>> getChefReviewsPaginated(
    String chefId, {
    int limit = 10,
    DocumentSnapshot? lastDoc,
  }) async {
    try {
      Query query = _reviewsCollection
          .where('chefId', isEqualTo: chefId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Review.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error getting paginated reviews: $e');
      return [];
    }
  }

  /// Get review for a specific booking
  static Future<Review?> getBookingReview(String bookingId) async {
    try {
      final snapshot = await _reviewsCollection
          .where('bookingId', isEqualTo: bookingId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return Review.fromMap(
          snapshot.docs.first.id,
          snapshot.docs.first.data() as Map<String, dynamic>,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Error getting booking review: $e');
      return null;
    }
  }

  /// Get chef's rating breakdown (count per star)
  static Future<Map<int, int>> getChefRatingBreakdown(String chefId) async {
    try {
      final snapshot = await _reviewsCollection
          .where('chefId', isEqualTo: chefId)
          .get();

      Map<int, int> breakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final rating = data['rating'] as int? ?? 0;
        if (rating >= 1 && rating <= 5) {
          breakdown[rating] = (breakdown[rating] ?? 0) + 1;
        }
      }

      return breakdown;
    } catch (e) {
      debugPrint('Error getting rating breakdown: $e');
      return {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    }
  }

  /// Get recent reviews for a chef (limited)
  static Future<List<Review>> getChefRecentReviews(String chefId, {int limit = 5}) async {
    try {
      final snapshot = await _reviewsCollection
          .where('chefId', isEqualTo: chefId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => Review.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error getting recent reviews: $e');
      return [];
    }
  }

  // ==========================================
  // CUSTOMER'S REVIEWS HISTORY
  // ==========================================

  /// Get all reviews submitted by current customer
  static Stream<List<Review>> getMyReviews() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _reviewsCollection
        .where('customerId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Review.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  // ==========================================
  // HELPERS
  // ==========================================

  /// Check if customer can review a booking
  static Future<bool> canReviewBooking(String bookingId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final bookingDoc = await _bookingsCollection.doc(bookingId).get();
      final bookingData = bookingDoc.data() as Map<String, dynamic>?;

      if (bookingData == null) return false;
      if (bookingData['customerId'] != user.uid) return false;
      if (bookingData['status'] != 'completed') return false;
      if (bookingData['reviewed'] == true) return false;

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get total review count for chef
  static Future<int> getChefReviewCount(String chefId) async {
    try {
      final snapshot = await _reviewsCollection
          .where('chefId', isEqualTo: chefId)
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}

