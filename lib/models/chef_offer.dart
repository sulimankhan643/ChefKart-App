import 'package:cloud_firestore/cloud_firestore.dart';

/// Status for chef offers
enum ChefOfferStatus {
  pending,    // Waiting for customer decision
  accepted,   // Customer accepted this offer
  rejected,   // Customer rejected or selected another chef
  withdrawn,  // Chef withdrew the offer
  expired,    // Request expired before decision
}

/// Type of offer
enum ChefOfferType {
  accept,     // Chef accepts customer's offered price
  counter,    // Chef proposes a different price
}

/// Model for chef's offer on a cooking request
class ChefOffer {
  final String id;
  final String requestId;

  // Chef details
  final String chefId;
  final String chefName;
  final String? chefImage;
  final double chefRating;
  final int chefReviewCount;
  final List<String> chefCuisines;
  final String? chefExperience;
  final double? chefDistanceKm;  // Distance from customer

  // Offer details
  final ChefOfferType offerType;
  final int offeredPrice;         // Price chef is willing to work for
  final int originalPrice;        // Customer's original offered price
  final String? message;          // Optional brief message from chef

  // Status
  final ChefOfferStatus status;

  // Timestamps
  final DateTime createdAt;
  final DateTime? respondedAt;

  ChefOffer({
    required this.id,
    required this.requestId,
    required this.chefId,
    required this.chefName,
    this.chefImage,
    required this.chefRating,
    required this.chefReviewCount,
    this.chefCuisines = const [],
    this.chefExperience,
    this.chefDistanceKm,
    required this.offerType,
    required this.offeredPrice,
    required this.originalPrice,
    this.message,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory ChefOffer.fromMap(String id, Map<String, dynamic> data) {
    return ChefOffer(
      id: id,
      requestId: data['requestId'] ?? '',
      chefId: data['chefId'] ?? '',
      chefName: data['chefName'] ?? '',
      chefImage: data['chefImage'],
      chefRating: (data['chefRating'] ?? 4.0).toDouble(),
      chefReviewCount: data['chefReviewCount'] ?? 0,
      chefCuisines: List<String>.from(data['chefCuisines'] ?? []),
      chefExperience: data['chefExperience'],
      chefDistanceKm: data['chefDistanceKm']?.toDouble(),
      offerType: _parseOfferType(data['offerType']),
      offeredPrice: data['offeredPrice'] ?? 0,
      originalPrice: data['originalPrice'] ?? 0,
      message: data['message'],
      status: _parseStatus(data['status']),
      createdAt: _parseTimestamp(data['createdAt']),
      respondedAt: data['respondedAt'] != null
          ? _parseTimestamp(data['respondedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'chefId': chefId,
      'chefName': chefName,
      'chefImage': chefImage,
      'chefRating': chefRating,
      'chefReviewCount': chefReviewCount,
      'chefCuisines': chefCuisines,
      'chefExperience': chefExperience,
      'chefDistanceKm': chefDistanceKm,
      'offerType': offerType.name,
      'offeredPrice': offeredPrice,
      'originalPrice': originalPrice,
      'message': message,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
    };
  }

  static ChefOfferType _parseOfferType(String? type) {
    switch (type) {
      case 'accept':
        return ChefOfferType.accept;
      case 'counter':
        return ChefOfferType.counter;
      default:
        return ChefOfferType.accept;
    }
  }

  static ChefOfferStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return ChefOfferStatus.pending;
      case 'accepted':
        return ChefOfferStatus.accepted;
      case 'rejected':
        return ChefOfferStatus.rejected;
      case 'withdrawn':
        return ChefOfferStatus.withdrawn;
      case 'expired':
        return ChefOfferStatus.expired;
      default:
        return ChefOfferStatus.pending;
    }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    return DateTime.now();
  }

  bool get isPending => status == ChefOfferStatus.pending;
  bool get isAccepted => status == ChefOfferStatus.accepted;
  bool get isRejected => status == ChefOfferStatus.rejected;
  bool get isWithdrawn => status == ChefOfferStatus.withdrawn;
  bool get isExpired => status == ChefOfferStatus.expired;

  bool get isCounterOffer => offerType == ChefOfferType.counter;
  bool get isDirectAccept => offerType == ChefOfferType.accept;

  int get priceDifference => offeredPrice - originalPrice;
  double get priceChangePercent => originalPrice > 0
      ? ((offeredPrice - originalPrice) / originalPrice * 100)
      : 0;

  ChefOffer copyWith({
    ChefOfferStatus? status,
    DateTime? respondedAt,
  }) {
    return ChefOffer(
      id: id,
      requestId: requestId,
      chefId: chefId,
      chefName: chefName,
      chefImage: chefImage,
      chefRating: chefRating,
      chefReviewCount: chefReviewCount,
      chefCuisines: chefCuisines,
      chefExperience: chefExperience,
      chefDistanceKm: chefDistanceKm,
      offerType: offerType,
      offeredPrice: offeredPrice,
      originalPrice: originalPrice,
      message: message,
      status: status ?? this.status,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}

