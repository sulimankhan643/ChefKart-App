/// Model class for Booking Request (InDrive Style)
class BookingRequest {
  final String id;
  final String chefId;
  final String chefName;
  final String chefImage;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerImage;
  final String serviceType;
  final String date;
  final String time;
  final String location;
  final String address;
  final int guestCount;
  final int offeredPrice;
  final String note;
  final String status; // pending, accepted, rejected, cancelled
  final DateTime createdAt;
  final DateTime? respondedAt;

  BookingRequest({
    required this.id,
    required this.chefId,
    required this.chefName,
    required this.chefImage,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerImage,
    required this.serviceType,
    required this.date,
    required this.time,
    required this.location,
    required this.address,
    required this.guestCount,
    required this.offeredPrice,
    required this.note,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory BookingRequest.fromMap(String id, Map<String, dynamic> data) {
    return BookingRequest(
      id: id,
      chefId: data['chefId'] ?? '',
      chefName: data['chefName'] ?? '',
      chefImage: data['chefImage'] ?? '',
      customerId: data['customerId'] ?? '',
      customerName: data['customerName'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
      customerImage: data['customerImage'] ?? '',
      serviceType: data['serviceType'] ?? 'one-time',
      date: data['date'] ?? '',
      time: data['time'] ?? '',
      location: data['location'] ?? '',
      address: data['address'] ?? '',
      guestCount: data['guestCount'] ?? 1,
      offeredPrice: data['offeredPrice'] ?? 0,
      note: data['note'] ?? '',
      status: data['status'] ?? 'pending',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as dynamic).toDate()
          : DateTime.now(),
      respondedAt: data['respondedAt'] != null
          ? (data['respondedAt'] as dynamic).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chefId': chefId,
      'chefName': chefName,
      'chefImage': chefImage,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerImage': customerImage,
      'serviceType': serviceType,
      'date': date,
      'time': time,
      'location': location,
      'address': address,
      'guestCount': guestCount,
      'offeredPrice': offeredPrice,
      'note': note,
      'status': status,
      'createdAt': createdAt,
      'respondedAt': respondedAt,
    };
  }

  BookingRequest copyWith({
    String? status,
    DateTime? respondedAt,
  }) {
    return BookingRequest(
      id: id,
      chefId: chefId,
      chefName: chefName,
      chefImage: chefImage,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      customerImage: customerImage,
      serviceType: serviceType,
      date: date,
      time: time,
      location: location,
      address: address,
      guestCount: guestCount,
      offeredPrice: offeredPrice,
      note: note,
      status: status ?? this.status,
      createdAt: createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
  bool get isExpired => status == 'expired';
  bool get isCancelled => status == 'cancelled' ||
      status == 'cancelled_by_customer' ||
      status == 'cancelled_by_chef';
  bool get isCancelledByCustomer => status == 'cancelled_by_customer';
  bool get isCancelledByChef => status == 'cancelled_by_chef';
  bool get isCompleted => status == 'completed';

  /// Check if booking can be cancelled by customer
  bool get canCustomerCancel => status == 'pending' || status == 'accepted';

  /// Check if booking can be cancelled by chef
  bool get canChefCancel => status == 'accepted';

  /// Check if request is still active (can be responded to)
  bool get isActive => status == 'pending' || status == 'accepted';

  /// Get readable status text
  String get statusText {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Confirmed';
      case 'rejected':
        return 'Rejected';
      case 'expired':
        return 'Expired';
      case 'cancelled':
      case 'cancelled_by_customer':
        return 'Cancelled';
      case 'cancelled_by_chef':
        return 'Chef Cancelled';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  /// Get status color
  int get statusColor {
    switch (status) {
      case 'pending':
        return 0xFFFFA000; // Orange
      case 'accepted':
        return 0xFF4CAF50; // Green
      case 'rejected':
      case 'cancelled_by_chef':
        return 0xFFF44336; // Red
      case 'expired':
        return 0xFF9E9E9E; // Grey
      case 'cancelled':
      case 'cancelled_by_customer':
        return 0xFFFF9800; // Orange
      case 'completed':
        return 0xFF2196F3; // Blue
      default:
        return 0xFF9E9E9E; // Grey
    }
  }
}

