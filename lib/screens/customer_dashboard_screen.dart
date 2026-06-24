import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/booking_request_service.dart';
import '../services/notification_service.dart';
import '../widgets/cached_chef_image.dart';
import 'customer_documents_screen.dart';
import 'notifications_screen.dart';

/// Customer Dashboard - Main screen for customers after login
class CustomerDashboardScreen extends StatefulWidget {
  final Function(String screen, {Map<String, dynamic>? data})? onNavigate;

  const CustomerDashboardScreen({super.key, this.onNavigate});

  @override
  State<CustomerDashboardScreen> createState() => _CustomerDashboardScreenState();
}

class _CustomerDashboardScreenState extends State<CustomerDashboardScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? userData;
  bool isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() {
          userData = doc.data();
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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
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
  // HOME TAB
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
                'Hello, ${userData?['name']?.split(' ').first ?? 'there'}! 👋',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                'Find your perfect chef',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            // Notification Bell
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

        // Search Bar
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => widget.onNavigate?.call('find_chefs'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey[600]),
                    const SizedBox(width: 12),
                    Text(
                      'Search for chefs...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Quick Actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildQuickAction(
                  icon: Icons.restaurant_menu,
                  label: 'Find Chef',
                  color: Colors.orange,
                  onTap: () => widget.onNavigate?.call('find_chefs'),
                ),
                const SizedBox(width: 12),
                _buildQuickAction(
                  icon: Icons.history,
                  label: 'Past Orders',
                  color: Colors.blue,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                const SizedBox(width: 12),
                _buildQuickAction(
                  icon: Icons.favorite,
                  label: 'Favorites',
                  color: Colors.red,
                  onTap: () => widget.onNavigate?.call('favorites'),
                ),
              ],
            ),
          ),
        ),

        // Current Booking Status
        SliverToBoxAdapter(
          child: _buildCurrentBookingSection(),
        ),

        // Pending Requests
        SliverToBoxAdapter(
          child: _buildPendingRequestsSection(),
        ),

        // Recent Chefs
        SliverToBoxAdapter(
          child: _buildRecentChefsSection(),
        ),

        // Spacing at bottom
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentBookingSection() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getCustomerUpcomingBookings(),
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? [];
        if (bookings.isEmpty) return const SizedBox.shrink();

        final booking = bookings.first;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upcoming Booking',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _CurrentBookingCard(
                booking: booking,
                onTap: () => widget.onNavigate?.call(
                  'booking_details',
                  data: {'bookingId': booking['id']},
                ),
                onChat: () => widget.onNavigate?.call(
                  'chat',
                  data: {'chefId': booking['chefId']},
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingRequestsSection() {
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
                    'Pending Requests',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${requests.length}',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...requests.take(2).map((request) => _PendingRequestCard(
                request: request,
                onCancel: () => _cancelRequest(request['id']),
              )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentChefsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getRecentChefs(),
      builder: (context, snapshot) {
        final chefs = snapshot.data ?? [];
        if (chefs.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your Recent Chefs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: chefs.length,
                  itemBuilder: (context, index) {
                    final chef = chefs[index];
                    return GestureDetector(
                      onTap: () => widget.onNavigate?.call(
                        'chef_profile',
                        data: {'chefId': chef['id']},
                      ),
                      child: Container(
                        width: 80,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            CachedChefAvatar(
                              imageUrl: chef['image'],
                              name: chef['name'],
                              radius: 30,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              chef['name']?.split(' ').first ?? 'Chef',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
            _buildBookingsList('confirmed'),
            _buildBookingsList('completed'),
            _buildBookingsList('cancelled'),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(String status) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getCustomerBookings(),
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
                  status == 'confirmed'
                      ? 'No upcoming bookings'
                      : status == 'completed'
                          ? 'No completed bookings'
                          : 'No cancelled bookings',
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
            return _BookingCard(
              booking: booking,
              onTap: () => widget.onNavigate?.call(
                'booking_details',
                data: {'bookingId': booking['id']},
              ),
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
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text('No messages yet'),
                  const SizedBox(height: 8),
                  Text(
                    'Chat with chefs after booking',
                    style: TextStyle(color: Colors.grey[600]),
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
                  imageUrl: chat['chefImage'],
                  name: chat['chefName'],
                  radius: 24,
                ),
                title: Text(chat['chefName'] ?? 'Chef'),
                subtitle: Text(
                  chat['lastMessage'] ?? 'Start chatting...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: chat['unreadCount'] > 0
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${chat['unreadCount']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : null,
                onTap: () => widget.onNavigate?.call(
                  'chat',
                  data: {'chatId': chat['id'], 'chefId': chat['chefId']},
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
      appBar: AppBar(title: const Text('Profile')),
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
                        CachedChefAvatar(
                          imageUrl: userData?['image'],
                          name: userData?['name'],
                          radius: 50,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          userData?['name'] ?? 'Customer',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userData?['email'] ?? '',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Stats
                  _buildStatsRow(),

                  const SizedBox(height: 24),

                  // Menu Items
                  _buildMenuItem(
                    icon: Icons.person_outline,
                    title: 'Edit Profile',
                    onTap: () => widget.onNavigate?.call('edit_profile'),
                  ),
                  _buildVerificationMenuItem(),
                  _buildMenuItem(
                    icon: Icons.location_on_outlined,
                    title: 'Saved Addresses',
                    onTap: () => widget.onNavigate?.call('addresses'),
                  ),
                  _buildMenuItem(
                    icon: Icons.favorite_outline,
                    title: 'Favorite Chefs',
                    onTap: () => widget.onNavigate?.call('favorites'),
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

  Widget _buildStatsRow() {
    return FutureBuilder<Map<String, dynamic>>(
      future: BookingRequestService.getCustomerStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};
        return Row(
          children: [
            _buildStatItem(
              '${stats['totalBookings'] ?? 0}',
              'Bookings',
              Icons.calendar_today,
            ),
            _buildStatItem(
              '${stats['completedBookings'] ?? 0}',
              'Completed',
              Icons.check_circle,
            ),
            _buildStatItem(
              '${stats['uniqueChefs'] ?? 0}',
              'Chefs',
              Icons.restaurant,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
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
                fontSize: 12,
                color: Colors.grey[600],
              ),
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

  Widget _buildVerificationMenuItem() {
    final verificationStatus = userData?['verificationStatus'] ?? 'not_submitted';

    Color statusColor;
    IconData statusIcon;
    String statusText;
    Widget? trailing;

    switch (verificationStatus) {
      case 'verified':
        statusColor = Colors.green;
        statusIcon = Icons.verified;
        statusText = 'Verified';
        trailing = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(statusText, style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Pending';
        trailing = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.pending, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Text(statusText, style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusText = 'Rejected';
        trailing = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning, color: Colors.red, size: 16),
              const SizedBox(width: 4),
              Text(statusText, style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.badge_outlined;
        statusText = 'Not Verified';
        trailing = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Verify Now',
            style: TextStyle(color: Colors.deepPurple, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        );
    }

    return ListTile(
      leading: Icon(statusIcon, color: statusColor),
      title: const Text('CNIC Verification'),
      trailing: trailing,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CustomerDocumentsScreen(
              onBack: () => Navigator.pop(context),
              onSave: () {
                Navigator.pop(context);
                _loadUserData(); // Refresh data
              },
            ),
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
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('bookingRequests')
        .where('customerId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  Future<List<Map<String, dynamic>>> _getRecentChefs() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return [];

      // Get recent bookings
      final bookings = await _firestore
          .collection('bookings')
          .where('customerId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      // Get unique chef IDs
      final chefIds = bookings.docs
          .map((doc) => doc.data()['chefId'] as String?)
          .where((id) => id != null)
          .toSet()
          .take(5)
          .toList();

      // Get chef details
      List<Map<String, dynamic>> chefs = [];
      for (var chefId in chefIds) {
        final chefDoc = await _firestore.collection('users').doc(chefId).get();
        if (chefDoc.exists) {
          chefs.add({'id': chefId, ...chefDoc.data()!});
        }
      }

      return chefs;
    } catch (e) {
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> _getChatList() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('chats')
        .where('customerId', isEqualTo: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  Stream<int> _getUnreadChatCount() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _firestore
        .collection('chats')
        .where('customerId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          int count = 0;
          for (var doc in snapshot.docs) {
            count += (doc.data()['customerUnread'] as int?) ?? 0;
          }
          return count;
        });
  }

  Future<void> _cancelRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('Are you sure you want to cancel this booking request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await BookingRequestService.cancelRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Request cancelled' : 'Failed to cancel'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
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

class _CurrentBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;
  final VoidCallback? onChat;

  const _CurrentBookingCard({
    required this.booking,
    this.onTap,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  CachedChefAvatar(
                    imageUrl: booking['chefImage'],
                    name: booking['chefName'],
                    radius: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['chefName'] ?? 'Chef',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${booking['date']} at ${booking['time']}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Confirmed',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onChat,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Chat'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: const Text('Details'),
                    ),
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

class _PendingRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onCancel;

  const _PendingRequestCard({
    required this.request,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CachedChefAvatar(
              imageUrl: request['chefImage'],
              name: request['chefName'],
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request['chefName'] ?? 'Chef',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Waiting for response...',
                    style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onCancel,
              child: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;

  const _BookingCard({
    required this.booking,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CachedChefAvatar(
                imageUrl: booking['chefImage'],
                name: booking['chefName'],
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking['chefName'] ?? 'Chef',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${booking['date']} • Rs. ${booking['price'] ?? 0}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        text = 'Confirmed';
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        break;
      default:
        color = Colors.red;
        text = 'Cancelled';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

