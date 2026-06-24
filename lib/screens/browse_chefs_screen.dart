import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/chef.dart';
import '../services/chef_service.dart';
import '../services/chef_recommendation_service.dart';
import '../widgets/cached_chef_image.dart';

/// Browse Chefs Screen - Full chef listing with filters and sorting
class BrowseChefsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(Chef)? onChefSelect;

  const BrowseChefsScreen({super.key, this.onBack, this.onChefSelect});

  @override
  State<BrowseChefsScreen> createState() => _BrowseChefsScreenState();
}

class _BrowseChefsScreenState extends State<BrowseChefsScreen> {
  final _searchController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;

  // Cached chef stream to avoid duplicate Firestore listeners
  late final Stream<List<Chef>> _chefsStream;

  String _searchQuery = '';
  String _sortBy = 'rating'; // rating, price_low, price_high, experience
  bool _showOnlyOnline = false;
  bool _showOnlyVerified = false;
  // ignore: prefer_final_fields
  List<String> _selectedCuisines = []; // Mutable list - contents change via add/remove
  RangeValues _priceRange = const RangeValues(500, 5000);
  double _minRating = 0;

  // AI Recommendation state
  List<Map<String, dynamic>> _aiRecommendations = [];
  bool _isLoadingRecommendations = false;
  bool _showAiRecommendations = true;
  String _userCity = 'Peshawar';

  final List<String> _cuisineOptions = [
    'Pakistani', 'BBQ', 'Chinese', 'Continental',
    'Italian', 'Fast Food', 'Desserts', 'Traditional',
  ];

  @override
  void initState() {
    super.initState();
    _chefsStream = ChefService.getChefsStream().asBroadcastStream();
    _loadUserCityAndRecommendations();
  }

