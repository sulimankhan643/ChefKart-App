// filepath: d:\flutter_projects\chef_kart\lib\services\rating_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/review.dart';

class RatingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Submit a new review for a chef
  static Future<bool> submitReview({
    required String chefId,
    required String bookingId,
    required int rating,
    String review = '',
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      // Get customer name from Firestore
      final customerDoc = await _firestore.collection('users').doc(user.uid).get();
      final customerName = customerDoc.data()?['name'] ?? 'Customer';
      final customerImage = customerDoc.data()?['profileImage'] ?? customerDoc.data()?['image'] ?? '';

      // Create review document
      final reviewRef = _firestore.collection('reviews').doc();
      final reviewObj = Review(
        id: reviewRef.id,
        chefId: chefId,
        customerId: user.uid,
        customerName: customerName,
        customerImage: customerImage,
        bookingId: bookingId,
        rating: rating,
        review: review,
        createdAt: DateTime.now(),
      );

      await reviewRef.set(reviewObj.toMap());

      // Update chef's average rating
      await _updateChefRating(chefId);

      // Mark booking as reviewed
      await _firestore.collection('bookings').doc(bookingId).update({
        'reviewed': true,
        'reviewId': reviewRef.id,
      });

      return true;
    } catch (e) {
      debugPrint('Error submitting review: $e');
      return false;
    }
  }

  /// Update chef's average rating based on all reviews
  static Future<void> _updateChefRating(String chefId) async {
    try {
      // Get all reviews for this chef
      final reviewsSnapshot = await _firestore
          .collection('reviews')
          .where('chefId', isEqualTo: chefId)
          .get();

      if (reviewsSnapshot.docs.isEmpty) return;

      // Calculate average rating
      double totalRating = 0;
      for (var doc in reviewsSnapshot.docs) {
        totalRating += (doc.data()['rating'] as int).toDouble();
      }
      final averageRating = totalRating / reviewsSnapshot.docs.length;
      final reviewCount = reviewsSnapshot.docs.length;

      // Update chef document
      await _firestore.collection('users').doc(chefId).update({
        'rating': double.parse(averageRating.toStringAsFixed(1)),
        'reviewCount': reviewCount,
      });
    } catch (e) {
      debugPrint('Error updating chef rating: $e');
    }
  }

  /// Get all reviews for a chef
  static Stream<List<Review>> getChefReviews(String chefId) {
    return _firestore
        .collection('reviews')
        .where('chefId', isEqualTo: chefId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Review.fromMap(doc.id, doc.data()))
            .toList());
  }

  /// Get reviews list (non-stream)
  static Future<List<Review>> getChefReviewsList(String chefId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('chefId', isEqualTo: chefId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Review.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error getting reviews: $e');
      return [];
    }
  }

  /// Check if user has already reviewed this booking
  static Future<bool> hasReviewed(String bookingId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final snapshot = await _firestore
          .collection('reviews')
          .where('bookingId', isEqualTo: bookingId)
          .where('customerId', isEqualTo: user.uid)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
