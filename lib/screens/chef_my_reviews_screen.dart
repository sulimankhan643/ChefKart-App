import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/cached_chef_image.dart';

/// Chef Reviews Screen - Shows all ratings and reviews received by the chef
class ChefMyReviewsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ChefMyReviewsScreen({super.key, this.onBack});

  @override
  State<ChefMyReviewsScreen> createState() => _ChefMyReviewsScreenState();
}

class _ChefMyReviewsScreenState extends State<ChefMyReviewsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  double _averageRating = 0;
  int _totalReviews = 0;
  Map<int, int> _ratingBreakdown = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Get chef data for overall rating
      final chefDoc = await _firestore.collection('users').doc(uid).get();
      if (chefDoc.exists) {
        final data = chefDoc.data()!;
        _averageRating = (data['rating'] ?? 0).toDouble();
        _totalReviews = data['reviewCount'] ?? 0;
      }

      // Get all reviews
      final reviewsSnapshot = await _firestore
          .collection('reviews')
          .where('chefId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .get();

      // Calculate rating breakdown
      Map<int, int> breakdown = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
      List<Map<String, dynamic>> reviews = [];

      for (var doc in reviewsSnapshot.docs) {
        final data = doc.data();
        final rating = (data['rating'] ?? 0) as int;

        if (breakdown.containsKey(rating)) {
          breakdown[rating] = breakdown[rating]! + 1;
        }

        reviews.add({
          'id': doc.id,
          'customerName': data['customerName'] ?? 'Customer',
          'customerImage': data['customerImage'] ?? '',
          'rating': rating,
          'review': data['review'] ?? '',
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        });
      }

      if (mounted) {
        setState(() {
          _ratingBreakdown = breakdown;
          _reviews = reviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('My Reviews'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReviews,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Rating Summary Card
                    _buildRatingSummaryCard(),

                    // Rating Breakdown
                    _buildRatingBreakdown(),

                    // Reviews Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Customer Reviews',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_reviews.length} reviews',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),

                    // Reviews List
                    if (_reviews.isEmpty)
                      _buildEmptyState()
                    else
                      ..._reviews.map((review) => _buildReviewCard(review)),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRatingSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade400, Colors.orange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Big Rating Number
          Column(
            children: [
              Text(
                _averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Stars
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return Icon(
                    index < _averageRating.round()
                        ? Icons.star
                        : Icons.star_border,
                    color: Colors.white,
                    size: 24,
                  );
                }),
              ),
              const SizedBox(height: 8),
              Text(
                '$_totalReviews reviews',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBreakdown() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rating Breakdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(5, (index) {
            final stars = 5 - index;
            final count = _ratingBreakdown[stars] ?? 0;
            final percentage = _totalReviews > 0
                ? (count / _totalReviews * 100).round()
                : 0;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Stars label
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$stars',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Icon(Icons.star, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  // Progress bar
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getBarColor(stars),
                        ),
                        minHeight: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Count
                  SizedBox(
                    width: 40,
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Color _getBarColor(int stars) {
    switch (stars) {
      case 5:
        return Colors.green;
      case 4:
        return Colors.lightGreen;
      case 3:
        return Colors.amber;
      case 2:
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.rate_review_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No reviews yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Customer reviews will appear here after completed bookings',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final createdAt = review['createdAt'] as DateTime?;
    final timeAgo = createdAt != null ? _getTimeAgo(createdAt) : '';
    final rating = review['rating'] as int;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CachedChefAvatar(
                  imageUrl: review['customerImage'],
                  name: review['customerName'],
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review['customerName'] ?? 'Customer',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getRatingColor(rating).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        size: 16,
                        color: _getRatingColor(rating),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$rating',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getRatingColor(rating),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Review Text
            if (review['review'] != null && review['review'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review['review'],
                style: TextStyle(
                  color: Colors.grey[800],
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating >= 3) return Colors.amber;
    return Colors.red;
  }

  String _getTimeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}mo ago';
    } else {
      return '${(diff.inDays / 365).floor()}y ago';
    }
  }
}

