import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/booking_request_service.dart';
import '../widgets/cached_chef_image.dart';
import 'chat_screen.dart';

/// Chef's booking management screen - view and manage confirmed bookings
class ChefBookingsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(Map<String, dynamic> booking)? onBookingTap;
  final Function(String customerId)? onChatWithCustomer;

  const ChefBookingsScreen({
    super.key,
    this.onBack,
    this.onBookingTap,
    this.onChatWithCustomer,
  });

  @override
  State<ChefBookingsScreen> createState() => _ChefBookingsScreenState();
}

class _ChefBookingsScreenState extends State<ChefBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingsTab('confirmed'),
          _buildBookingsTab('completed'),
          _buildBookingsTab('cancelled'),
        ],
      ),
    );
  }

  Widget _buildBookingsTab(String statusFilter) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getChefBookings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allBookings = snapshot.data ?? [];
        final bookings = allBookings.where((b) {
          final status = b['status'] as String? ?? '';
          if (statusFilter == 'confirmed') {
            return status == 'confirmed';
          } else if (statusFilter == 'completed') {
            return status == 'completed';
          } else {
            return status.contains('cancelled');
          }
        }).toList();

        if (bookings.isEmpty) {
          return _buildEmptyState(statusFilter);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            return _ChefBookingCard(
              booking: bookings[index],
              onTap: () => widget.onBookingTap?.call(bookings[index]),
              onChat: () => _openChat(bookings[index]),
              onMarkComplete: bookings[index]['status'] == 'confirmed'
                  ? () => _markComplete(bookings[index])
                  : null,
              onCancel: bookings[index]['status'] == 'confirmed'
                  ? () => _cancelBooking(bookings[index])
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String status) {
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case 'confirmed':
        icon = Icons.calendar_today_outlined;
        title = 'No Upcoming Bookings';
        subtitle = 'Accept requests to see bookings here';
        break;
      case 'completed':
        icon = Icons.check_circle_outline;
        title = 'No Completed Bookings';
        subtitle = 'Completed services will appear here';
        break;
      default:
        icon = Icons.cancel_outlined;
        title = 'No Cancelled Bookings';
        subtitle = 'Cancelled bookings will appear here';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  /// Open chat with customer
  void _openChat(Map<String, dynamic> booking) async {
    final chatId = booking['chatId'] as String?;
    final customerName = booking['customerName'] as String? ?? 'Customer';
    final customerImage = booking['customerImage'] as String?;
    final customerId = booking['customerId'] as String?;
    final bookingId = booking['id'] as String?;
    final requestId = booking['requestId'] as String?;

    debugPrint('=== Opening Chat ===');
    debugPrint('chatId: $chatId');
    debugPrint('bookingId: $bookingId');
    debugPrint('requestId: $requestId');
    debugPrint('customerId: $customerId');

    // Method 1: Use chatId directly if available
    if (chatId != null && chatId.isNotEmpty) {
      debugPrint('Method 1: Opening chat directly with chatId: $chatId');
      _navigateToChat(chatId, customerName, customerImage);
      return;
    }

    // Method 2: Search by bookingId
    if (bookingId != null && bookingId.isNotEmpty) {
      try {
        debugPrint('Method 2: Searching chat by bookingId: $bookingId');
        final chatQuery = await FirebaseFirestore.instance
            .collection('chats')
            .where('bookingId', isEqualTo: bookingId)
            .limit(1)
            .get();

        if (chatQuery.docs.isNotEmpty) {
          final foundChatId = chatQuery.docs.first.id;
          debugPrint('Found chat by bookingId: $foundChatId');
          _navigateToChat(foundChatId, customerName, customerImage);
          return;
        }
        debugPrint('No chat found by bookingId');
      } catch (e) {
        debugPrint('Error searching by bookingId: $e');
      }
    }

    // Method 3: Search by requestId
    if (requestId != null && requestId.isNotEmpty) {
      try {
        debugPrint('Method 3: Searching chat by requestId: $requestId');
        final chatQuery = await FirebaseFirestore.instance
            .collection('chats')
            .where('requestId', isEqualTo: requestId)
            .limit(1)
            .get();

        if (chatQuery.docs.isNotEmpty) {
          final foundChatId = chatQuery.docs.first.id;
          debugPrint('Found chat by requestId: $foundChatId');
          _navigateToChat(foundChatId, customerName, customerImage);
          return;
        }
        debugPrint('No chat found by requestId');
      } catch (e) {
        debugPrint('Error searching by requestId: $e');
      }
    }

    // Method 4: Search by customerId only and filter locally
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final currentChefId = FirebaseAuth.instance.currentUser?.uid;
        debugPrint('Method 4: Searching chat by customerId: $customerId, chefId: $currentChefId');

        final chatQuery = await FirebaseFirestore.instance
            .collection('chats')
            .where('customerId', isEqualTo: customerId)
            .limit(10)
            .get();

        debugPrint('Found ${chatQuery.docs.length} chats for customer');

        // Filter locally by chefId
        for (var doc in chatQuery.docs) {
          final data = doc.data();
          if (data['chefId'] == currentChefId) {
            debugPrint('Found matching chat: ${doc.id}');
            _navigateToChat(doc.id, customerName, customerImage);
            return;
          }
        }
        debugPrint('No matching chat found for this chef');
      } catch (e) {
        debugPrint('Error searching by customerId: $e');
      }
    }

    // No chat found - Create a new chat or show message
    debugPrint('No chat found - showing message');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat not available for this booking'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Navigate to chat screen
  void _navigateToChat(String chatId, String customerName, String? customerImage) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUserName: customerName,
            otherUserImage: customerImage,
            isChefView: true,
          ),
        ),
      );
    }
  }

  Future<void> _markComplete(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Complete?'),
        content: Text(
          'Mark the service for ${booking['customerName']} as completed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Yes, Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final bookingId = booking['id'] as String?;
      if (bookingId != null) {
        final success = await BookingRequestService.markBookingCompleted(bookingId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Booking marked as completed!' : 'Failed to update booking',
              ),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    String? reason;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel the booking with ${booking['customerName']}?',
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (v) => reason = v,
            ),
          ],
        ),
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

    if (confirmed == true && mounted) {
      final requestId = booking['requestId'] as String?;
      if (requestId != null) {
        final success = await BookingRequestService.chefCancelBooking(
          requestId,
          reason: reason ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Booking cancelled' : 'Failed to cancel booking',
              ),
              backgroundColor: success ? Colors.orange : Colors.red,
            ),
          );
        }
      }
    }
  }
}

