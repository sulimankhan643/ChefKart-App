import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chef.dart';
import '../services/chef_service.dart';
import '../services/location_service.dart';
import '../services/deal_negotiation_service.dart';
import '../services/onesignal_service.dart';
import '../services/notification_service.dart';
import '../widgets/cached_chef_image.dart';
import '../widgets/chef_filter_bottom_sheet.dart';
import 'customer_profile_edit_screen.dart';
import 'customer_bookings_screen.dart';
import 'customer_documents_screen.dart';
import 'favorite_chefs_screen.dart';
import 'notification_settings_screen.dart';
import 'notifications_screen.dart';
import 'chef_route_map_screen.dart';
import 'chef_list_screen.dart';
import 'chat_list_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? cuisineFilters;
  final Function(Chef) onChefSelect;
  final VoidCallback? onSwitchToChef; // InDrive-style mode switch
  final VoidCallback? onFindChef; // Navigate to broadcast request (InDrive-style)
  final Function(String requestId)? onViewOffers; // View active request offers with ID

  const HomeScreen({
    super.key,
    this.cuisineFilters,
    required this.onChefSelect,
    this.onSwitchToChef,
    this.onFindChef,
    this.onViewOffers,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String searchQuery = "";
  String viewMode = "list"; // "list" or "map"
  String location = "Getting location..."; // Will be updated with real location

  // Customer's current location for distance calculation
  LatLng? _customerLocation;
  bool _isLoadingLocation = true;

  // Active broadcast request ID (InDrive-style)
  String? _activeRequestId;
  bool _hasActiveRequest = false;

  // Cached chef stream to avoid duplicate Firestore listeners
  late final Stream<List<Chef>> _chefsStream;

  // Advanced filters
  Map<String, dynamic> advancedFilters = {
    'cuisines': <String>[],
    'minRating': 0.0,
    'priceRange': null,
    'gender': 'any',
    'availableToday': false,
    'verified': false,
    'sortBy': 'distance',
  };

  final List<Map<String, dynamic>> filters = [
    {"id": "cuisine", "label": "Cuisine", "active": false},
    {"id": "gender", "label": "Gender", "active": false},
    {"id": "rating", "label": "Rating 4+", "active": false},
    {"id": "distance", "label": "Nearby", "active": false},
    {"id": "price", "label": "Price", "active": false},
  ];

  int _activeFilterCount = 0;

  @override
  void initState() {
    super.initState();
    _chefsStream = ChefService.getChefsStream().asBroadcastStream();
    _loadCurrentLocation();
    _loadActiveRequest();
  }

  /// Load active broadcast request if exists (InDrive-style)
  Future<void> _loadActiveRequest() async {
    try {
      final requestId = await DealNegotiationService.getActivePendingRequestId();
      if (mounted) {
        setState(() {
          _activeRequestId = requestId;
          _hasActiveRequest = requestId != null;
        });
      }
    } catch (e) {
      debugPrint('HomeScreen: Error loading active request: $e');
    }
  }

  /// Load customer's current location for distance calculation
  Future<void> _loadCurrentLocation() async {
    try {
      debugPrint('HomeScreen: Loading current location...');

      final loc = await LocationService.getCurrentLocationWithFallback();

      if (loc != null && mounted) {
        debugPrint('HomeScreen: Got location: ${loc.latitude}, ${loc.longitude}');
        setState(() {
          _customerLocation = loc;
          _isLoadingLocation = false;
          location = "Your Location";
        });

        // Save location to user profile
        await LocationService.saveUserLocation(loc);
      } else {
        debugPrint('HomeScreen: Could not get location, using default');
        if (mounted) {
          setState(() {
            // Default to Peshawar if location not available
            _customerLocation = const LatLng(34.0151, 71.5249);
            _isLoadingLocation = false;
            location = "Peshawar, KPK";
          });
        }
      }
    } catch (e) {
      debugPrint('HomeScreen: Error loading location: $e');
      if (mounted) {
        setState(() {
          _customerLocation = const LatLng(34.0151, 71.5249);
          _isLoadingLocation = false;
          location = "Peshawar, KPK";
        });
      }
    }
  }

  /// Calculate real distance to chef
  double _calculateDistanceToChef(Chef chef) {
    if (_customerLocation == null) return chef.distance;

    final chefLocation = LatLng(chef.lat, chef.lng);
    return LocationService.calculateDistance(_customerLocation!, chefLocation);
  }

  void _openFilterSheet() async {
    final result = await ChefFilterBottomSheet.show(
      context,
      currentFilters: advancedFilters,
    );

    if (result != null) {
      setState(() {
        advancedFilters = result;
        _updateActiveFilterCount();
      });
    }
  }

  void _updateActiveFilterCount() {
    int count = 0;
    if ((advancedFilters['cuisines'] as List).isNotEmpty) count++;
    if ((advancedFilters['minRating'] ?? 0.0) > 0) count++;
    if (advancedFilters['priceRange'] != null) count++;
    if (advancedFilters['gender'] != 'any') count++;
    if (advancedFilters['availableToday'] == true) count++;
    if (advancedFilters['verified'] == true) count++;
    _activeFilterCount = count;
  }

  void toggleFilter(String filterId) {
    setState(() {
      final filterIndex = filters.indexWhere((f) => f["id"] == filterId);
      if (filterIndex != -1) {
        filters[filterIndex]["active"] = !filters[filterIndex]["active"];
      }
    });
  }

  /// Build drawer with InDrive-style mode switch
  Widget _buildDrawer(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: SafeArea(
        bottom: true,
        child: Column(
          children: [
            // Profile Header - Beautiful Orange-White Theme for Customer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF6B35), // Warm orange
                    const Color(0xFFFF8C42), // Light orange
                    const Color(0xFFFFE0D0), // Very light peach/white
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Text(
                        user?.email?.substring(0, 1).toUpperCase() ?? 'U',
                        style: const TextStyle(
                          fontSize: 32,
                          color: Color(0xFFFF6B35),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.email ?? 'User',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, color: Color(0xFFFF6B35), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Customer Mode',
                          style: TextStyle(
                            color: Color(0xFFFF6B35),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Menu Items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Mode Switch Card (InDrive Style) - Green for Chef switch
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.restaurant_menu, color: Colors.white),
                      title: const Text(
                        'Switch to Chef Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Start offering your services',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onSwitchToChef?.call();
                      },
                    ),
                  ),

                  const Divider(height: 1),

                  // Menu Items
                  ListTile(
                    leading: const Icon(Icons.restaurant_menu, color: Colors.orange),
                    title: const Text('All Chefs'),
                    subtitle: const Text('Browse chefs by city & specialty', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChefListScreen(
                            onChefSelect: widget.onChefSelect,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('My Profile'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerProfileEditScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('My Bookings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerBookingsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF25D366)),
                    title: const Text('Messages'),
                    subtitle: const Text('Chat with chefs', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChatListScreen(isChefView: false),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.map, color: Colors.blue),
                    title: const Text('Live Map'),
                    subtitle: const Text('View map with your location', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChefRouteMapScreen(
                            customerLocation: _customerLocation ?? const LatLng(34.0151, 71.5249),
                            customerName: 'My Location',
                            isChefView: false,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.favorite_outline),
                    title: const Text('Favorite Chefs'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FavoriteChefsScreen(
                            onChefSelect: widget.onChefSelect,
                          ),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.badge_outlined, color: Colors.deepPurple),
                    title: const Text('CNIC Verification'),
                    subtitle: const Text('Verify your identity', style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomerDocumentsScreen(),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Help & Support'),
                    onTap: () {
                      Navigator.pop(context);
                      _showHelpDialog(context);
                    },
                  ),
                  // TODO: Remove this before production
                  ],
              ),
            ),

            // Logout - Fixed at bottom
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                // Logout from OneSignal first
                await OneSignalService.logoutUser();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Chef> filterChefs(List<Chef> chefs) {
    List<Chef> filtered = chefs;

    // Calculate real distances if customer location is available
    if (_customerLocation != null) {
      filtered = filtered.map((chef) {
        final realDistance = _calculateDistanceToChef(chef);
        return chef.copyWith(distance: realDistance);
      }).toList();
    }

    // Apply search query filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((chef) {
        final nameMatch = chef.name.toLowerCase().contains(searchQuery.toLowerCase());
        final cuisineMatch = chef.cuisines.any((c) =>
            c.toLowerCase().contains(searchQuery.toLowerCase()));
        final dishMatch = chef.dishes.any((d) =>
            d.toLowerCase().contains(searchQuery.toLowerCase()));
        return nameMatch || cuisineMatch || dishMatch;
      }).toList();
    }

    // Apply cuisine filters from widget
    if (widget.cuisineFilters != null) {
      final cuisineFilter = widget.cuisineFilters!;

      filtered = filtered.where((chef) {
        final cuisineMatch = chef.cuisines.any((c) =>
            c.toLowerCase().contains((cuisineFilter["cuisine"] ?? "").toString().toLowerCase()));

        final dishes = cuisineFilter["dishes"] as List<dynamic>? ?? [];
        final dishMatch = dishes.isEmpty || dishes.any((dish) =>
            chef.dishes.any((cd) => cd.toLowerCase().contains(dish.toString().toLowerCase())));

        final genderFilter = cuisineFilter["gender"] ?? "any";
        final genderMatch = genderFilter == "any" ||
            chef.gender.toLowerCase() == genderFilter.toString().toLowerCase();

        return cuisineMatch && dishMatch && genderMatch;
      }).toList();
    }

    // Apply "Nearby" quick filter - show only chefs within 10km
    final nearbyFilterActive = filters.firstWhere((f) => f["id"] == "distance")["active"] as bool;
    if (nearbyFilterActive) {
      filtered = filtered.where((chef) => chef.distance <= 10.0).toList();
    }

    // Apply advanced filters using ChefService
    final priceRange = advancedFilters['priceRange'] as Map<String, dynamic>?;
    filtered = ChefService.applyFilters(
      filtered,
      cuisines: (advancedFilters['cuisines'] as List<String>?)?.isNotEmpty == true
          ? advancedFilters['cuisines'] as List<String>
          : null,
      minRating: advancedFilters['minRating'] as double?,
      minPrice: priceRange?['min'] as int?,
      maxPrice: priceRange?['max'] as int?,
      gender: advancedFilters['gender'] as String?,
      verifiedOnly: advancedFilters['verified'] as bool?,
      availableToday: advancedFilters['availableToday'] as bool?,
      sortBy: advancedFilters['sortBy'] as String?,
    );

    // Sort by distance by default
    filtered.sort((a, b) => a.distance.compareTo(b.distance));

    return filtered;
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email Us'),
              subtitle: const Text('chefkart900@gmail.com'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('WhatsApp'),
              subtitle: const Text('0310 9887889'),
              onTap: () {
                Navigator.pop(context);
                _launchWhatsApp(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _launchWhatsApp(BuildContext context) async {
    final Uri whatsappUri = Uri.parse('https://wa.me/923109887889?text=Hello, I need help with ChefKart');
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  /// InDrive-style floating action button for finding a chef
  Widget _buildFindChefFAB() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FloatingActionButton.extended(
        onPressed: widget.onFindChef,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.search, size: 24),
        label: const Text(
          'Find a Chef',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  /// Banner shown when customer has an active broadcast request
  Widget _buildActiveRequestBanner() {
    return GestureDetector(
      onTap: () {
        if (_activeRequestId != null && widget.onViewOffers != null) {
          widget.onViewOffers!(_activeRequestId!);
        }
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(0, 40, 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.broadcast_on_home, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Active Request',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Tap to view chef offers',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      // InDrive-style FAB for finding a chef
      floatingActionButton: _hasActiveRequest ? null : _buildFindChefFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(
          children: [
            // Active Request Banner (InDrive-style)
            if (_hasActiveRequest && _activeRequestId != null)
              _buildActiveRequestBanner(),
            // Header - Made flexible to handle landscape
            Flexible(
              flex: 0,
              child: Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Builder(
                              builder: (context) => IconButton(
                                icon: const Icon(Icons.menu),
                                onPressed: () => Scaffold.of(context).openDrawer(),
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "ChefKart",
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "Customer Mode",
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Theme.of(context).primaryColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            StreamBuilder<int>(
                              stream: NotificationService.getUnreadCount(),
                              builder: (context, snapshot) {
                                final count = snapshot.data ?? 0;
                                return IconButton(
                                  icon: Badge(
                                    isLabelVisible: count > 0,
                                    label: Text('$count'),
                                    child: const Icon(Icons.notifications_outlined),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => NotificationsScreen(
                                          onBack: () => Navigator.pop(context),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Search Bar
                    TextField(
                      decoration: InputDecoration(
                        hintText: "Search chefs, cuisines...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onChanged: (value) {
                        setState(() => searchQuery = value);
                      },
                    )
                  ],
                ),
              ),
            ),

          // Filters
          Container(
            color: Theme.of(context).cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Advanced Filter Button
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.tune, size: 18),
                            SizedBox(width: 4),
                            Text('Filters'),
                          ],
                        ),
                        selected: _activeFilterCount > 0,
                        onSelected: (_) => _openFilterSheet(),
                        selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                      ),
                      if (_activeFilterCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_activeFilterCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Quick filters
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: filters.map((filter) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(filter["label"]),
                            selected: filter["active"],
                            onSelected: (_) => toggleFilter(filter["id"]),
                            selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Active Filters Display
          if (widget.cuisineFilters != null)
            Container(
              color: Colors.orange.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text("Showing: ", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Chip(
                    label: Text(
                      widget.cuisineFilters!["cuisine"] ?? "",
                      style: const TextStyle(fontSize: 12),
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  if (widget.cuisineFilters!["gender"] != "any")
                    Chip(
                      label: Text(
                        widget.cuisineFilters!["gender"] == "female" ? "👩‍🍳 Female" : "👨‍🍳 Male",
                        style: const TextStyle(fontSize: 12),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),

          // View Toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StreamBuilder<List<Chef>>(
              stream: _chefsStream,
              builder: (context, snapshot) {
                int chefCount = 0;
                if (snapshot.hasData) {
                  chefCount = snapshot.data!.length;
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$chefCount chefs found nearby",
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.list,
                            color: viewMode == "list" ? Theme.of(context).primaryColor : Colors.grey,
                          ),
                          onPressed: () => setState(() => viewMode = "list"),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.map,
                            color: viewMode == "map" ? Theme.of(context).primaryColor : Colors.grey,
                          ),
                          onPressed: () => setState(() => viewMode = "map"),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          // Content
          Expanded(
            child: StreamBuilder<List<Chef>>(
              stream: _chefsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "Failed to load chefs",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text("Retry"),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.restaurant, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          "No chefs available",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Check back later for more chefs",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                List<Chef> chefs = filterChefs(snapshot.data!);

                if (chefs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          "No matching chefs found",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Try adjusting your filters",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              advancedFilters = {
                                'cuisines': <String>[],
                                'minRating': 0.0,
                                'priceRange': null,
                                'gender': 'any',
                                'availableToday': false,
                                'verified': false,
                                'sortBy': 'distance',
                              };
                              _activeFilterCount = 0;
                              searchQuery = '';
                            });
                          },
                          child: const Text("Clear Filters"),
                        ),
                      ],
                    ),
                  );
                }

                if (viewMode == "list") {
                  return _buildListView(chefs);
                } else {
                  return _buildMapView(chefs);
                }
              },
            ),
          )
        ],
        ),
      ),
    );
  }

  Widget _buildListView(List<Chef> chefs) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: chefs.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final chef = chefs[index];
        return _buildChefCard(chef);
      },
    );
  }

 Widget _buildChefCard(Chef chef) {
    return Card(
      key: ValueKey(chef.id),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: () => widget.onChefSelect(chef),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chef Image with status - Using CachedChefImage for smooth scrolling
                  Stack(
                    children: [
                      CachedChefImage(
                        imageUrl: chef.image,
                        width: 80,
                        height: 80,
                        borderRadius: BorderRadius.circular(12),
                        placeholderText: chef.name,
                      ),
                      // Online status - shows green only if chef is online (isAvailable = true)
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
                      // Verified badge
                      if (chef.isVerified)
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2B3A67),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.white, size: 10),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Chef Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name and rating row
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 14),
                                  const SizedBox(width: 2),
                                  Text(
                                    "${chef.rating}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    " (${chef.reviewCount})",
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Experience & Gender
                        Row(
                          children: [
                            if (chef.experience.isNotEmpty) ...[
                              Icon(Icons.work_outline, size: 14, color: Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                chef.experience,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                chef.gender,
                                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Cuisines
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: chef.cuisines.take(3).map((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              c,
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bottom section with location and price
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  // Location and City
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.red[400]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          chef.city.isNotEmpty ? chef.city : "${chef.distance} km away",
                          style: TextStyle(fontSize: 12, color: Colors.grey[700], fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: chef.isOnline ? Colors.green[50] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              chef.isOnline ? Icons.check_circle : Icons.access_time,
                              size: 12,
                              color: chef.isOnline ? Colors.green[600] : Colors.grey[600],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              chef.isOnline ? "Available" : "Offline",
                              style: TextStyle(
                                fontSize: 11,
                                color: chef.isOnline ? Colors.green[700] : Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Specialties and Price Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Specialties
                      if (chef.dishes.isNotEmpty)
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.restaurant_menu, size: 14, color: Colors.orange[400]),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  chef.dishes.take(2).join(', '),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Price
                      Text(
                        "Rs. ${chef.startingPrice}",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView(List<Chef> chefs) {
    // Use customer location or default to Peshawar
    final centerLocation = _customerLocation ?? const LatLng(34.0151, 71.5249);

    return Stack(
      children: [
        // Real Map using flutter_map
        FlutterMap(
          options: MapOptions(
            initialCenter: centerLocation,
            initialZoom: 13.0,
            minZoom: 10.0,
            maxZoom: 18.0,
          ),
          children: [
            // OpenStreetMap Tile Layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.chefkart.app',
            ),

            // Chef Markers
            MarkerLayer(
              markers: [
                // Customer Location Marker
                Marker(
                  point: centerLocation,
                  width: 60,
                  height: 70,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, color: Colors.white, size: 18),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('You', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                // Chef Markers
                ...chefs.map((chef) {
                  final chefLocation = LatLng(chef.lat, chef.lng);
                  return Marker(
                    point: chefLocation,
                    width: 70,
                    height: 75,
                    child: GestureDetector(
                      onTap: () => widget.onChefSelect(chef),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: chef.isOnline ? Colors.green : Colors.grey,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: CachedChefAvatar(
                              imageUrl: chef.image,
                              name: chef.name,
                              radius: 20,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              chef.name.split(' ').first,
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),

        // Map Controls
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: "my_location",
                onPressed: _loadCurrentLocation,
                backgroundColor: Colors.white,
                child: _isLoadingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: Colors.blue),
              ),
            ],
          ),
        ),

        // Bottom Chef List Preview
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 120,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.white.withValues(alpha: 0.9)],
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: chefs.length,
              itemBuilder: (context, index) {
                final chef = chefs[index];
                return Container(
                  width: 200,
                  margin: const EdgeInsets.only(right: 12),
                  child: Card(
                    elevation: 4,
                    child: InkWell(
                      onTap: () => widget.onChefSelect(chef),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CachedChefAvatar(
                              imageUrl: chef.image,
                              name: chef.name,
                              radius: 20,
                              showOnlineStatus: true,
                              isOnline: chef.isOnline,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    chef.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 12, color: Colors.grey),
                                      Text(
                                        ' ${chef.distance.toStringAsFixed(1)} km',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                      const Text(' • ', style: TextStyle(color: Colors.grey)),
                                      const Icon(Icons.star, size: 12, color: Colors.amber),
                                      Text(
                                        ' ${chef.rating}',
                                        style: const TextStyle(fontSize: 11),
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
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