  Future<void> _loadUserCityAndRecommendations() async {
    try {
      // Get user's city from profile
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        if (userData != null && userData['city'] != null) {
          _userCity = userData['city'];
        }
      }
      // Load AI recommendations
      await _loadAiRecommendations();
    } catch (e) {
      debugPrint('Error loading user city: $e');
    }
  }

  Future<void> _loadAiRecommendations() async {
    if (!_showAiRecommendations) return;

    setState(() => _isLoadingRecommendations = true);

    try {
      final recommendations = await ChefRecommendationService.getTopRecommendedChefs(
        orderCity: _userCity,
        requiredDishes: _selectedCuisines,
        count: 3,
      );

      if (mounted) {
        setState(() {
          _aiRecommendations = recommendations;
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading AI recommendations: $e');
      if (mounted) {
        setState(() => _isLoadingRecommendations = false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Find Chefs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search chefs, cuisines, dishes...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),

          // Quick Filters
          _buildQuickFilters(),

          // Active Filters Display
          if (_hasActiveFilters()) _buildActiveFilters(),

          // Results Count
          StreamBuilder<List<Chef>>(
            stream: _chefsStream,
            builder: (context, snapshot) {
              final chefs = _filterAndSortChefs(snapshot.data ?? []);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${chefs.length} chefs found',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    if (_showOnlyOnline)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('Online Only', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // Chef List
          Expanded(
            child: StreamBuilder<List<Chef>>(
              stream: _chefsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final chefs = _filterAndSortChefs(snapshot.data ?? []);

                if (chefs.isEmpty && _aiRecommendations.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // AI Recommended Chefs Section
                    if (_showAiRecommendations && _aiRecommendations.isNotEmpty && _searchQuery.isEmpty) ...[
                      _buildAiRecommendationsSection(snapshot.data ?? []),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],

                    // Regular Chef List
                    if (chefs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.restaurant_menu, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              'All Chefs',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...chefs.map((chef) => _ChefListCard(
                        chef: chef,
                        onTap: () => widget.onChefSelect?.call(chef),
                        onFavorite: () => _toggleFavorite(chef.id),
                      )),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Online Only
          FilterChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.green, size: 10),
                SizedBox(width: 4),
                Text('Online'),
              ],
            ),
            selected: _showOnlyOnline,
            onSelected: (value) => setState(() => _showOnlyOnline = value),
          ),
          const SizedBox(width: 8),
          // Verified Only
          FilterChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.blue, size: 14),
                SizedBox(width: 4),
                Text('Verified'),
              ],
            ),
            selected: _showOnlyVerified,
            onSelected: (value) => setState(() => _showOnlyVerified = value),
          ),
          const SizedBox(width: 8),
          // Rating 4+
          FilterChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, color: Colors.amber, size: 14),
                SizedBox(width: 4),
                Text('4+ Rating'),
              ],
            ),
            selected: _minRating >= 4,
            onSelected: (value) => setState(() => _minRating = value ? 4 : 0),
          ),
          const SizedBox(width: 8),
          // Cuisines
          ..._cuisineOptions.take(4).map((cuisine) {
            final isSelected = _selectedCuisines.contains(cuisine);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(cuisine),
                selected: isSelected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedCuisines.add(cuisine);
                    } else {
                      _selectedCuisines.remove(cuisine);
                    }
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Active Filters:',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_showOnlyOnline)
                    _buildFilterTag('Online', () => setState(() => _showOnlyOnline = false)),
                  if (_showOnlyVerified)
                    _buildFilterTag('Verified', () => setState(() => _showOnlyVerified = false)),
                  if (_minRating > 0)
                    _buildFilterTag('${_minRating.toInt()}+ Stars', () => setState(() => _minRating = 0)),
                  ..._selectedCuisines.map((c) => _buildFilterTag(
                    c,
                    () => setState(() => _selectedCuisines.remove(c)),
                  )),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: _clearFilters,
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTag(String label, VoidCallback onRemove) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No chefs found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _clearFilters,
            child: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  /// Build AI Recommendations Section with smart chef suggestions
  Widget _buildAiRecommendationsSection(List<Chef> allChefs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with AI badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.blue.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Recommended for You',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const Spacer(),
            // Refresh button
            IconButton(
              icon: _isLoadingRecommendations
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 20),
              onPressed: _isLoadingRecommendations ? null : _loadAiRecommendations,
              tooltip: 'Refresh recommendations',
            ),
            // Toggle visibility
            IconButton(
              icon: Icon(
                _showAiRecommendations ? Icons.visibility : Icons.visibility_off,
                size: 20,
              ),
              onPressed: () => setState(() => _showAiRecommendations = !_showAiRecommendations),
              tooltip: 'Toggle AI recommendations',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Smart picks based on rating, experience & availability',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),

        // AI Recommendation Cards
        if (_isLoadingRecommendations)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_aiRecommendations.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No AI recommendations available for $_userCity right now.',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          )
        else
          ..._aiRecommendations.map((recommendation) {
            // Find the Chef object from allChefs
            final chefId = recommendation['recommended_chef_id'];
            final chef = allChefs.firstWhere(
              (c) => c.id == chefId,
              orElse: () => Chef(
                id: chefId ?? '',
                name: recommendation['chef_name'] ?? 'Chef',
                image: '',
                about: '',
                cuisines: [],
                dishes: [],
                rating: 0,
                reviewCount: 0,
                distance: 0,
                startingPrice: 0,
                isVerified: false,
                gender: '',
                lat: 0,
                lng: 0,
              ),
            );

            return _AiRecommendedChefCard(
              chef: chef,
              recommendation: recommendation,
              onTap: () => widget.onChefSelect?.call(chef),
            );
          }),
      ],
    );
  }

  bool _hasActiveFilters() {
    return _showOnlyOnline ||
        _showOnlyVerified ||
        _minRating > 0 ||
        _selectedCuisines.isNotEmpty;
  }

  void _clearFilters() {
    setState(() {
      _showOnlyOnline = false;
      _showOnlyVerified = false;
      _minRating = 0;
      _selectedCuisines.clear();
      _priceRange = const RangeValues(500, 5000);
    });
  }

  List<Chef> _filterAndSortChefs(List<Chef> chefs) {
    var filtered = chefs.where((chef) {
      // Search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatch = chef.name.toLowerCase().contains(query);
        final cuisineMatch = chef.cuisines.any((c) => c.toLowerCase().contains(query));
        final dishMatch = chef.dishes.any((d) => d.toLowerCase().contains(query));
        if (!nameMatch && !cuisineMatch && !dishMatch) return false;
      }

      // Online filter - use real-time online status
      if (_showOnlyOnline && !chef.isOnline) return false;

      // Verified filter
      if (_showOnlyVerified && !chef.isVerified) return false;

      // Rating filter
      if (_minRating > 0 && chef.rating < _minRating) return false;

      // Cuisine filter
      if (_selectedCuisines.isNotEmpty) {
        final hasMatchingCuisine = chef.cuisines.any((c) => _selectedCuisines.contains(c));
        if (!hasMatchingCuisine) return false;
      }

      // Price filter
      if (chef.startingPrice < _priceRange.start || chef.startingPrice > _priceRange.end) {
        return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sortBy) {
      case 'rating':
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'price_low':
        filtered.sort((a, b) => a.startingPrice.compareTo(b.startingPrice));
        break;
      case 'price_high':
        filtered.sort((a, b) => b.startingPrice.compareTo(a.startingPrice));
        break;
      case 'experience':
        // Sort by experience if available
        break;
      case 'reviews':
        filtered.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
        break;
    }

    return filtered;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              _clearFilters();
                              setModalState(() {});
                            },
                            child: const Text('Reset'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Cuisines
                      const Text(
                        'Cuisines',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _cuisineOptions.map((cuisine) {
                          final isSelected = _selectedCuisines.contains(cuisine);
                          return FilterChip(
                            label: Text(cuisine),
                            selected: isSelected,
                            onSelected: (value) {
                              setModalState(() {
                                if (value) {
                                  _selectedCuisines.add(cuisine);
                                } else {
                                  _selectedCuisines.remove(cuisine);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 24),

                      // Price Range
                      const Text(
                        'Price Range',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Rs. ${_priceRange.start.toInt()}'),
                          Text('Rs. ${_priceRange.end.toInt()}'),
                        ],
                      ),
                      RangeSlider(
                        values: _priceRange,
                        min: 500,
                        max: 10000,
                        divisions: 19,
                        onChanged: (values) {
                          setModalState(() => _priceRange = values);
                        },
                      ),

                      const SizedBox(height: 24),

                      // Minimum Rating
                      const Text(
                        'Minimum Rating',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(5, (index) {
                          final rating = index + 1;
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                _minRating = _minRating == rating.toDouble() ? 0 : rating.toDouble();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: _minRating >= rating
                                    ? Colors.amber.shade100
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.star,
                                    color: _minRating >= rating ? Colors.amber : Colors.grey,
                                    size: 18,
                                  ),
                                  Text(' $rating+'),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),

                      const SizedBox(height: 24),

                      // Toggles
                      SwitchListTile(
                        title: const Text('Online Now'),
                        subtitle: const Text('Show only available chefs'),
                        value: _showOnlyOnline,
                        onChanged: (value) {
                          setModalState(() => _showOnlyOnline = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Verified Only'),
                        subtitle: const Text('Show only verified chefs'),
                        value: _showOnlyVerified,
                        onChanged: (value) {
                          setModalState(() => _showOnlyVerified = value);
                        },
                      ),

                      const SizedBox(height: 24),

                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {});
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Apply Filters'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort By',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildSortOption('Highest Rating', 'rating', Icons.star),
              _buildSortOption('Lowest Price', 'price_low', Icons.arrow_downward),
              _buildSortOption('Highest Price', 'price_high', Icons.arrow_upward),
              _buildSortOption('Most Reviews', 'reviews', Icons.rate_review),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSortOption(String label, String value, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Theme.of(context).primaryColor : null),
      title: Text(label),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _toggleFavorite(String chefId) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userDoc = _firestore.collection('users').doc(uid);
      final userData = await userDoc.get();
      List<String> favorites = List<String>.from(userData.data()?['favoriteChefs'] ?? []);

      if (favorites.contains(chefId)) {
        favorites.remove(chefId);
      } else {
        favorites.add(chefId);
      }

      await userDoc.update({'favoriteChefs': favorites});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(favorites.contains(chefId) ? 'Added to favorites' : 'Removed from favorites'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
    }
  }
}

// Chef List Card Widget
class _ChefListCard extends StatelessWidget {
  final Chef chef;
  final VoidCallback? onTap;
  final VoidCallback? onFavorite;

  const _ChefListCard({
    required this.chef,
    this.onTap,
    this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chef Image
              Stack(
                children: [
                  CachedChefImage(
                    imageUrl: chef.image,
                    width: 100,
                    height: 100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Online Indicator
                  if (chef.isOnline)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Chef Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and Verified Badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chef.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (chef.isVerified)
                          const Icon(Icons.verified, color: Colors.blue, size: 18),
                        IconButton(
                          icon: const Icon(Icons.favorite_border, size: 20),
                          onPressed: onFavorite,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Cuisines
                    Text(
                      chef.cuisines.join(' • '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Rating and Reviews
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          chef.rating.toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          ' (${chef.reviewCount} reviews)',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Price and Book Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'From Rs. ${chef.startingPrice}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: onTap,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('View Profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Special card for AI recommended chefs with score breakdown
class _AiRecommendedChefCard extends StatelessWidget {
  final Chef chef;
  final Map<String, dynamic> recommendation;
  final VoidCallback onTap;

  const _AiRecommendedChefCard({
    required this.chef,
    required this.recommendation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scoreBreakdown = recommendation['score_breakdown'] as Map<String, dynamic>? ?? {};
    final finalScore = (recommendation['final_score'] as double? ?? 0) * 100;
    final reason = recommendation['recommendation_reason'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.shade50,
            Colors.blue.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.purple.shade200,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chef Image with AI badge
                    Stack(
                      children: [
                        CachedChefImage(
                          imageUrl: chef.image,
                          width: 80,
                          height: 80,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        // AI Badge
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.purple.shade400, Colors.blue.shade400],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Chef Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  chef.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (chef.isVerified)
                                const Icon(Icons.verified, color: Colors.blue, size: 18),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chef.cuisines.join(' • '),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // Rating and Match Score
                          Row(
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                chef.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${finalScore.toStringAsFixed(0)}% Match',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Price
                          Text(
                            'From Rs. ${chef.startingPrice}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Recommendation Reason
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, size: 14, color: Colors.purple.shade400),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reason,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Score Breakdown (collapsed by default)
                if (scoreBreakdown.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: Text(
                      'View AI Score Breakdown',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple.shade400,
                      ),
                    ),
                    dense: true,
                    children: [
                      _buildScoreBar('Rating', (scoreBreakdown['rating'] as double? ?? 0) * 100, Colors.amber),
                      _buildScoreBar('Experience', (scoreBreakdown['experience'] as double? ?? 0) * 100, Colors.blue),
                      _buildScoreBar('Specialty Match', (scoreBreakdown['specialty_match'] as double? ?? 0) * 100, Colors.green),
                      _buildScoreBar('Availability', (scoreBreakdown['earnings_balance'] as double? ?? 0) * 100, Colors.purple),
                      _buildScoreBar('Activity', (scoreBreakdown['recency'] as double? ?? 0) * 100, Colors.orange),
                    ],
                  ),
                ],

                // Action Button
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.restaurant_menu, size: 16),
                    label: const Text('View Profile & Book'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreBar(String label, double percentage, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percentage / 100,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