/// Individual booking card for chef
class _ChefBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;
  final VoidCallback? onChat;
  final VoidCallback? onMarkComplete;
  final VoidCallback? onCancel;

  const _ChefBookingCard({
    required this.booking,
    this.onTap,
    this.onChat,
    this.onMarkComplete,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String? ?? 'confirmed';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with customer info and status
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          booking['serviceType'] == 'event'
                              ? 'Event Catering'
                              : 'Home Cooking',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
                ],
              ),

              const Divider(height: 24),

              // Booking details
              _buildDetailRow(Icons.calendar_today, booking['date'] ?? ''),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.access_time, booking['time'] ?? ''),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.location_on, _getLocationString(booking)),
              const SizedBox(height: 8),
              _buildDetailRow(Icons.people, '${booking['guestCount'] ?? 0} guests'),

              if (booking['note'] != null && (booking['note'] as String).isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow(Icons.note, booking['note']),
              ],

              const SizedBox(height: 12),

              // Earnings
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Your Earnings'),
                    Text(
                      'Rs. ${booking['price'] ?? 0}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              // Action buttons for confirmed bookings
              if (status == 'confirmed') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChat,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Chat', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onMarkComplete,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Complete', overflow: TextOverflow.ellipsis),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
                    label: const Text('Cancel Booking', style: TextStyle(color: Colors.red), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[700]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        text = 'Confirmed';
        icon = Icons.check_circle;
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        icon = Icons.done_all;
        break;
      case 'cancelled':
      case 'cancelled_by_customer':
        color = Colors.orange;
        text = 'Customer Cancelled';
        icon = Icons.cancel;
        break;
      case 'cancelled_by_chef':
        color = Colors.red;
        text = 'You Cancelled';
        icon = Icons.cancel;
        break;
      default:
        color = Colors.grey;
        text = status;
        icon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper to get location string from booking data
  String _getLocationString(Map<String, dynamic> booking) {
    // First check if there's an address field
    if (booking['address'] != null && booking['address'].toString().isNotEmpty) {
      return booking['address'].toString();
    }

    final location = booking['location'];
    if (location == null) return 'Location not specified';

    // If it's already a string, return it
    if (location is String) return location;

    // If it's a GeoPoint
    if (location is GeoPoint) {
      return 'Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}';
    }

    // If it's a Map with lat/lng
    if (location is Map) {
      final lat = location['lat'] ?? location['latitude'];
      final lng = location['lng'] ?? location['longitude'];
      if (lat != null && lng != null) {
        return 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}';
      }
    }

    return 'Location available';
  }
}

