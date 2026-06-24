import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// App Mode - Like InDrive's Driver/Passenger mode
enum AppMode { customer, chef }

/// Service to manage app mode switching
class AppModeService extends ChangeNotifier {
  static final AppModeService _instance = AppModeService._internal();
  factory AppModeService() => _instance;
  AppModeService._internal();

  AppMode _currentMode = AppMode.customer;
  bool _isChefProfileComplete = false;
  bool _isCustomerProfileComplete = false;
  bool _isLoading = false;

  AppMode get currentMode => _currentMode;
  bool get isChefMode => _currentMode == AppMode.chef;
  bool get isCustomerMode => _currentMode == AppMode.customer;
  bool get isChefProfileComplete => _isChefProfileComplete;
  bool get isCustomerProfileComplete => _isCustomerProfileComplete;
  bool get isLoading => _isLoading;

  /// Initialize mode from Firestore
  Future<void> initializeMode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final savedMode = data['currentMode'] ?? 'customer';
        _currentMode = savedMode == 'chef' ? AppMode.chef : AppMode.customer;
        _isCustomerProfileComplete = data['customerProfileComplete'] ?? false;
        _isChefProfileComplete = data['chefProfileComplete'] ?? false;
      }
    } catch (e) {
      debugPrint('Error initializing mode: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Switch between Chef and Customer mode
  Future<bool> switchMode(AppMode newMode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Check if profile is complete for the target mode
    if (newMode == AppMode.chef && !_isChefProfileComplete) {
      return false; // Need to complete chef profile first
    }

    _isLoading = true;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'currentMode': newMode == AppMode.chef ? 'chef' : 'customer'});

      _currentMode = newMode;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error switching mode: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Mark customer profile as complete
  Future<void> setCustomerProfileComplete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'customerProfileComplete': true});

    _isCustomerProfileComplete = true;
    notifyListeners();
  }

  /// Mark chef profile as complete
  Future<void> setChefProfileComplete() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .update({'chefProfileComplete': true});

    _isChefProfileComplete = true;
    notifyListeners();
  }

  /// Reset on logout
  void reset() {
    _currentMode = AppMode.customer;
    _isChefProfileComplete = false;
    _isCustomerProfileComplete = false;
    _isLoading = false;
    notifyListeners();
  }
}

