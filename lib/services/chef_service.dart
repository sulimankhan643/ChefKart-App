import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/chef.dart';

/// Service class for all chef-related Firebase operations
class ChefService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection reference
  static CollectionReference get _chefsCollection => _firestore.collection('users');

  // Pagination settings
  static const int _defaultPageSize = 15;
  static DocumentSnapshot? _lastDocument;
  static bool _hasMoreData = true;

  /// Reset pagination state
  static void resetPagination() {
    _lastDocument = null;
    _hasMoreData = true;
  }

  /// Check if more data is available
  static bool get hasMoreData => _hasMoreData;

  /// Get all verified chefs as a stream (real-time updates)
  static Stream<List<Chef>> getChefsStream() {
    return _chefsCollection
        .where('role', isEqualTo: 'chef')
        .where('profileCompleted', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }

  /// Get paginated chefs (first page)
  static Future<List<Chef>> getChefsPaginated({int pageSize = _defaultPageSize}) async {
    try {
      resetPagination();

      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .orderBy('rating', descending: true)
          .limit(pageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        _hasMoreData = false;
        return [];
      }

      _lastDocument = snapshot.docs.last;
      _hasMoreData = snapshot.docs.length == pageSize;

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching paginated chefs: $e');
      return [];
    }
  }

  /// Get next page of chefs
  static Future<List<Chef>> getNextPage({int pageSize = _defaultPageSize}) async {
    try {
      if (_lastDocument == null || !_hasMoreData) {
        return [];
      }

      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .orderBy('rating', descending: true)
          .startAfterDocument(_lastDocument!)
          .limit(pageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        _hasMoreData = false;
        return [];
      }

      _lastDocument = snapshot.docs.last;
      _hasMoreData = snapshot.docs.length == pageSize;

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching next page: $e');
      return [];
    }
  }

  /// Get paginated chefs with filters
  static Future<List<Chef>> getChefsPaginatedWithFilters({
    int pageSize = _defaultPageSize,
    String? sortBy,
    double? minRating,
    String? cuisine,
    bool resetPage = false,
  }) async {
    try {
      if (resetPage) {
        resetPagination();
      }

      Query query = _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true);

      // Apply indexed filters
      if (minRating != null && minRating > 0) {
        query = query.where('rating', isGreaterThanOrEqualTo: minRating);
      }

      if (cuisine != null && cuisine.isNotEmpty) {
        query = query.where('cuisines', arrayContains: cuisine);
      }

      // Apply sorting (must match index)
      switch (sortBy) {
        case 'rating':
          query = query.orderBy('rating', descending: true);
          break;
        case 'price_low':
          query = query.orderBy('startingPrice', descending: false);
          break;
        case 'price_high':
          query = query.orderBy('startingPrice', descending: true);
          break;
        case 'reviews':
          query = query.orderBy('reviewCount', descending: true);
          break;
        default:
          query = query.orderBy('rating', descending: true);
      }

      // Apply pagination
      if (_lastDocument != null && !resetPage) {
        query = query.startAfterDocument(_lastDocument!);
      }

      query = query.limit(pageSize);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        _hasMoreData = false;
        return [];
      }

      _lastDocument = snapshot.docs.last;
      _hasMoreData = snapshot.docs.length == pageSize;

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching filtered paginated chefs: $e');
      return [];
    }
  }

  /// Get all verified chefs (one-time fetch)
  static Future<List<Chef>> getChefs() async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chefs: $e');
      return [];
    }
  }

  /// Get a single chef by ID
  static Future<Chef?> getChefById(String chefId) async {
    try {
      final doc = await _chefsCollection.doc(chefId).get();
      if (doc.exists) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching chef: $e');
      return null;
    }
  }

  /// Get chef stream by ID (real-time updates for single chef)
  static Stream<Chef?> getChefStream(String chefId) {
    return _chefsCollection.doc(chefId).snapshots().map((doc) {
      if (doc.exists) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  /// Search chefs by name, cuisine, or dishes
  static Future<List<Chef>> searchChefs(String query) async {
    try {
      // Get all chefs first (Firestore doesn't support full-text search)
      final chefs = await getChefs();

      if (query.isEmpty) return chefs;

      final lowerQuery = query.toLowerCase();
      return chefs.where((chef) {
        final nameMatch = chef.name.toLowerCase().contains(lowerQuery);
        final cuisineMatch = chef.cuisines.any((c) => c.toLowerCase().contains(lowerQuery));
        final dishMatch = chef.dishes.any((d) => d.toLowerCase().contains(lowerQuery));
        return nameMatch || cuisineMatch || dishMatch;
      }).toList();
    } catch (e) {
      debugPrint('Error searching chefs: $e');
      return [];
    }
  }

  /// Get chefs filtered by cuisine
  static Future<List<Chef>> getChefsByCuisine(String cuisine) async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .where('cuisines', arrayContains: cuisine)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chefs by cuisine: $e');
      return [];
    }
  }

  /// Get chefs with minimum rating
  static Future<List<Chef>> getChefsWithMinRating(double minRating) async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .where('rating', isGreaterThanOrEqualTo: minRating)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chefs by rating: $e');
      return [];
    }
  }

  /// Get verified chefs only
  static Future<List<Chef>> getVerifiedChefs() async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .where('isVerified', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching verified chefs: $e');
      return [];
    }
  }

  /// Get chefs by gender preference
  static Future<List<Chef>> getChefsByGender(String gender) async {
    try {
      if (gender == 'any') {
        return getChefs();
      }

      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .where('gender', isEqualTo: gender)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chefs by gender: $e');
      return [];
    }
  }

  /// Get chefs within price range
  static Future<List<Chef>> getChefsInPriceRange(int minPrice, int maxPrice) async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .where('startingPrice', isGreaterThanOrEqualTo: minPrice)
          .where('startingPrice', isLessThanOrEqualTo: maxPrice)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching chefs by price: $e');
      return [];
    }
  }

  /// Get top rated chefs
  static Future<List<Chef>> getTopRatedChefs({int limit = 10}) async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .orderBy('rating', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching top rated chefs: $e');
      return [];
    }
  }

  /// Get recently joined chefs
  static Future<List<Chef>> getRecentChefs({int limit = 10}) async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        return Chef.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching recent chefs: $e');
      return [];
    }
  }

  /// Toggle favorite chef for current user
  static Future<bool> toggleFavoriteChef(String chefId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = _firestore.collection('users').doc(user.uid);
      final userData = await userDoc.get();

      List<String> favorites = List<String>.from(userData.data()?['favoriteChefs'] ?? []);

      if (favorites.contains(chefId)) {
        favorites.remove(chefId);
      } else {
        favorites.add(chefId);
      }

      await userDoc.update({'favoriteChefs': favorites});
      return true;
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      return false;
    }
  }

  /// Check if chef is favorite
  static Future<bool> isChefFavorite(String chefId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userData = await _firestore.collection('users').doc(user.uid).get();
      final favorites = List<String>.from(userData.data()?['favoriteChefs'] ?? []);

      return favorites.contains(chefId);
    } catch (e) {
      return false;
    }
  }

  /// Get user's favorite chefs
  static Future<List<Chef>> getFavoriteChefs() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      final userData = await _firestore.collection('users').doc(user.uid).get();
      final favoriteIds = List<String>.from(userData.data()?['favoriteChefs'] ?? []);

      if (favoriteIds.isEmpty) return [];

      List<Chef> favorites = [];
      for (String id in favoriteIds) {
        final chef = await getChefById(id);
        if (chef != null) {
          favorites.add(chef);
        }
      }

      return favorites;
    } catch (e) {
      debugPrint('Error fetching favorite chefs: $e');
      return [];
    }
  }

  /// Get chef count
  static Future<int> getChefCount() async {
    try {
      final snapshot = await _chefsCollection
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('Error getting chef count: $e');
      return 0;
    }
  }

  /// Apply multiple filters at once
  static List<Chef> applyFilters(
    List<Chef> chefs, {
    List<String>? cuisines,
    double? minRating,
    int? minPrice,
    int? maxPrice,
    String? gender,
    bool? verifiedOnly,
    bool? availableToday,
    String? sortBy,
  }) {
    List<Chef> filtered = List.from(chefs);

    // Filter by cuisines
    if (cuisines != null && cuisines.isNotEmpty) {
      filtered = filtered.where((chef) {
        return chef.cuisines.any((c) =>
          cuisines.any((fc) => c.toLowerCase().contains(fc.toLowerCase())));
      }).toList();
    }

    // Filter by rating
    if (minRating != null && minRating > 0) {
      filtered = filtered.where((chef) => chef.rating >= minRating).toList();
    }

    // Filter by price range
    if (minPrice != null) {
      filtered = filtered.where((chef) => chef.startingPrice >= minPrice).toList();
    }
    if (maxPrice != null) {
      filtered = filtered.where((chef) => chef.startingPrice <= maxPrice).toList();
    }

    // Filter by gender
    if (gender != null && gender != 'any') {
      filtered = filtered.where((chef) =>
        chef.gender.toLowerCase() == gender.toLowerCase()).toList();
    }

    // Filter by verified
    if (verifiedOnly == true) {
      filtered = filtered.where((chef) => chef.isVerified).toList();
    }

    // Filter by availability
    if (availableToday == true) {
      filtered = filtered.where((chef) => chef.isAvailableToday).toList();
    }

    // Sort results
    if (sortBy != null) {
      switch (sortBy) {
        case 'distance':
          filtered.sort((a, b) => a.distance.compareTo(b.distance));
          break;
        case 'rating':
          filtered.sort((a, b) => b.rating.compareTo(a.rating));
          break;
        case 'price_low':
          filtered.sort((a, b) => a.startingPrice.compareTo(b.startingPrice));
          break;
        case 'price_high':
          filtered.sort((a, b) => b.startingPrice.compareTo(a.startingPrice));
          break;
        case 'reviews':
          filtered.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
          break;
      }
    }

    return filtered;
  }
}

