import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/chef.dart';
import '../widgets/cached_chef_image.dart';

/// Saved/Favorite Chefs Screen
class FavoriteChefsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(Chef)? onChefSelect;

  const FavoriteChefsScreen({super.key, this.onBack, this.onChefSelect});

  @override
  State<FavoriteChefsScreen> createState() => _FavoriteChefsScreenState();
}

class _FavoriteChefsScreenState extends State<FavoriteChefsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<Chef> _favoriteChefs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Get user's favorite chef IDs
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final favoriteIds = List<String>.from(userDoc.data()?['favoriteChefs'] ?? []);

      if (favoriteIds.isEmpty) {
        if (mounted) {
          setState(() {
            _favoriteChefs = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Get chef details for each favorite
      List<Chef> chefs = [];
      for (String chefId in favoriteIds) {
        final chefDoc = await _firestore.collection('users').doc(chefId).get();
        if (chefDoc.exists) {
          final data = chefDoc.data()!;
          if (data['role'] == 'chef') {
            chefs.add(Chef(
              id: chefId,
              uid: chefId, // ALWAYS use document ID as uid - it IS the Firebase Auth UID
              name: data['name'] ?? 'Chef',
              image: data['image'] ?? '',
              about: data['bio'] ?? data['about'] ?? '',
              cuisines: List<String>.from(data['cuisines'] ?? []),
              dishes: List<String>.from(data['specialties'] ?? []),
              rating: (data['rating'] ?? 0).toDouble(),
              reviewCount: data['reviewCount'] ?? 0,
              distance: 0,
              startingPrice: data['startingPrice'] ?? 0,
              isVerified: data['isVerified'] ?? false,
              gender: data['gender'] ?? 'Any',
              lat: (data['lat'] ?? 0).toDouble(),
              lng: (data['lng'] ?? 0).toDouble(),
              isAvailableToday: data['isAvailable'] ?? false,
              isOnline: data['isAvailable'] ?? false,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _favoriteChefs = chefs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeFromFavorites(String chefId) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore.collection('users').doc(uid).update({
        'favoriteChefs': FieldValue.arrayRemove([chefId]),
      });

      setState(() {
        _favoriteChefs.removeWhere((chef) => chef.id == chefId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from favorites'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing favorite: $e');
    }
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
        title: const Text('Saved Chefs'),
        actions: [
          if (_favoriteChefs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() => _isLoading = true);
                _loadFavorites();
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favoriteChefs.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadFavorites,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _favoriteChefs.length,
                    itemBuilder: (context, index) {
                      final chef = _favoriteChefs[index];
                      return _FavoriteChefCard(
                        chef: chef,
                        onTap: () => widget.onChefSelect?.call(chef),
                        onRemove: () => _removeFromFavorites(chef.id),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No saved chefs',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Save your favorite chefs for easy access',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.search),
            label: const Text('Browse Chefs'),
          ),
        ],
      ),
    );
  }
}

class _FavoriteChefCard extends StatelessWidget {
  final Chef chef;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _FavoriteChefCard({
    required this.chef,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Chef Image
              Stack(
                children: [
                  CachedChefImage(
                    imageUrl: chef.image,
                    width: 80,
                    height: 80,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  // Online Indicator - shows only if chef is online
                  if (chef.isOnline)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Details
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
                          const Icon(Icons.verified, color: Color(0xFF2B3A67), size: 16),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chef.cuisines.take(3).join(' • '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${chef.rating.toStringAsFixed(1)} (${chef.reviewCount})',
                          style: const TextStyle(fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          'Rs. ${chef.startingPrice}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Actions
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.red),
                    onPressed: onRemove,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: onTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

