import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/cached_chef_image.dart';

/// Customer Booking History Screen - Enhanced with all booking states
class CustomerBookingHistoryScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(String screen, {Map<String, dynamic>? data})? onNavigate;

  const CustomerBookingHistoryScreen({super.key, this.onBack, this.onNavigate});

  @override
  State<CustomerBookingHistoryScreen> createState() => _CustomerBookingHistoryScreenState();
}

class _CustomerBookingHistoryScreenState extends State<CustomerBookingHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Confirmed'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingList('pending'),
          _buildBookingList('confirmed'),
          _buildBookingList('completed'),
          _buildBookingList('cancelled'),
        ],
      ),
    );
  }

  Widget _buildBookingList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getBookingsStream(status),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _buildEmptyState(status);
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              data['id'] = docs[index].id;

              // Debug: Check rating status
              final bool isRated = data['rated'] == true;
              debugPrint('Booking ${docs[index].id}: status=$status, rated=$isRated, chefId=${data['chefId']}');

              return _BookingCard(
                booking: data,
                status: status,
                onTap: () => widget.onNavigate?.call(
                  'booking_details',
                  data: {'bookingId': docs[index].id},
                ),
                onRebook: status == 'completed' || status == 'cancelled'
                    ? () => _rebookChef(data['chefId'])
                    : null,
                onRate: (status == 'completed' && !isRated)
                    ? () {
                        debugPrint('Rate button clicked for booking: ${docs[index].id}');
                        _showRatingDialog(docs[index].id, data['chefId']);
                      }
                    : null,
                onCancel: status == 'pending' || status == 'confirmed'
                    ? () => _cancelBooking(docs[index].id, status)
                    : null,
                // Chat only allowed after order is accepted (confirmed status)
                onChat: status == 'confirmed'
                    ? () => widget.onNavigate?.call(
                          'chat',
                          data: {'chefId': data['chefId']},
                        )
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  Stream<QuerySnapshot> _getBookingsStream(String status) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    // Determine which collection and status to query
    if (status == 'pending') {
      // Pending requests
      return _firestore
          .collection('bookingRequests')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else if (status == 'confirmed') {
      // Confirmed bookings
      return _firestore
          .collection('bookings')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'confirmed')
          .orderBy('createdAt', descending: true)
          .snapshots();
    } else if (status == 'completed') {
      // Completed bookings
      return _firestore
          .collection('bookings')
          .where('customerId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('completedAt', descending: true)
          .snapshots();
    } else {
      // Cancelled - both requests and bookings
      return _firestore
          .collection('bookings')
          .where('customerId', isEqualTo: uid)
          .where('status', whereIn: ['cancelled', 'cancelled_by_customer', 'cancelled_by_chef', 'rejected'])
          .orderBy('createdAt', descending: true)
          .snapshots();
    }
  }

  Widget _buildEmptyState(String status) {
    IconData icon;
    String title;
    String subtitle;

    switch (status) {
      case 'pending':
        icon = Icons.hourglass_empty;
        title = 'No pending requests';
        subtitle = 'Your booking requests will appear here';
        break;
      case 'confirmed':
        icon = Icons.calendar_today;
        title = 'No upcoming bookings';
        subtitle = 'Your confirmed bookings will appear here';
        break;
      case 'completed':
        icon = Icons.check_circle_outline;
        title = 'No completed bookings';
        subtitle = 'Your past bookings will appear here';
        break;
      default:
        icon = Icons.cancel_outlined;
        title = 'No cancelled bookings';
        subtitle = 'Cancelled bookings will appear here';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey[600]),
          ),
          if (status == 'pending' || status == 'confirmed') ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => widget.onNavigate?.call('browse_chefs'),
              icon: const Icon(Icons.search),
              label: const Text('Find Chefs'),
            ),
          ],
        ],
      ),
    );
  }

  void _rebookChef(String? chefId) {
    if (chefId == null) return;
    widget.onNavigate?.call('chef_profile', data: {'chefId': chefId});
  }

  Future<void> _cancelBooking(String bookingId, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Text(
          status == 'pending'
              ? 'Are you sure you want to cancel this request?'
              : 'Are you sure you want to cancel this booking?',
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

    if (confirmed == true) {
      try {
        final collection = status == 'pending' ? 'bookingRequests' : 'bookings';
        await _firestore.collection(collection).doc(bookingId).update({
          'status': 'cancelled_by_customer',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showRatingDialog(String bookingId, String? chefId) async {
    if (chefId == null) return;

    int selectedRating = 5;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Rate Your Experience'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Star Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () {
                        setDialogState(() => selectedRating = index + 1);
                      },
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  _getRatingText(selectedRating),
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // Review Text
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Write your review (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await _submitRating(bookingId, chefId, selectedRating, reviewController.text);
    }

    reviewController.dispose();
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }

  Future<void> _submitRating(
    String bookingId,
    String chefId,
    int rating,
    String review,
  ) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Get customer info
      final customerDoc = await _firestore.collection('users').doc(uid).get();
      final customerData = customerDoc.data();

      // Create review document
      await _firestore.collection('reviews').add({
        'chefId': chefId,
        'customerId': uid,
        'customerName': customerData?['name'] ?? 'Customer',
        'customerImage': customerData?['image'] ?? '',
        'bookingId': bookingId,
        'rating': rating,
        'review': review,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update booking as rated
      await _firestore.collection('bookings').doc(bookingId).update({
        'rated': true,
        'rating': rating,
      });

      // Update chef's average rating
      await _updateChefRating(chefId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateChefRating(String chefId) async {
    try {
      // Get all reviews for this chef
      final reviews = await _firestore
          .collection('reviews')
          .where('chefId', isEqualTo: chefId)
          .get();

      if (reviews.docs.isEmpty) return;

      // Calculate average
      double total = 0;
      for (var doc in reviews.docs) {
        total += (doc.data()['rating'] ?? 0) as int;
      }
      final average = total / reviews.docs.length;

      // Update chef profile
      await _firestore.collection('users').doc(chefId).update({
        'rating': double.parse(average.toStringAsFixed(1)),
        'reviewCount': reviews.docs.length,
      });
    } catch (e) {
      debugPrint('Error updating chef rating: $e');
    }
  }
}

// Booking Card Widget
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String status;
  final VoidCallback? onTap;
  final VoidCallback? onRebook;
  final VoidCallback? onRate;
  final VoidCallback? onCancel;
  final VoidCallback? onChat;

  const _BookingCard({
    required this.booking,
    required this.status,
    this.onTap,
    this.onRebook,
    this.onRate,
    this.onCancel,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Header with chef info - tappable area
          InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CachedChefAvatar(
                    imageUrl: booking['chefImage'],
                    name: booking['chefName'],
                    radius: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['chefName'] ?? 'Chef',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          booking['serviceType'] ?? 'Cooking Service',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(),
                ],
              ),
            ),
          ),

          // Booking Details - tappable area
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Row(
                children: [
                  _buildDetailItem(Icons.calendar_today, booking['date'] ?? '-'),
                  const SizedBox(width: 24),
                  _buildDetailItem(Icons.access_time, booking['time'] ?? '-'),
                  const SizedBox(width: 24),
                  _buildDetailItem(
                    Icons.payments,
                    'Rs. ${booking['price'] ?? booking['offeredPrice'] ?? 0}',
                  ),
                ],
              ),
            ),
          ),

          // Actions - NOT inside InkWell so buttons work properly
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildActions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        text = 'Pending';
        icon = Icons.hourglass_empty;
        break;
      case 'confirmed':
        color = Colors.green;
        text = 'Confirmed';
        icon = Icons.check_circle;
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        icon = Icons.check;
        break;
      default:
        color = Colors.red;
        text = 'Cancelled';
        icon = Icons.cancel;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    List<Widget> actions = [];

    debugPrint('_buildActions: onRate=${onRate != null}, onRebook=${onRebook != null}, onChat=${onChat != null}, onCancel=${onCancel != null}');

    if (onChat != null) {
      actions.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onChat,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Chat'),
          ),
        ),
      );
    }

    if (onCancel != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
            label: const Text('Cancel', style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (onRate != null) {
      debugPrint('Adding Rate button');
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              debugPrint('Rate button onPressed triggered');
              onRate!();
            },
            icon: const Icon(Icons.star, size: 18),
            label: const Text('Rate'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          ),
        ),
      );
    }

    if (onRebook != null) {
      if (actions.isNotEmpty) actions.add(const SizedBox(width: 8));
      actions.add(
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onRebook,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Rebook'),
          ),
        ),
      );
    }

    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Row(children: actions);
  }
}

