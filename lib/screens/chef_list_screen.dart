// filepath: d:\flutter_projects\chef_kart\lib\screens\chef_list_screen.dart
import 'package:flutter/material.dart';
import '../models/chef.dart';
import '../services/chef_service.dart';
import '../widgets/cached_chef_image.dart';
import 'chef_profile_screen.dart';

/// Chef List Screen - Shows all chefs with their specialties and location
class ChefListScreen extends StatefulWidget {
  final Function(Chef)? onChefSelect;
  final VoidCallback? onBack;

  const ChefListScreen({
    super.key,
    this.onChefSelect,
    this.onBack,
  });

  @override
  State<ChefListScreen> createState() => _ChefListScreenState();
}

class _ChefListScreenState extends State<ChefListScreen> {
  String _searchQuery = '';
  String _selectedCity = 'All';
  String _selectedCuisine = 'All';
  String _sortBy = 'rating'; // rating, price, distance

  final List<String> _cities = ['All', 'Peshawar', 'Lahore', 'Karachi', 'Islamabad', 'Rawalpindi'];
  final List<String> _cuisines = ['All', 'Pakistani', 'BBQ', 'Chinese', 'Continental', 'Italian', 'Fast Food', 'Desserts', 'Traditional'];

  List<Chef> _filterChefs(List<Chef> chefs) {
    List<Chef> filtered = chefs;

    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((chef) {
        return chef.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            chef.cuisines.any((c) => c.toLowerCase().contains(_searchQuery.toLowerCase())) ||
            chef.dishes.any((d) => d.toLowerCase().contains(_searchQuery.toLowerCase())) ||
            chef.city.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // City filter
    if (_selectedCity != 'All') {
      filtered = filtered.where((chef) =>
        chef.city.toLowerCase() == _selectedCity.toLowerCase()
      ).toList();
    }

    // Cuisine filter
    if (_selectedCuisine != 'All') {
      filtered = filtered.where((chef) =>
        chef.cuisines.any((c) => c.toLowerCase() == _selectedCuisine.toLowerCase())
      ).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'rating':
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'price':
        filtered.sort((a, b) => a.startingPrice.compareTo(b.startingPrice));
        break;
      case 'distance':
        filtered.sort((a, b) => a.distance.compareTo(b.distance));
        break;
    }

    return filtered;
  }

  void _navigateToChefProfile(Chef chef) {
    // Always navigate directly to chef profile screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChefProfileScreen(
          chef: chef,
          onBack: () => Navigator.pop(context),
          onBook: () {
            // Pop back to chef list, then call onChefSelect if available
            Navigator.pop(context);
            if (widget.onChefSelect != null) {
              widget.onChefSelect!(chef);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)
            : null,
        title: const Text('All Chefs'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (value) => setState(() => _sortBy = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rating',
                child: Row(
                  children: [
                    Icon(Icons.star, color: _sortBy == 'rating' ? Theme.of(context).primaryColor : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Rating', style: TextStyle(
                      fontWeight: _sortBy == 'rating' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'price',
                child: Row(
                  children: [
                    Icon(Icons.payments, color: _sortBy == 'price' ? Theme.of(context).primaryColor : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Price (Low to High)', style: TextStyle(
                      fontWeight: _sortBy == 'price' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'distance',
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: _sortBy == 'distance' ? Theme.of(context).primaryColor : Colors.grey),
                    const SizedBox(width: 8),
                    Text('Distance', style: TextStyle(
                      fontWeight: _sortBy == 'distance' ? FontWeight.bold : FontWeight.normal,
                    )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search chefs, cuisines, cities...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // City Filter
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCity,
                        isExpanded: true,
                        hint: const Text('City'),
                        icon: const Icon(Icons.location_city, size: 18),
                        items: _cities.map((city) => DropdownMenuItem(
                          value: city,
                          child: Text(city, style: const TextStyle(fontSize: 14)),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedCity = value!),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Cuisine Filter
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCuisine,
                        isExpanded: true,
                        hint: const Text('Cuisine'),
                        icon: const Icon(Icons.restaurant_menu, size: 18),
                        items: _cuisines.map((cuisine) => DropdownMenuItem(
                          value: cuisine,
                          child: Text(cuisine, style: const TextStyle(fontSize: 14)),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedCuisine = value!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Chef List
          Expanded(
            child: StreamBuilder<List<Chef>>(
              stream: ChefService.getChefsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('No chefs available', style: TextStyle(fontSize: 18)),
                      ],
                    ),
                  );
                }

                final chefs = _filterChefs(snapshot.data!);

                if (chefs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text('No chefs match your filters', style: TextStyle(fontSize: 18)),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _selectedCity = 'All';
                              _selectedCuisine = 'All';
                            });
                          },
                          child: const Text('Clear Filters'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: chefs.length,
                  itemBuilder: (context, index) {
                    final chef = chefs[index];
                    return _buildChefDetailCard(chef);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChefDetailCard(Chef chef) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: InkWell(
        onTap: () => _navigateToChefProfile(chef),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with image and basic info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chef Image
                  Stack(
                    children: [
                      CachedChefImage(
                        imageUrl: chef.image,
                        width: 90,
                        height: 90,
                        borderRadius: BorderRadius.circular(12),
                        placeholderText: chef.name,
                      ),
                      if (chef.isVerified)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 12),
                          ),
                        ),
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: chef.isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  // Chef Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name
                        Text(
                          chef.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Rating
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${chef.rating}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              ' (${chef.reviewCount} reviews)',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Location
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: Colors.red[400]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                chef.city.isNotEmpty ? chef.city : 'Peshawar',
                                style: TextStyle(color: Colors.grey[700], fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Experience
                        if (chef.experience.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.work_outline, size: 16, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                chef.experience,
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Price
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs. ${chef.startingPrice}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      Text(
                        '/session',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Cuisines
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.restaurant, size: 16, color: Colors.orange[400]),
                      const SizedBox(width: 6),
                      const Text(
                        'Cuisines:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: chef.cuisines.map((cuisine) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        cuisine,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Specialties/Dishes
            if (chef.dishes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_dining, size: 16, color: Colors.green[600]),
                        const SizedBox(width: 6),
                        const Text(
                          'Specialties:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      chef.dishes.join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

            // Footer with availability and book button
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Availability
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: chef.isOnline ? Colors.green[100] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              chef.isOnline ? Icons.check_circle : Icons.schedule,
                              size: 14,
                              color: chef.isOnline ? Colors.green[700] : Colors.grey[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              chef.isOnline ? 'Available Now' : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: chef.isOnline ? Colors.green[700] : Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Book Button
                  ElevatedButton(
                    onPressed: () => _navigateToChefProfile(chef),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('View Profile'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
