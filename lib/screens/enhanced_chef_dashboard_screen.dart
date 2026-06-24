import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/booking_request_service.dart';
import '../services/notification_service.dart';
import '../widgets/cached_chef_image.dart';
import 'notifications_screen.dart';

/// Enhanced Chef Dashboard with Bottom Navigation
class EnhancedChefDashboardScreen extends StatefulWidget {
  final Function(String screen, {Map<String, dynamic>? data})? onNavigate;

  const EnhancedChefDashboardScreen({super.key, this.onNavigate});

  @override
  State<EnhancedChefDashboardScreen> createState() => _EnhancedChefDashboardScreenState();
}

class _EnhancedChefDashboardScreenState extends State<EnhancedChefDashboardScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? chefData;
  bool isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadChefData();
  }

  Future<void> _loadChefData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          chefData = doc.data();
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildRequestsTab(),
          _buildBookingsTab(),
          _buildChatsTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: StreamBuilder<int>(
              stream: _getPendingRequestsCount(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.notifications_active_outlined),
                );
              },
            ),
            selectedIcon: const Icon(Icons.notifications_active),
            label: 'Requests',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Bookings',
          ),
          NavigationDestination(
            icon: StreamBuilder<int>(
              stream: _getUnreadChatCount(),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.chat_bubble_outline),
                );
              },
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  // ===========================================
  // HOME/DASHBOARD TAB
  // ===========================================
  Widget _buildHomeTab() {
    return CustomScrollView(
      slivers: [
        // App Bar
        SliverAppBar(
          floating: true,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello, ${chefData?['name']?.split(' ').first ?? 'Chef'}! 👨‍🍳',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                chefData?['isAvailable'] == true ? 'You are online' : 'You are offline',
                style: TextStyle(
                  fontSize: 14,
                  color: chefData?['isAvailable'] == true ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            // Online/Offline Toggle
            Switch(
              value: chefData?['isAvailable'] ?? false,
              onChanged: _toggleAvailability,
              activeTrackColor: Colors.green.shade200,
            ),
            // Notifications
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

        // Stats Cards
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildStatsCards(),
          ),
        ),

        // Today's Summary
        SliverToBoxAdapter(
          child: _buildTodaySummary(),
        ),

        // Pending Requests Preview
        SliverToBoxAdapter(
          child: _buildPendingRequestsPreview(),
        ),

        // Upcoming Bookings Preview
        SliverToBoxAdapter(
          child: _buildUpcomingBookingsPreview(),
        ),

        // Quick Actions
        SliverToBoxAdapter(
          child: _buildQuickActions(),
        ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return FutureBuilder<Map<String, dynamic>>(
      future: BookingRequestService.getChefStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};
        return Row(
          children: [
            _buildStatCard(
              icon: Icons.payments,
              label: "Today's Earnings",
              value: 'Rs. ${stats['todayEarnings'] ?? 0}',
              color: Colors.green,
            ),
            const SizedBox(width: 12),
            _buildStatCard(
              icon: Icons.star,
              label: 'Rating',
              value: (chefData?['rating'] ?? 0.0).toStringAsFixed(1),
              color: Colors.amber,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FutureBuilder<Map<String, dynamic>>(
        future: BookingRequestService.getChefStats(),
        builder: (context, snapshot) {
          final stats = snapshot.data ?? {};
          return Row(
            children: [
              _buildMiniStat('Total Bookings', '${stats['totalBookings'] ?? 0}'),
              const SizedBox(width: 8),
              _buildMiniStat('Completed', '${stats['completedBookings'] ?? 0}'),
              const SizedBox(width: 8),
              _buildMiniStat('Pending', '${stats['pendingRequests'] ?? 0}'),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingRequestsPreview() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _getPendingRequests(),
      builder: (context, snapshot) {
        final requests = snapshot.data ?? [];
        if (requests.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'New Requests',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentIndex = 1),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...requests.take(2).map((request) => _RequestPreviewCard(
                request: request,
                onAccept: () => _acceptRequest(request['id']),
                onReject: () => _rejectRequest(request['id']),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpcomingBookingsPreview() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getChefUpcomingBookings(),
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? [];
        if (bookings.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Bookings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentIndex = 2),
                    child: const Text('View All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...bookings.take(2).map((booking) => _BookingPreviewCard(
                booking: booking,
                onTap: () => widget.onNavigate?.call(
                  'booking_details',
                  data: {'bookingId': booking['id']},
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickActionButton(
                icon: Icons.edit,
                label: 'Edit Profile',
                onTap: () => widget.onNavigate?.call('edit_profile'),
              ),
              const SizedBox(width: 12),
              _buildQuickActionButton(
                icon: Icons.payments,
                label: 'Earnings',
                onTap: () => widget.onNavigate?.call('earnings'),
              ),
              const SizedBox(width: 12),
              _buildQuickActionButton(
                icon: Icons.reviews,
                label: 'My Reviews',
                onTap: () => widget.onNavigate?.call('reviews'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================
  // REQUESTS TAB
  // ===========================================
  Widget _buildRequestsTab() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Requests'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getPendingRequests(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('Requests Tab Error: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'Error loading requests',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No pending requests',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'New booking requests will appear here',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chef ID: ${_auth.currentUser?.uid ?? "Not logged in"}',
                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _InDriveRequestCard(
                request: request,
                onAccept: () => _acceptRequest(request['id']),
                onReject: () => _rejectRequest(request['id']),
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================
  // BOOKINGS TAB
  // ===========================================
  Widget _buildBookingsTab() {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Bookings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChefBookingsList('confirmed'),
            _buildChefBookingsList('completed'),
            _buildChefBookingsList('cancelled'),
          ],
        ),
      ),
    );
  }

  Widget _buildChefBookingsList(String status) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getChefBookings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allBookings = snapshot.data ?? [];
        final bookings = allBookings.where((b) {
          final s = b['status'] as String? ?? '';
          if (status == 'confirmed') return s == 'confirmed';
          if (status == 'completed') return s == 'completed';
          return s.contains('cancelled');
        }).toList();

        if (bookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'confirmed'
                      ? Icons.calendar_today_outlined
                      : status == 'completed'
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No ${status == 'cancelled' ? 'cancelled' : status} bookings',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            return _ChefBookingCard(
              booking: booking,
              onTap: () => widget.onNavigate?.call(
                'booking_details',
                data: {'bookingId': booking['id']},
              ),
              onComplete: status == 'confirmed'
                  ? () => _completeBooking(booking['id'])
                  : null,
            );
          },
        );
      },
    );
  }

  // ===========================================
  // CHATS TAB
  // ===========================================
  Widget _buildChatsTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _getChatList(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    'No messages yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chat with customers after accepting bookings',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return ListTile(
                leading: CachedChefAvatar(
                  imageUrl: chat['customerImage'],
                  name: chat['customerName'],
                  radius: 24,
                ),
                title: Text(chat['customerName'] ?? 'Customer'),
                subtitle: Text(
                  chat['lastMessage'] ?? 'Start chatting...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chat['chefUnread'] != null && chat['chefUnread'] > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${chat['chefUnread']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : null,
                onTap: () => widget.onNavigate?.call(
                  'chat',
                  data: {'chatId': chat['id'], 'customerId': chat['customerId']},
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================
  // PROFILE TAB
  // ===========================================
  Widget _buildProfileTab() {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profile Header
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CachedChefAvatar(
                              imageUrl: chefData?['image'],
                              name: chefData?['name'],
                              radius: 50,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: chefData?['isAvailable'] == true
                                      ? Colors.green
                                      : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Icon(
                                  chefData?['isAvailable'] == true
                                      ? Icons.check
                                      : Icons.remove,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          chefData?['name'] ?? 'Chef',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              '${(chefData?['rating'] ?? 0.0).toStringAsFixed(1)} (${chefData?['reviewCount'] ?? 0} reviews)',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Earnings Summary Card
                  _buildEarningsSummaryCard(),

                  const SizedBox(height: 16),

                  // Menu Items
                  _buildMenuItem(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    onTap: () => widget.onNavigate?.call('edit_profile'),
                  ),
                  _buildMenuItem(
                    icon: Icons.restaurant_menu,
                    title: 'My Menu & Specialties',
                    onTap: () => widget.onNavigate?.call('edit_profile'),
                  ),
                  _buildMenuItem(
                    icon: Icons.payments,
                    title: 'My Earnings',
                    onTap: () => widget.onNavigate?.call('earnings'),
                  ),
                  _buildMenuItem(
                    icon: Icons.schedule,
                    title: 'Availability Settings',
                    onTap: () => _showAvailabilitySettings(),
                  ),
                  _buildMenuItem(
                    icon: Icons.star_outline,
                    title: 'My Reviews',
                    onTap: () => widget.onNavigate?.call('reviews'),
                  ),
                  _buildMenuItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () => widget.onNavigate?.call('notifications'),
                  ),
                  _buildMenuItem(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () => widget.onNavigate?.call('support'),
                  ),
                  _buildMenuItem(
                    icon: Icons.logout,
                    title: 'Logout',
                    color: Colors.red,
                    onTap: _logout,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      trailing: Icon(Icons.chevron_right, color: color ?? Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildEarningsSummaryCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: BookingRequestService.getChefStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade700],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Total Earnings',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Rs. ${stats['totalEarnings'] ?? 0}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        '${stats['completedBookings'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Completed',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        '${stats['totalBookings'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'Total',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================
  // HELPER METHODS
  // ===========================================

  Stream<List<Map<String, dynamic>>> _getPendingRequests() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      debugPrint('_getPendingRequests: No user logged in');
      return Stream.value([]);
    }

    debugPrint('_getPendingRequests: Fetching for chef UID: $uid');

    return _firestore
        .collection('bookingRequests')
        .where('chefId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .handleError((error) {
          debugPrint('_getPendingRequests ERROR: $error');
          return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        })
        .map((snapshot) {
          debugPrint('_getPendingRequests: Found ${snapshot.docs.length} pending requests');
          for (var doc in snapshot.docs) {
            final data = doc.data();
            debugPrint('  Request ${doc.id}: chefId=${data['chefId']}, customer=${data['customerName']}');
          }

          final list = snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList();
          // Sort locally by createdAt descending
          list.sort((a, b) {
            final aTime = a['createdAt'] as Timestamp?;
            final bTime = b['createdAt'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });
          return list;
        });
  }

  Stream<int> _getPendingRequestsCount() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('bookingRequests')
        .where('chefId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<int> _getUnreadChatCount() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('chats')
        .where('chefId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          int count = 0;
          for (var doc in snapshot.docs) {
            count += (doc.data()['chefUnread'] as int?) ?? 0;
          }
          return count;
        });
  }

  Stream<List<Map<String, dynamic>>> _getChatList() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('chats')
        .where('chefId', isEqualTo: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  Future<void> _toggleAvailability(bool value) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore.collection('users').doc(uid).update({
        'isAvailable': value,
      });

      setState(() {
        chefData?['isAvailable'] = value;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'You are now online' : 'You are now offline'),
            backgroundColor: value ? Colors.green : Colors.grey,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling availability: $e');
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    final success = await BookingRequestService.acceptRequest(requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Booking accepted!' : 'Failed to accept'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request?'),
        content: const Text('Are you sure you want to reject this request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await BookingRequestService.rejectRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Request rejected' : 'Failed to reject'),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _completeBooking(String bookingId) async {
    final success = await BookingRequestService.markBookingCompleted(bookingId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Booking marked as completed!' : 'Failed'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _showAvailabilitySettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Availability Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  // Online/Offline Toggle
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (chefData?['isAvailable'] == true)
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          chefData?['isAvailable'] == true
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: chefData?['isAvailable'] == true
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chefData?['isAvailable'] == true
                                    ? 'You are Online'
                                    : 'You are Offline',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                chefData?['isAvailable'] == true
                                    ? 'Customers can send you booking requests'
                                    : 'You won\'t receive new booking requests',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: chefData?['isAvailable'] ?? false,
                          onChanged: (value) async {
                            await _toggleAvailability(value);
                            setModalState(() {});
                          },
                          activeTrackColor: Colors.green.shade200,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'When offline, your profile will be hidden from search results.',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await NotificationService.clearToken();
      await _auth.signOut();
      widget.onNavigate?.call('login');
    }
  }
}

// ===========================================
// HELPER WIDGETS
// ===========================================

class _RequestPreviewCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _RequestPreviewCard({
    required this.request,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CachedChefAvatar(
              imageUrl: request['customerImage'],
              name: request['customerName'],
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request['customerName'] ?? 'Customer',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${request['date']} • Rs. ${request['offeredPrice'] ?? 0}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: onReject,
            ),
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: onAccept,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingPreviewCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;

  const _BookingPreviewCard({
    required this.booking,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CachedChefAvatar(
          imageUrl: booking['customerImage'],
          name: booking['customerName'],
          radius: 20,
        ),
        title: Text(booking['customerName'] ?? 'Customer'),
        subtitle: Text('${booking['date']} at ${booking['time']}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _InDriveRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _InDriveRequestCard({
    required this.request,
    this.onAccept,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CachedChefAvatar(
                  imageUrl: request['customerImage'],
                  name: request['customerName'],
                  radius: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['customerName'] ?? 'Customer',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'New booking request',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildDetailRow(Icons.calendar_today, 'Date', request['date'] ?? '-'),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.access_time, 'Time', request['time'] ?? '-'),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.location_on, 'Location', request['location'] ?? '-'),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.people, 'Guests', '${request['guestCount'] ?? 0} people'),
              ],
            ),
          ),

          // Price
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.green.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Offered Price'),
                Text(
                  'Rs. ${request['offeredPrice'] ?? 0}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text('Reject', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: Colors.grey[600])),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ChefBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;

  const _ChefBookingCard({
    required this.booking,
    this.onTap,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  CachedChefAvatar(
                    imageUrl: booking['customerImage'],
                    name: booking['customerName'],
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['customerName'] ?? 'Customer',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${booking['date']} at ${booking['time']}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Rs. ${booking['price'] ?? 0}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
              if (status == 'confirmed' && onComplete != null) ...[
                const Divider(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check),
                    label: const Text('Mark as Completed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

