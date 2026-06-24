import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/presence_service.dart';

class Chef {
  final String id;  // Document ID (should be same as uid)
  final String uid; // Firebase Auth UID - use this for chat
  final String name;
  final String image;
  final String about;
  final List<String> cuisines;
  final List<String> dishes;
  final List<String> skills;
  final double rating;
  final int reviewCount;
  final double distance;
  final int startingPrice;
  final bool isVerified;
  final String gender;
  final double lat;
  final double lng;
  final String phone;
  final String experience;
  final String city;  // Chef's city/location
  final String address;  // Chef's address
  final Map<String, bool> availability; // Day-wise availability
  final bool isAvailableToday;
  final bool isOnline; // Real-time online/offline status (verified via heartbeat)
  final Timestamp? lastOnlineAt; // Last heartbeat timestamp

  Chef({
    required this.id,
    String? uid, // Optional - defaults to id if not provided
    required this.name,
    required this.image,
    required this.about,
    required this.cuisines,
    required this.dishes,
    this.skills = const [],
    required this.rating,
    required this.reviewCount,
    required this.distance,
    required this.startingPrice,
    required this.isVerified,
    required this.gender,
    required this.lat,
    required this.lng,
    this.phone = '',
    this.experience = '',
    this.city = 'Peshawar',
    this.address = '',
    this.availability = const {},
    this.isAvailableToday = true,
    this.isOnline = false, // Default to offline
    this.lastOnlineAt,
  }) : uid = uid ?? id; // If uid not provided, use document id

  factory Chef.fromMap(String id, Map<String, dynamic> data) {
    // Check if chef is available today based on schedule
    final now = DateTime.now();
    final dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
    final todayName = dayNames[now.weekday % 7];
    final availabilityMap = Map<String, bool>.from(data['availability'] ?? {});
    final isAvailableToday = availabilityMap[todayName] ?? true;

    // Real-time online status — verified via heartbeat timestamp
    final isAvailableFlag = data['isAvailable'] ?? false;
    final lastOnlineAt = data['lastOnlineAt'] as Timestamp?;
    final isOnline = PresenceService.isTrulyOnline(isAvailableFlag, lastOnlineAt);

    return Chef(
      id: id,
      // ALWAYS use document id as uid since it IS the Firebase Auth UID
      // The document ID in users collection is the Firebase Auth UID
      uid: id,
      // ...existing fields...
      name: data['name'] ?? '',
      image: data['image'] ?? '',
      about: data['about'] ?? data['bio'] ?? '',
      cuisines: List<String>.from(data['cuisines'] ?? []),
      dishes: List<String>.from(data['dishes'] ?? data['specialties'] ?? []),
      skills: List<String>.from(data['skills'] ?? []),
      rating: (data['rating'] ?? 4.5).toDouble(),
      reviewCount: data['reviewCount'] ?? 0,
      distance: (data['distance'] ?? 1.0).toDouble(),
      startingPrice: data['startingPrice'] ?? 1500,
      isVerified: data['isVerified'] ?? data['profileCompleted'] ?? false,
      gender: data['gender'] ?? 'Not specified',
      lat: (data['lat'] ?? 34.0151).toDouble(),  // Default Peshawar
      lng: (data['lng'] ?? 71.5249).toDouble(),  // Default Peshawar
      phone: data['phone'] ?? '',
      experience: data['experience'] ?? '',
      city: data['city'] ?? 'Peshawar',
      address: data['address'] ?? '',
      availability: availabilityMap,
      isAvailableToday: isAvailableToday,
      isOnline: isOnline,
      lastOnlineAt: lastOnlineAt,
    );
  }

  /// Create a copy of this Chef with updated fields
  Chef copyWith({
    String? id,
    String? uid,
    String? name,
    String? image,
    String? about,
    List<String>? cuisines,
    List<String>? dishes,
    List<String>? skills,
    double? rating,
    int? reviewCount,
    double? distance,
    int? startingPrice,
    bool? isVerified,
    String? gender,
    double? lat,
    double? lng,
    String? phone,
    String? experience,
    String? city,
    String? address,
    Map<String, bool>? availability,
    bool? isAvailableToday,
    bool? isOnline,
    Timestamp? lastOnlineAt,
  }) {
    return Chef(
      // ...existing fields...
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      image: image ?? this.image,
      about: about ?? this.about,
      cuisines: cuisines ?? this.cuisines,
      dishes: dishes ?? this.dishes,
      skills: skills ?? this.skills,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      distance: distance ?? this.distance,
      startingPrice: startingPrice ?? this.startingPrice,
      isVerified: isVerified ?? this.isVerified,
      gender: gender ?? this.gender,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      phone: phone ?? this.phone,
      experience: experience ?? this.experience,
      city: city ?? this.city,
      address: address ?? this.address,
      availability: availability ?? this.availability,
      isAvailableToday: isAvailableToday ?? this.isAvailableToday,
      isOnline: isOnline ?? this.isOnline,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
    );
  }
}
