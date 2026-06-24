import 'package:flutter/material.dart';
import '../services/rating_service.dart';

class RatingDialog extends StatefulWidget {
  final String chefId;
  final String chefName;
  final String bookingId;
  final VoidCallback? onComplete;

  const RatingDialog({
    super.key,
    required this.chefId,
    required this.chefName,
    required this.bookingId,
    this.onComplete,
  });

  /// Show the rating dialog
  static Future<void> show(
    BuildContext context, {
    required String chefId,
    required String chefName,
    required String bookingId,
    VoidCallback? onComplete,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RatingDialog(
        chefId: chefId,
        chefName: chefName,
        bookingId: bookingId,
        onComplete: onComplete,
      ),
    );
  }

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _selectedRating = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    setState(() => _isSubmitting = true);

    final success = await RatingService.submitReview(
      chefId: widget.chefId,
      bookingId: widget.bookingId,
      rating: _selectedRating,
      review: _commentController.text.trim(),
    );

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your review!'),
          backgroundColor: Colors.green,
        ),
      );
      widget.onComplete?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit review. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            const Icon(
              Icons.star_rounded,
              size: 48,
              color: Colors.amber,
            ),
            const SizedBox(height: 16),
            Text(
              'Rate ${widget.chefName}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'How was your experience with the chef?',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Star Rating
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNumber = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRating = starNumber),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starNumber <= _selectedRating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 40,
                      color: starNumber <= _selectedRating
                          ? Colors.amber
                          : Colors.grey[400],
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 8),
            Text(
              _getRatingText(_selectedRating),
              style: TextStyle(
                fontSize: 14,
                color: Colors.amber[700],
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 24),

            // Comment Box
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Share your experience (optional)',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Skip'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRating,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }
}
