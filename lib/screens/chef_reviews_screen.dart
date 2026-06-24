import 'package:flutter/material.dart';
import '../models/review.dart';
import '../services/review_service.dart';
import '../widgets/cached_chef_image.dart';

/// Screen to display all reviews for a chef
class ChefReviewsScreen extends StatefulWidget {
  final String chefId;
  final String chefName;
  final double rating;
  final int reviewCount;
  final VoidCallback? onBack;

  const ChefReviewsScreen({
    super.key,
    required this.chefId,
    required this.chefName,
    required this.rating,
    required this.reviewCount,
    this.onBack,
  });

  @override
  State<ChefReviewsScreen> createState() => _ChefReviewsScreenState();
}

class _ChefReviewsScreenState extends State<ChefReviewsScreen> {
  Map<int, int> _ratingBreakdown = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
  bool _isLoadingBreakdown = true;

  @override
  void initState() {
    super.initState();
    _loadRatingBreakdown();
  }

  Future<void> _loadRatingBreakdown() async {
    final breakdown = await ReviewService.getChefRatingBreakdown(widget.chefId);
    if (mounted) {
      setState(() {
        _ratingBreakdown = breakdown;
        _isLoadingBreakdown = false;
      });
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
        title: const Text('Reviews'),
      ),
      body: Column(
        children: [
          // Rating Summary Card
          _buildRatingSummary(),

          // Reviews List
          Expanded(
            child: StreamBuilder<List<Review>>(
              stream: ReviewService.getChefReviews(widget.chefId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final reviews = snapshot.data ?? [];

                if (reviews.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reviews.length,
                  itemBuilder: (context, index) {
                    return _ReviewCard(review: reviews[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
      child: Row(
        children: [
          // Overall Rating
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Text(
                  widget.rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < widget.rating.round()
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: 20,
                    );
                  }),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.reviewCount} reviews',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          const SizedBox(width: 20),

          // Rating Breakdown
          Expanded(
            flex: 3,
            child: _isLoadingBreakdown
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: List.generate(5, (index) {
                      final star = 5 - index;
                      final count = _ratingBreakdown[star] ?? 0;
                      final percentage = widget.reviewCount > 0
                          ? count / widget.reviewCount
                          : 0.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text('$star'),
                            const Icon(Icons.star, size: 14, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LinearProgressIndicator(
                                value: percentage,
                                backgroundColor: Colors.grey[300],
                                valueColor: const AlwaysStoppedAnimation(Colors.amber),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rate_review_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No reviews yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to review ${widget.chefName}!',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

/// Individual review card widget
class _ReviewCard extends StatelessWidget {
  final Review review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  imageUrl: review.customerImage,
                  name: review.customerName,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.customerName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        review.timeAgo,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Rating
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRatingColor(review.rating).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star,
                        size: 16,
                        color: _getRatingColor(review.rating),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${review.rating}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getRatingColor(review.rating),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Review text
            if (review.review.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review.review,
                style: const TextStyle(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getRatingColor(int rating) {
    switch (rating) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.amber;
      case 4:
        return Colors.lightGreen;
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

/// Small widget to show recent reviews preview on chef profile
class RecentReviewsWidget extends StatelessWidget {
  final String chefId;
  final VoidCallback? onViewAll;

  const RecentReviewsWidget({
    super.key,
    required this.chefId,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Review>>(
      future: ReviewService.getChefRecentReviews(chefId, limit: 3),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final reviews = snapshot.data ?? [];

        if (reviews.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Reviews',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (onViewAll != null)
                    TextButton(
                      onPressed: onViewAll,
                      child: const Text('View All'),
                    ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reviews.length,
              itemBuilder: (context, index) {
                return _ReviewCard(review: reviews[index]);
              },
            ),
          ],
        );
      },
    );
  }
}

