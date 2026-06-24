/// Model class for Review
class Review {
  final String id;
  final String chefId;
  final String customerId;
  final String customerName;
  final String customerImage;
  final String bookingId;
  final int rating; // 1 to 5
  final String review; // Optional text
  final DateTime createdAt;

  Review({
    required this.id,
    required this.chefId,
    required this.customerId,
    required this.customerName,
    required this.customerImage,
    required this.bookingId,
    required this.rating,
    required this.review,
    required this.createdAt,
  });

  factory Review.fromMap(String id, Map<String, dynamic> data) {
    return Review(
      id: id,
      chefId: data['chefId'] ?? '',
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? 'Customer',
      customerImage: data['customerImage'] ?? '',
      bookingId: data['bookingId'] ?? '',
      rating: data['rating'] ?? 0,
      review: data['review'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chefId': chefId,
      'customerId': customerId,
      'customerName': customerName,
      'customerImage': customerImage,
      'bookingId': bookingId,
      'rating': rating,
      'review': review,
      'createdAt': createdAt,
    };
  }

  /// Get rating stars text
  String get ratingStars {
    return '★' * rating + '☆' * (5 - rating);
  }

  /// Get time ago text
  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else {
      return 'Just now';
    }
  }
}

