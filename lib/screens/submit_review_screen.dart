import 'package:flutter/material.dart';
import '../services/review_service.dart';
import '../widgets/cached_chef_image.dart';

/// Screen for customer to submit review after completed booking
class SubmitReviewScreen extends StatefulWidget {
  final String bookingId;
  final String chefId;
  final String chefName;
  final String? chefImage;
  final VoidCallback onBack;
  final VoidCallback onSubmitted;

  const SubmitReviewScreen({
    super.key,
    required this.bookingId,
    required this.chefId,
    required this.chefName,
    this.chefImage,
    required this.onBack,
    required this.onSubmitted,
  });

  @override
  State<SubmitReviewScreen> createState() => _SubmitReviewScreenState();
}

class _SubmitReviewScreenState extends State<SubmitReviewScreen> {
  int _selectedRating = 0;
  final _reviewController = TextEditingController();
  bool _isLoading = false;

  final List<String> _ratingLabels = [
    '',
    'Poor',
    'Fair',
    'Good',
    'Very Good',
    'Excellent',
  ];

  final List<String> _ratingEmojis = [
    '',
    '😞',
    '😐',
    '🙂',
    '😊',
    '🤩',
  ];

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await ReviewService.submitReview(
      chefId: widget.chefId,
      bookingId: widget.bookingId,
      rating: _selectedRating,
      review: _reviewController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your review! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSubmitted();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to submit review. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Leave a Review'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Chef Info
            CachedChefAvatar(
              imageUrl: widget.chefImage,
              name: widget.chefName,
              radius: 40,
            ),
            const SizedBox(height: 16),
            Text(
              widget.chefName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How was your experience?',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 32),

            // Rating Stars
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = starIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      starIndex <= _selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      size: 48,
                      color: starIndex <= _selectedRating
                          ? Colors.amber
                          : Colors.grey[400],
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 16),

            // Rating Label with Emoji
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _selectedRating > 0
                  ? Column(
                      key: ValueKey(_selectedRating),
                      children: [
                        Text(
                          _ratingEmojis[_selectedRating],
                          style: const TextStyle(fontSize: 48),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _ratingLabels[_selectedRating],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _getRatingColor(_selectedRating),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox(
                      key: ValueKey(0),
                      height: 80,
                      child: Center(
                        child: Text(
                          'Tap a star to rate',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 32),

            // Review Text Field
            TextField(
              controller: _reviewController,
              maxLines: 5,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Share your experience (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),

            const SizedBox(height: 16),

            // Suggestion chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildSuggestionChip('Delicious food! 🍽️'),
                _buildSuggestionChip('Very professional 👨‍🍳'),
                _buildSuggestionChip('Clean and hygienic 🧹'),
                _buildSuggestionChip('On time ⏰'),
                _buildSuggestionChip('Great service 👍'),
              ],
            ),

            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading || _selectedRating == 0
                    ? null
                    : _submitReview,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Review',
                        style: TextStyle(fontSize: 16),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Skip Button
            TextButton(
              onPressed: widget.onBack,
              child: const Text('Maybe Later'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        final currentText = _reviewController.text;
        if (currentText.isEmpty) {
          _reviewController.text = text;
        } else if (!currentText.contains(text)) {
          _reviewController.text = '$currentText $text';
        }
      },
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

