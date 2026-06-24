import 'package:cloud_firestore/cloud_firestore.dart';

/// Status for cooking requests
enum CookingRequestStatus {
  pending,      // Broadcasted, waiting for offers
  confirmed,    // Customer confirmed a chef
  expired,      // No confirmation within time window
  cancelled,    // Customer cancelled
}

/// Model for broadcast cooking request (InDrive style)
class CookingRequest {
  final String id;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String? customerImage;

  // Request details
  final String serviceType;       // 'home-cooking', 'event-catering', 'premium'
  final String date;
  final String time;
  final GeoPoint? customerLocation;
  final String address;
  final int guestCount;
  final int offeredPrice;         // Customer's initial price
  final String? note;
  final List<String> cuisinePreferences;

  // Broadcast settings
  final double broadcastRadiusKm; // Radius to find nearby chefs
  final int expirationMinutes;    // Minutes until auto-expire

  // Status and confirmation
  final CookingRequestStatus status;
  final String? confirmedChefId;
  final String? confirmedChefName;
  final int? finalPrice;

  // Timestamps
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? confirmedAt;

  // Chat enabled flag
  final bool chatEnabled;

  CookingRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.customerImage,
    required this.serviceType,
    required this.date,
    required this.time,
    this.customerLocation,
    required this.address,
    required this.guestCount,
    required this.offeredPrice,
    this.note,
    this.cuisinePreferences = const [],
    this.broadcastRadiusKm = 10.0,
    this.expirationMinutes = 30,
    required this.status,
    this.confirmedChefId,
    this.confirmedChefName,
    this.finalPrice,
    required this.createdAt,
    required this.expiresAt,
    this.confirmedAt,
    this.chatEnabled = false,
  });

  factory CookingRequest.fromMap(String id, Map<String, dynamic> data) {
    return CookingRequest(
      id: id,
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
      customerImage: data['customerImage'],
      serviceType: data['serviceType'] ?? 'home-cooking',
      date: data['date'] ?? '',
      time: data['time'] ?? '',
      customerLocation: data['customerLocation'],
      address: data['address'] ?? '',
      guestCount: data['guestCount'] ?? 1,
      offeredPrice: data['offeredPrice'] ?? 0,
      note: data['note'],
      cuisinePreferences: List<String>.from(data['cuisinePreferences'] ?? []),
      broadcastRadiusKm: (data['broadcastRadiusKm'] ?? 10.0).toDouble(),
      expirationMinutes: data['expirationMinutes'] ?? 30,
      status: _parseStatus(data['status']),
      confirmedChefId: data['confirmedChefId'],
      confirmedChefName: data['confirmedChefName'],
      finalPrice: data['finalPrice'],
      createdAt: _parseTimestamp(data['createdAt']),
      expiresAt: _parseTimestamp(data['expiresAt']),
      confirmedAt: data['confirmedAt'] != null
          ? _parseTimestamp(data['confirmedAt'])
          : null,
      chatEnabled: data['chatEnabled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerImage': customerImage,
      'serviceType': serviceType,
      'date': date,
      'time': time,
      'customerLocation': customerLocation,
      'address': address,
      'guestCount': guestCount,
      'offeredPrice': offeredPrice,
      'note': note,
      'cuisinePreferences': cuisinePreferences,
      'broadcastRadiusKm': broadcastRadiusKm,
      'expirationMinutes': expirationMinutes,
      'status': status.name,
      'confirmedChefId': confirmedChefId,
      'confirmedChefName': confirmedChefName,
      'finalPrice': finalPrice,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'chatEnabled': chatEnabled,
    };
  }

  static CookingRequestStatus _parseStatus(String? status) {
    switch (status) {
      case 'pending':
        return CookingRequestStatus.pending;
      case 'confirmed':
        return CookingRequestStatus.confirmed;
      case 'expired':
        return CookingRequestStatus.expired;
      case 'cancelled':
        return CookingRequestStatus.cancelled;
      default:
        return CookingRequestStatus.pending;
    }
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    return DateTime.now();
  }

  bool get isPending => status == CookingRequestStatus.pending;
  bool get isConfirmed => status == CookingRequestStatus.confirmed;
  bool get isExpired => status == CookingRequestStatus.expired;
  bool get isCancelled => status == CookingRequestStatus.cancelled;

  bool get isActive => isPending && DateTime.now().isBefore(expiresAt);

  Duration get remainingTime => expiresAt.difference(DateTime.now());

  CookingRequest copyWith({
    CookingRequestStatus? status,
    String? confirmedChefId,
    String? confirmedChefName,
    int? finalPrice,
    DateTime? confirmedAt,
    bool? chatEnabled,
  }) {
    return CookingRequest(
      id: id,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerImage: customerImage,
      serviceType: serviceType,
      date: date,
      time: time,
      customerLocation: customerLocation,
      address: address,
      guestCount: guestCount,
      offeredPrice: offeredPrice,
      note: note,
      cuisinePreferences: cuisinePreferences,
      broadcastRadiusKm: broadcastRadiusKm,
      expirationMinutes: expirationMinutes,
      status: status ?? this.status,
      confirmedChefId: confirmedChefId ?? this.confirmedChefId,
      confirmedChefName: confirmedChefName ?? this.confirmedChefName,
      finalPrice: finalPrice ?? this.finalPrice,
      createdAt: createdAt,
      expiresAt: expiresAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      chatEnabled: chatEnabled ?? this.chatEnabled,
    );
  }
}

