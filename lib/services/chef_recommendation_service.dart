import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

/// ===========================================
/// ChefKart AI Recommendation Service
/// ===========================================
///
/// This is a RULE-BASED AI system (not machine learning) that recommends
/// the best available chef for a customer order in real-time based on
/// multiple dynamic factors.
///
/// KEY PRINCIPLES:
/// - No hardcoded chef IDs
/// - No random selection (unless scores are exactly equal)
/// - Dynamic recommendations that change as data changes
/// - Fair load distribution across chefs
/// - Readable, modular, and easily tunable logic
///
/// SCORING WEIGHTS (configurable):
/// - Rating: 40% - Higher rated chefs score higher
/// - Experience: 20% - More completed orders = more trust
/// - Specialty Match: 20% - Chef skills match order requirements
/// - Earnings Balance: 10% - Lower current_cycle_earnings = higher priority
/// - Recency Factor: 10% - Recently active but not overloaded
///
/// ===========================================

class ChefRecommendationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===========================================
  // SCORING WEIGHTS (configurable for tuning)
  // ===========================================

  /// Weight for chef rating (0.0 to 1.0, must sum to 1.0 with others)
  static const double weightRating = 0.40;

  /// Weight for experience/completed orders
  static const double weightExperience = 0.20;

  /// Weight for specialty/cuisine match with order
  static const double weightSpecialtyMatch = 0.20;

  /// Weight for earnings balance (fair distribution)
  static const double weightEarningsBalance = 0.10;

  /// Weight for recency factor (active but not overloaded)
  static const double weightRecency = 0.10;

  // ===========================================
  // THRESHOLD CONFIGURATIONS
  // ===========================================

  /// Maximum rating value for normalization
  static const double maxRating = 5.0;

  /// Orders completed threshold for "experienced" chef
  static const int experiencedOrdersThreshold = 50;

  /// Hours since last order to consider "overloaded"
  static const int overloadHoursThreshold = 2;

  /// Hours since last order to consider "inactive"
  static const int inactiveHoursThreshold = 48;

  /// Maximum current cycle earnings for fair distribution calculation
  static const double maxCycleEarnings = 5000.0;

  // ===========================================
  // DATA MODELS
  // ===========================================

  /// Represents a chef candidate with scoring data
  static Map<String, dynamic> _createChefCandidate({
    required String chefId,
    required Map<String, dynamic> chefData,
  }) {
    return {
      'chef_id': chefId,
      'name': chefData['name'] ?? 'Unknown',
      'rating': (chefData['rating'] ?? 4.0).toDouble(),
      'total_orders_completed': chefData['total_orders_completed'] ?? chefData['reviewCount'] ?? 0,
      'specialties': List<String>.from(chefData['cuisines'] ?? chefData['specialties'] ?? []),
      'dishes': List<String>.from(chefData['dishes'] ?? []),
      'current_cycle_earnings': (chefData['current_cycle_earnings'] ?? 0.0).toDouble(),
      'last_order_completed_at': chefData['last_order_completed_at'],
      'city': chefData['city'] ?? 'Peshawar',
      'is_available': chefData['isAvailable'] ?? false,
      'is_order_blocked': chefData['is_order_blocked'] ?? false,
      'lat': (chefData['lat'] ?? 0.0).toDouble(),
      'lng': (chefData['lng'] ?? 0.0).toDouble(),
    };
  }

  /// Represents the result of a recommendation
  static Map<String, dynamic> _createRecommendationResult({
    required String chefId,
    required String chefName,
    required double finalScore,
    required Map<String, double> scoreBreakdown,
    required String reason,
  }) {
    return {
      'recommended_chef_id': chefId,
      'chef_name': chefName,
      'final_score': finalScore,
      'score_breakdown': scoreBreakdown,
      'recommendation_reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ===========================================
  // MAIN RECOMMENDATION METHOD
  // ===========================================

  /// Get the best recommended chef for an order
  ///
  /// [orderCity] - City where service is needed (e.g., "Peshawar")
  /// [requiredDishes] - List of dishes/cuisines customer wants
  /// [orderLocation] - Optional GeoPoint for distance calculation
  /// [excludeChefIds] - Optional list of chef IDs to exclude (e.g., recently rejected)
  ///
  /// Returns a recommendation result map with:
  /// - recommended_chef_id
  /// - chef_name
  /// - final_score
  /// - score_breakdown (for debugging/logging)
  /// - recommendation_reason
  ///
  /// Returns null if no suitable chef is found
  static Future<Map<String, dynamic>?> getRecommendedChef({
    required String orderCity,
    List<String> requiredDishes = const [],
    GeoPoint? orderLocation,
    List<String> excludeChefIds = const [],
  }) async {
    try {
      debugPrint('===========================================');
      debugPrint('AI RECOMMENDATION: Starting chef recommendation');
      debugPrint('Order City: $orderCity');
      debugPrint('Required Dishes: $requiredDishes');
      debugPrint('===========================================');

      // Step 1: Fetch all chefs
      final chefsSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .get();

      if (chefsSnapshot.docs.isEmpty) {
        debugPrint('AI RECOMMENDATION: No chefs found in database');
        return null;
      }

      debugPrint('AI RECOMMENDATION: Found ${chefsSnapshot.docs.length} total chefs');

      // Step 2: Apply hard filters
      final List<Map<String, dynamic>> eligibleChefs = [];

      for (final doc in chefsSnapshot.docs) {
        final chefId = doc.id;
        final chefData = doc.data();

        // Skip excluded chefs
        if (excludeChefIds.contains(chefId)) {
          debugPrint('AI RECOMMENDATION: Skipping excluded chef: $chefId');
          continue;
        }

        final candidate = _createChefCandidate(chefId: chefId, chefData: chefData);

        // Hard Filter 1: Must be available
        if (candidate['is_available'] != true) {
          debugPrint('AI RECOMMENDATION: Chef ${candidate['name']} filtered - not available');
          continue;
        }

        // Hard Filter 2: Must not be order blocked
        if (candidate['is_order_blocked'] == true) {
          debugPrint('AI RECOMMENDATION: Chef ${candidate['name']} filtered - order blocked (commission pending)');
          continue;
        }

        // Hard Filter 3: Must match order city (case-insensitive)
        final chefCity = (candidate['city'] as String).toLowerCase().trim();
        final targetCity = orderCity.toLowerCase().trim();
        if (chefCity != targetCity && !chefCity.contains(targetCity) && !targetCity.contains(chefCity)) {
          debugPrint('AI RECOMMENDATION: Chef ${candidate['name']} filtered - city mismatch ($chefCity vs $targetCity)');
          continue;
        }

        eligibleChefs.add(candidate);
      }

      debugPrint('AI RECOMMENDATION: ${eligibleChefs.length} chefs passed hard filters');

      if (eligibleChefs.isEmpty) {
        debugPrint('AI RECOMMENDATION: No eligible chefs after filtering');
        return _createNoChefResult('No available chefs in $orderCity');
      }

      // Step 3: Score each eligible chef
      final List<Map<String, dynamic>> scoredChefs = [];

      for (final chef in eligibleChefs) {
        final scoreResult = _calculateChefScore(
          chef: chef,
          requiredDishes: requiredDishes,
        );

        scoredChefs.add({
          ...chef,
          'final_score': scoreResult['final_score'],
          'score_breakdown': scoreResult['breakdown'],
        });
      }

      // Step 4: Sort by score (descending)
      scoredChefs.sort((a, b) => (b['final_score'] as double).compareTo(a['final_score'] as double));

      // Step 5: Apply fairness rule - avoid repeated assignments
      final recommendedChef = await _applyFairnessRule(scoredChefs);

      // Log the recommendation
      debugPrint('===========================================');
      debugPrint('AI RECOMMENDATION: RESULT');
      debugPrint('Recommended Chef: ${recommendedChef['name']}');
      debugPrint('Chef ID: ${recommendedChef['chef_id']}');
      debugPrint('Final Score: ${recommendedChef['final_score']}');
      debugPrint('Score Breakdown: ${recommendedChef['score_breakdown']}');
      debugPrint('===========================================');

      return _createRecommendationResult(
        chefId: recommendedChef['chef_id'],
        chefName: recommendedChef['name'],
        finalScore: recommendedChef['final_score'],
        scoreBreakdown: Map<String, double>.from(recommendedChef['score_breakdown']),
        reason: _generateRecommendationReason(recommendedChef),
      );
    } catch (e, stack) {
      debugPrint('AI RECOMMENDATION ERROR: $e');
      debugPrint('Stack trace: $stack');
      return null;
    }
  }

  // ===========================================
  // SCORING CALCULATIONS
  // ===========================================

  /// Calculate the total score for a chef
  static Map<String, dynamic> _calculateChefScore({
    required Map<String, dynamic> chef,
    required List<String> requiredDishes,
  }) {
    // Calculate individual scores (normalized 0.0 to 1.0)
    final ratingScore = _calculateRatingScore(chef['rating'] as double);
    final experienceScore = _calculateExperienceScore(chef['total_orders_completed'] as int);
    final specialtyScore = _calculateSpecialtyMatchScore(
      chefSpecialties: List<String>.from(chef['specialties']),
      chefDishes: List<String>.from(chef['dishes']),
      requiredDishes: requiredDishes,
    );
    final earningsScore = _calculateEarningsBalanceScore(chef['current_cycle_earnings'] as double);
    final recencyScore = _calculateRecencyScore(chef['last_order_completed_at']);

    // Calculate weighted final score
    final finalScore = (ratingScore * weightRating) +
        (experienceScore * weightExperience) +
        (specialtyScore * weightSpecialtyMatch) +
        (earningsScore * weightEarningsBalance) +
        (recencyScore * weightRecency);

    return {
      'final_score': double.parse(finalScore.toStringAsFixed(4)),
      'breakdown': {
        'rating': double.parse(ratingScore.toStringAsFixed(4)),
        'experience': double.parse(experienceScore.toStringAsFixed(4)),
        'specialty_match': double.parse(specialtyScore.toStringAsFixed(4)),
        'earnings_balance': double.parse(earningsScore.toStringAsFixed(4)),
        'recency': double.parse(recencyScore.toStringAsFixed(4)),
      },
    };
  }

  /// Rating Score: Higher rating = higher score
  /// Normalized: rating / maxRating
  static double _calculateRatingScore(double rating) {
    if (rating <= 0) return 0.0;
    if (rating > maxRating) rating = maxRating;
    return rating / maxRating;
  }

  /// Experience Score: More completed orders = higher trust
  /// Uses logarithmic scaling to avoid penalizing new chefs too much
  static double _calculateExperienceScore(int totalOrders) {
    if (totalOrders <= 0) return 0.1; // New chefs get baseline score

    // Logarithmic scaling: ln(orders + 1) / ln(threshold + 1)
    final score = log(totalOrders + 1) / log(experiencedOrdersThreshold + 1);
    return score.clamp(0.0, 1.0);
  }

  /// Specialty Match Score: Chef skills match order dishes = bonus
  /// Returns 1.0 for perfect match, 0.0 for no match
  static double _calculateSpecialtyMatchScore({
    required List<String> chefSpecialties,
    required List<String> chefDishes,
    required List<String> requiredDishes,
  }) {
    if (requiredDishes.isEmpty) return 0.5; // Neutral if no specific requirement

    // Combine chef's specialties and dishes for matching
    final chefSkills = [
      ...chefSpecialties.map((s) => s.toLowerCase()),
      ...chefDishes.map((d) => d.toLowerCase()),
    ];

    if (chefSkills.isEmpty) return 0.3; // Low score if chef has no listed skills

    // Count matches
    int matches = 0;
    for (final dish in requiredDishes) {
      final dishLower = dish.toLowerCase();
      for (final skill in chefSkills) {
        if (skill.contains(dishLower) || dishLower.contains(skill)) {
          matches++;
          break;
        }
      }
    }

    return (matches / requiredDishes.length).clamp(0.0, 1.0);
  }

  /// Earnings Balance Score: Lower current_cycle_earnings = higher priority
  /// This ensures fair distribution of orders across chefs
  static double _calculateEarningsBalanceScore(double currentCycleEarnings) {
    if (currentCycleEarnings <= 0) return 1.0; // Chef with no earnings gets highest priority

    // Inverse relationship: lower earnings = higher score
    // Score = 1 - (earnings / threshold)
    final score = 1.0 - (currentCycleEarnings / maxCycleEarnings);
    return score.clamp(0.0, 1.0);
  }

  /// Recency Score: Recently active chefs get bonus, but very recent = penalty
  /// - Inactive for too long: lower score
  /// - Recently completed order: slight penalty (avoid overload)
  /// - Moderately active: best score
  static double _calculateRecencyScore(dynamic lastOrderTimestamp) {
    if (lastOrderTimestamp == null) return 0.5; // Neutral for no history

    DateTime lastOrderTime;
    if (lastOrderTimestamp is Timestamp) {
      lastOrderTime = lastOrderTimestamp.toDate();
    } else if (lastOrderTimestamp is DateTime) {
      lastOrderTime = lastOrderTimestamp;
    } else {
      return 0.5;
    }

    final hoursSinceLastOrder = DateTime.now().difference(lastOrderTime).inHours;

    // Very recent (within 2 hours): slight penalty to avoid overload
    if (hoursSinceLastOrder < overloadHoursThreshold) {
      return 0.6;
    }

    // Active within 48 hours: good score
    if (hoursSinceLastOrder <= inactiveHoursThreshold) {
      return 0.9;
    }

    // Inactive for too long: lower score but not disqualifying
    return 0.4;
  }

  // ===========================================
  // FAIRNESS RULE
  // ===========================================

  /// Apply fairness rule to avoid repeated assignments to same chef
  /// If top chefs have similar scores, prefer the one with fewer recent orders
  static Future<Map<String, dynamic>> _applyFairnessRule(
      List<Map<String, dynamic>> scoredChefs) async {
    if (scoredChefs.isEmpty) {
      throw Exception('No chefs to apply fairness rule');
    }

    if (scoredChefs.length == 1) {
      return scoredChefs.first;
    }

    final topChef = scoredChefs.first;
    final topScore = topChef['final_score'] as double;

    // Find chefs within 5% of top score (similar performance)
    final similarChefs = scoredChefs.where((chef) {
      final score = chef['final_score'] as double;
      return (topScore - score).abs() <= 0.05;
    }).toList();

    if (similarChefs.length <= 1) {
      return topChef;
    }

    debugPrint('AI RECOMMENDATION: ${similarChefs.length} chefs have similar scores');
    debugPrint('AI RECOMMENDATION: Applying fairness rule...');

    // Among similar chefs, prefer the one with lower current_cycle_earnings
    similarChefs.sort((a, b) {
      final aEarnings = a['current_cycle_earnings'] as double;
      final bEarnings = b['current_cycle_earnings'] as double;
      return aEarnings.compareTo(bEarnings);
    });

    final fairestChef = similarChefs.first;
    debugPrint('AI RECOMMENDATION: Fairness rule selected: ${fairestChef['name']} '
        '(cycle earnings: Rs. ${fairestChef['current_cycle_earnings']})');

    return fairestChef;
  }

  // ===========================================
  // HELPER METHODS
  // ===========================================

  /// Generate human-readable recommendation reason
  static String _generateRecommendationReason(Map<String, dynamic> chef) {
    final breakdown = chef['score_breakdown'] as Map<String, dynamic>;
    final reasons = <String>[];

    // Rating
    if ((breakdown['rating'] as double) >= 0.8) {
      reasons.add('highly rated');
    }

    // Experience
    if ((breakdown['experience'] as double) >= 0.7) {
      reasons.add('experienced');
    }

    // Specialty match
    if ((breakdown['specialty_match'] as double) >= 0.7) {
      reasons.add('matches your cuisine preferences');
    }

    // Fair distribution
    if ((breakdown['earnings_balance'] as double) >= 0.7) {
      reasons.add('available for new orders');
    }

    if (reasons.isEmpty) {
      return 'Best available chef based on overall performance';
    }

    return 'Recommended because: ${reasons.join(', ')}';
  }

  /// Create a result for when no chef is found
  static Map<String, dynamic> _createNoChefResult(String reason) {
    return {
      'recommended_chef_id': null,
      'chef_name': null,
      'final_score': 0.0,
      'score_breakdown': {},
      'recommendation_reason': reason,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // ===========================================
  // MULTIPLE RECOMMENDATIONS
  // ===========================================

  /// Get top N recommended chefs (for showing options to customer)
  ///
  /// [count] - Number of recommendations to return (default 5)
  /// Returns list of recommendation results sorted by score
  static Future<List<Map<String, dynamic>>> getTopRecommendedChefs({
    required String orderCity,
    List<String> requiredDishes = const [],
    GeoPoint? orderLocation,
    List<String> excludeChefIds = const [],
    int count = 5,
  }) async {
    try {
      debugPrint('AI RECOMMENDATION: Getting top $count chef recommendations');

      // Fetch all chefs
      final chefsSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'chef')
          .where('profileCompleted', isEqualTo: true)
          .get();

      if (chefsSnapshot.docs.isEmpty) {
        return [];
      }

      // Apply filters and score
      final List<Map<String, dynamic>> scoredChefs = [];

      for (final doc in chefsSnapshot.docs) {
        final chefId = doc.id;
        final chefData = doc.data();

        if (excludeChefIds.contains(chefId)) continue;

        final candidate = _createChefCandidate(chefId: chefId, chefData: chefData);

        // Apply hard filters
        if (candidate['is_available'] != true) continue;
        if (candidate['is_order_blocked'] == true) continue;

        final chefCity = (candidate['city'] as String).toLowerCase().trim();
        final targetCity = orderCity.toLowerCase().trim();
        if (chefCity != targetCity && !chefCity.contains(targetCity) && !targetCity.contains(chefCity)) {
          continue;
        }

        // Score the chef
        final scoreResult = _calculateChefScore(
          chef: candidate,
          requiredDishes: requiredDishes,
        );

        scoredChefs.add({
          ...candidate,
          'final_score': scoreResult['final_score'],
          'score_breakdown': scoreResult['breakdown'],
        });
      }

      // Sort and take top N
      scoredChefs.sort((a, b) => (b['final_score'] as double).compareTo(a['final_score'] as double));

      final topChefs = scoredChefs.take(count).map((chef) {
        return _createRecommendationResult(
          chefId: chef['chef_id'],
          chefName: chef['name'],
          finalScore: chef['final_score'],
          scoreBreakdown: Map<String, double>.from(chef['score_breakdown']),
          reason: _generateRecommendationReason(chef),
        );
      }).toList();

      debugPrint('AI RECOMMENDATION: Returning ${topChefs.length} recommendations');
      return topChefs;
    } catch (e) {
      debugPrint('AI RECOMMENDATION ERROR (top N): $e');
      return [];
    }
  }

  // ===========================================
  // ANALYTICS & LOGGING
  // ===========================================

  /// Log a recommendation for analytics (optional - for tracking recommendation performance)
  static Future<void> logRecommendation({
    required String orderId,
    required Map<String, dynamic> recommendation,
    required bool wasAccepted,
  }) async {
    try {
      await _firestore.collection('recommendation_logs').add({
        'order_id': orderId,
        'recommended_chef_id': recommendation['recommended_chef_id'],
        'final_score': recommendation['final_score'],
        'score_breakdown': recommendation['score_breakdown'],
        'was_accepted': wasAccepted,
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('AI RECOMMENDATION: Logged recommendation for analytics');
    } catch (e) {
      debugPrint('AI RECOMMENDATION: Failed to log recommendation: $e');
    }
  }

  /// Get recommendation statistics for a chef
  static Future<Map<String, dynamic>> getChefRecommendationStats(String chefId) async {
    try {
      final logsSnapshot = await _firestore
          .collection('recommendation_logs')
          .where('recommended_chef_id', isEqualTo: chefId)
          .get();

      int totalRecommendations = logsSnapshot.docs.length;
      int acceptedRecommendations = logsSnapshot.docs
          .where((doc) => doc.data()['was_accepted'] == true)
          .length;

      double acceptanceRate = totalRecommendations > 0
          ? (acceptedRecommendations / totalRecommendations) * 100
          : 0.0;

      return {
        'chef_id': chefId,
        'total_recommendations': totalRecommendations,
        'accepted_recommendations': acceptedRecommendations,
        'acceptance_rate': double.parse(acceptanceRate.toStringAsFixed(2)),
      };
    } catch (e) {
      debugPrint('AI RECOMMENDATION: Failed to get stats: $e');
      return {
        'chef_id': chefId,
        'total_recommendations': 0,
        'accepted_recommendations': 0,
        'acceptance_rate': 0.0,
      };
    }
  }
}

