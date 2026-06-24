import 'package:flutter/material.dart';

class ChefFilterBottomSheet extends StatefulWidget {
  final Map<String, dynamic> currentFilters;
  final Function(Map<String, dynamic>) onApplyFilters;

  const ChefFilterBottomSheet({
    super.key,
    required this.currentFilters,
    required this.onApplyFilters,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> currentFilters,
  }) async {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ChefFilterBottomSheet(
          currentFilters: currentFilters,
          onApplyFilters: (filters) {
            Navigator.pop(context, filters);
          },
        );
      },
    );
  }

  @override
  State<ChefFilterBottomSheet> createState() => _ChefFilterBottomSheetState();
}

class _ChefFilterBottomSheetState extends State<ChefFilterBottomSheet> {
  late Map<String, dynamic> _filters;

  // Cuisine options
  final List<Map<String, dynamic>> _cuisineOptions = [
    {'id': 'pakistani', 'name': 'Pakistani', 'icon': '🇵🇰'},
    {'id': 'chinese', 'name': 'Chinese', 'icon': '🇨🇳'},
    {'id': 'bbq', 'name': 'BBQ', 'icon': '🍖'},
    {'id': 'continental', 'name': 'Continental', 'icon': '🍽️'},
    {'id': 'italian', 'name': 'Italian', 'icon': '🇮🇹'},
    {'id': 'fast-food', 'name': 'Fast Food', 'icon': '🍔'},
    {'id': 'desserts', 'name': 'Desserts', 'icon': '🍰'},
    {'id': 'traditional', 'name': 'Traditional', 'icon': '🥘'},
  ];

  // Rating options
  final List<double> _ratingOptions = [4.5, 4.0, 3.5, 3.0];

  // Price range options
  final List<Map<String, dynamic>> _priceOptions = [
    {'label': 'Under Rs. 1,500', 'min': 0, 'max': 1500},
    {'label': 'Rs. 1,500 - 2,500', 'min': 1500, 'max': 2500},
    {'label': 'Rs. 2,500 - 4,000', 'min': 2500, 'max': 4000},
    {'label': 'Above Rs. 4,000', 'min': 4000, 'max': 999999},
  ];

  @override
  void initState() {
    super.initState();
    _filters = Map<String, dynamic>.from(widget.currentFilters);
  }

  void _resetFilters() {
    setState(() {
      _filters = {
        'cuisines': <String>[],
        'minRating': 0.0,
        'priceRange': null,
        'gender': 'any',
        'availableToday': false,
        'verified': false,
        'sortBy': 'distance',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filter Chefs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _resetFilters,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Filter content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cuisine Type
                  _buildSectionTitle('Cuisine Type'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _cuisineOptions.map((cuisine) {
                      final isSelected = (_filters['cuisines'] as List<String>?)
                              ?.contains(cuisine['id']) ??
                          false;
                      return FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cuisine['icon']),
                            const SizedBox(width: 4),
                            Text(cuisine['name']),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            final cuisines = List<String>.from(
                                _filters['cuisines'] ?? <String>[]);
                            if (selected) {
                              cuisines.add(cuisine['id']);
                            } else {
                              cuisines.remove(cuisine['id']);
                            }
                            _filters['cuisines'] = cuisines;
                          });
                        },
                        selectedColor:
                            Theme.of(context).primaryColor.withValues(alpha: 0.2),
                        checkmarkColor: Theme.of(context).primaryColor,
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Rating
                  _buildSectionTitle('Minimum Rating'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _ratingOptions.map((rating) {
                      final isSelected = (_filters['minRating'] ?? 0.0) == rating;
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 16, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text('$rating+'),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _filters['minRating'] = selected ? rating : 0.0;
                          });
                        },
                        selectedColor:
                            Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Price Range
                  _buildSectionTitle('Price Range'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _priceOptions.map((price) {
                      final isSelected =
                          _filters['priceRange']?['label'] == price['label'];
                      return ChoiceChip(
                        label: Text(price['label']),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _filters['priceRange'] = selected ? price : null;
                          });
                        },
                        selectedColor:
                            Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Gender Preference
                  _buildSectionTitle('Chef Gender'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildGenderOption('any', 'Any', Icons.people),
                      const SizedBox(width: 12),
                      _buildGenderOption('male', 'Male', Icons.person),
                      const SizedBox(width: 12),
                      _buildGenderOption('female', 'Female', Icons.person_2),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Additional Filters
                  _buildSectionTitle('Additional Filters'),
                  const SizedBox(height: 12),
                  _buildSwitchTile(
                    'Available Today',
                    'Show only chefs available today',
                    'availableToday',
                    Icons.today,
                  ),
                  _buildSwitchTile(
                    'Verified Only',
                    'Show only verified chefs',
                    'verified',
                    Icons.verified,
                  ),

                  const SizedBox(height: 24),

                  // Sort By
                  _buildSectionTitle('Sort By'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildSortOption('distance', 'Nearest'),
                      _buildSortOption('rating', 'Highest Rated'),
                      _buildSortOption('price_low', 'Price: Low to High'),
                      _buildSortOption('price_high', 'Price: High to Low'),
                      _buildSortOption('reviews', 'Most Reviewed'),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Apply Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => widget.onApplyFilters(_filters),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Apply Filters'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildGenderOption(String value, String label, IconData icon) {
    final isSelected = (_filters['gender'] ?? 'any') == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filters['gender'] = value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, String filterKey, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        value: _filters[filterKey] ?? false,
        onChanged: (value) => setState(() => _filters[filterKey] = value),
        activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.5),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).primaryColor;
          }
          return null;
        }),
      ),
    );
  }

  Widget _buildSortOption(String value, String label) {
    final isSelected = (_filters['sortBy'] ?? 'distance') == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _filters['sortBy'] = value);
        }
      },
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
    );
  }
}

