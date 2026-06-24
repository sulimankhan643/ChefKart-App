import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Location Service for managing live location updates
/// Supports both Firestore and Realtime Database for different use cases
class LocationService {
  static final _firestore = FirebaseFirestore.instance;
  static final _realtimeDb = FirebaseDatabase.instance;
  static StreamSubscription<Position>? _positionSubscription;
  static Timer? _locationTimer;

  /// Check if location services are available and have permission
  static Future<bool> checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: Location services are disabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('LocationService: Current permission: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('LocationService: Permission after request: $permission');
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: Permission denied');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('LocationService: Error checking permission: $e');
      return false;
    }
  }

  /// Get current location with detailed error handling
  static Future<LatLng?> getCurrentLocation() async {
    try {
      debugPrint('LocationService: Getting current location...');

      bool hasPermission = await checkLocationPermission();
      if (!hasPermission) {
        debugPrint('LocationService: No permission, returning null');
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      debugPrint('LocationService: Got location: ${position.latitude}, ${position.longitude}');
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('LocationService: Error getting location: $e');
      return null;
    }
  }

  /// Get current location with fallback to last known position
  static Future<LatLng?> getCurrentLocationWithFallback() async {
    try {
      // First try to get current position
      final currentLocation = await getCurrentLocation();
      if (currentLocation != null) {
        return currentLocation;
      }

      // Fallback to last known position
      debugPrint('LocationService: Trying last known position...');
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        debugPrint('LocationService: Got last known: ${lastPosition.latitude}, ${lastPosition.longitude}');
        return LatLng(lastPosition.latitude, lastPosition.longitude);
      }

      debugPrint('LocationService: No location available');
      return null;
    } catch (e) {
      debugPrint('LocationService: Error in fallback: $e');
      return null;
    }
  }

  /// Start live location updates and save to Firestore
  static void startLiveLocationUpdates() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _positionSubscription?.cancel();

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // Update every 50 meters
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      // Update location in Firestore
      _firestore.collection('users').doc(uid).update({
        'liveLocation': {
          'lat': position.latitude,
          'lng': position.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      });
    });
  }

  /// Start real-time location updates to Firebase Realtime Database (InDrive style)
  /// Updates every 3 seconds for smooth tracking
  static void startRealtimeLocationUpdates(String chefId) {
    _locationTimer?.cancel();

    _locationTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final location = await getCurrentLocation();
      if (location != null) {
        await _realtimeDb.ref("chef_locations/$chefId").set({
          "latitude": location.latitude,
          "longitude": location.longitude,
          "updatedAt": DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  /// Stop real-time location updates
  static void stopRealtimeLocationUpdates(String chefId) {
    _locationTimer?.cancel();
    _locationTimer = null;

    // Remove location from database when chef stops sharing
    _realtimeDb.ref("chef_locations/$chefId").remove();
  }

  /// Start continuous Firestore location updates for chef tracking
  /// Updates every 5 seconds for smooth tracking
  static void startChefFirestoreLocationUpdates() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _locationTimer?.cancel();

    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final location = await getCurrentLocation();
      if (location != null) {
        try {
          await _firestore.collection('users').doc(uid).update({
            'lat': location.latitude,
            'lng': location.longitude,
            'locationUpdatedAt': FieldValue.serverTimestamp(),
          });
          debugPrint('LocationService: Updated chef location to Firestore: ${location.latitude}, ${location.longitude}');
        } catch (e) {
          debugPrint('LocationService: Error updating Firestore location: $e');
        }
      }
    });
  }

  /// Stop continuous Firestore location updates
  static void stopChefFirestoreLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  /// Stream chef's live location from Firebase Realtime Database
  static Stream<LatLng?> getChefRealtimeLocation(String chefId) {
    return _realtimeDb.ref("chef_locations/$chefId").onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;

      final Map<dynamic, dynamic> locationData = data as Map<dynamic, dynamic>;
      return LatLng(
        (locationData["latitude"] ?? 0).toDouble(),
        (locationData["longitude"] ?? 0).toDouble(),
      );
    });
  }

  /// Stop live location updates
  static void stopLiveLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Get user's live location from Firestore
  static Stream<LatLng?> getUserLiveLocation(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data();
      final liveLocation = data?['liveLocation'];
      if (liveLocation == null) return null;

      return LatLng(
        (liveLocation['lat'] ?? 0).toDouble(),
        (liveLocation['lng'] ?? 0).toDouble(),
      );
    });
  }

  /// Save user's address location
  static Future<void> saveUserLocation(LatLng location) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore.collection('users').doc(uid).update({
      'location': {
        'lat': location.latitude,
        'lng': location.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  /// Calculate distance between two points
  static double calculateDistance(LatLng from, LatLng to) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, from, to);
  }

  /// Estimate travel time (assuming 30 km/h average speed in city)
  static double estimateTime(double distanceKm) {
    return distanceKm * 2; // 2 minutes per km
  }
}

