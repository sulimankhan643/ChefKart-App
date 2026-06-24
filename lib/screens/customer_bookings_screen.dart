import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../services/booking_request_service.dart';
import '../services/deal_negotiation_service.dart';
import '../services/chat_service.dart';
import '../models/cooking_request.dart';
import '../widgets/cached_chef_image.dart';
import 'indrive_live_tracking_screen.dart';
import 'view_offers_screen.dart';
import 'chat_screen.dart';

/// Customer's booking history and upcoming bookings screen
class CustomerBookingsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final Function(Map<String, dynamic> booking)? onBookingTap;
  final Function(String chefId)? onChatWithChef;

  const CustomerBookingsScreen({
    super.key,
    this.onBack,
    this.onBookingTap,
    this.onChatWithChef,
  });

  @override
  State<CustomerBookingsScreen> createState() => _CustomerBookingsScreenState();
}

class _CustomerBookingsScreenState extends State<CustomerBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Changed to 4 tabs
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
        title: const Text('My Orders'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Accepted'),
            Tab(text: 'Completed'),
            Tab(text: 'Cancelled'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRequestsTab(),  // NEW: Pending tab
          _buildBookingsTab('confirmed'),
          _buildBookingsTab('completed'),
          _buildBookingsTab('cancelled'),
        ],
      ),
    );
  }

  /// NEW: Build pending requests tab - shows BOTH direct requests and broadcast requests
  Widget _buildPendingRequestsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Broadcast Requests Section (InDrive-style)
          _buildBroadcastRequestsSection(),

          const SizedBox(height: 24),

          // Direct Requests Section
          _buildDirectRequestsSection(),
        ],
      ),
    );
  }

  /// Build broadcast requests section (cookingRequests collection)
  Widget _buildBroadcastRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.broadcast_on_home, color: Colors.deepPurple.shade700, size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'Broadcast Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Requests sent to all nearby chefs',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<CookingRequest>>(
          stream: DealNegotiationService.getCustomerPendingRequests(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final requests = snapshot.data ?? [];

            if (requests.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No broadcast requests',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: requests.map((request) =>
                _BroadcastRequestCard(
                  request: request,
                  onViewOffers: () => _viewBroadcastOffers(request.id),
                  onCancel: () => _cancelBroadcastRequest(request),
                ),
              ).toList(),
            );
          },
        ),
      ],
    );
  }

  /// Build direct requests section (bookingRequests collection)
  Widget _buildDirectRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.person, color: Colors.orange.shade700, size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'Direct Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Requests sent to specific chefs',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: BookingRequestService.getCustomerPendingRequests(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final requests = snapshot.data ?? [];

            if (requests.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.hourglass_empty, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No direct requests pending',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: requests.map((request) =>
                _PendingRequestCard(
                  request: request,
                  onCancel: () => _cancelPendingRequest(request),
                ),
              ).toList(),
            );
          },
        ),
      ],
    );
  }

  /// View offers for a broadcast request
  void _viewBroadcastOffers(String requestId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ViewOffersScreen(
          requestId: requestId,
          onBack: () => Navigator.pop(context),
          onConfirmed: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Chef Confirmed!'),
                backgroundColor: Colors.green,
              ),
            );
          },
          onExpired: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ Request expired'),
                backgroundColor: Colors.orange,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Cancel a broadcast request
  Future<void> _cancelBroadcastRequest(CookingRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: const Text('Cancel this broadcast request? All pending offers will be discarded.'),
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
      final success = await DealNegotiationService.cancelRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Request cancelled' : 'Failed to cancel'),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelPendingRequest(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request?'),
        content: Text('Cancel your request to ${request['chefName']}?'),
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
      final success = await BookingRequestService.cancelRequest(request['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Request cancelled' : 'Failed to cancel'),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBookingsTab(String statusFilter) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: BookingRequestService.getCustomerBookings(),
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
            return status.contains('cancelled') || status == 'rejected';
          }
        }).toList();

        if (bookings.isEmpty) {
          return _buildEmptyState(statusFilter);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: bookings.length,
          itemBuilder: (context, index) {
            final booking = bookings[index];
            return _BookingCard(
              booking: booking,
              onTap: () => widget.onBookingTap?.call(booking),
              onChat: () => _openChat(booking),
              onCancel: booking['status'] == 'confirmed'
                  ? () => _cancelBooking(booking)
                  : null,
              onRebook: booking['status'] == 'completed'
                  ? () => _rebookBooking(booking)
                  : null,
              onTrackChef: booking['status'] == 'confirmed'
                  ? () => _trackChef(booking)
                  : null,
              onReview: (booking['status'] == 'completed' && booking['reviewed'] != true)
                  ? () => _showReviewDialog(booking)
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
      case 'pending':
        icon = Icons.hourglass_empty;
        title = 'No Pending Orders';
        subtitle = 'Your pending orders will appear here';
        break;
      case 'confirmed':
        icon = Icons.calendar_today_outlined;
        title = 'No Accepted Bookings';
        subtitle = 'Your accepted bookings will appear here';
        break;
      case 'completed':
        icon = Icons.check_circle_outline;
        title = 'No Completed Bookings';
        subtitle = 'Your completed bookings will appear here';
        break;
      default:
        icon = Icons.cancel_outlined;
        title = 'No Cancelled/Rejected Orders';
        subtitle = 'Cancelled or rejected orders will appear here';
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

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: Text(
          'Are you sure you want to cancel your booking with ${booking['chefName']}?',
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
        final success = await BookingRequestService.cancelAcceptedBooking(requestId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Booking cancelled' : 'Failed to cancel booking',
              ),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Open chat with chef
  void _openChat(Map<String, dynamic> booking) async {
    final chatId = booking['chatId'] as String?;
    final chefName = booking['chefName'] as String? ?? 'Chef';
    final chefImage = booking['chefImage'] as String?;
    final chefId = booking['chefId'] as String?;
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to chat')),
      );
      return;
    }

    if (chatId != null && chatId.isNotEmpty) {
      // Chat ID exists in booking, open directly
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUserName: chefName,
            otherUserImage: chefImage,
            isChefView: false,
          ),
        ),
      );
    } else if (chefId != null && chefId.isNotEmpty) {
      // No chatId but we have chefId - create or find chat
      try {
        // First try to find existing chat by customerId and chefId
        final existingChat = await FirebaseFirestore.instance
            .collection('chats')
            .where('customerId', isEqualTo: currentUser.uid)
            .where('chefId', isEqualTo: chefId)
            .limit(1)
            .get();

        String finalChatId;
        if (existingChat.docs.isNotEmpty) {
          finalChatId = existingChat.docs.first.id;
        } else {
          // Create new chat
          final chatService = ChatService();
          finalChatId = await chatService.getOrCreateChat(
            customerId: currentUser.uid,
            chefId: chefId,
          );
        }

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                chatId: finalChatId,
                otherUserName: chefName,
                otherUserImage: chefImage,
                isChefView: false,
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error opening/creating chat: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open chat: $e')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat not available - missing chef info')),
      );
    }
  }

  /// Track chef location on map (InDrive style)
  void _trackChef(Map<String, dynamic> booking) async {
    // Get customer/service location from booking
    double lat = 34.0151; // Default Peshawar
    double lng = 71.5249;
    bool locationFound = false;

    // Try to get location from different possible fields
    final location = booking['location'];
    final customerLocation = booking['customerLocation'];
    final serviceLocation = booking['serviceLocation'];

    // Check location field
    if (location != null) {
      if (location is GeoPoint) {
        lat = location.latitude;
        lng = location.longitude;
        locationFound = true;
        debugPrint('TrackChef: Got location from GeoPoint: $lat, $lng');
      } else if (location is Map) {
        final locLat = location['lat'] ?? location['latitude'];
        final locLng = location['lng'] ?? location['longitude'];
        if (locLat != null && locLng != null) {
          lat = (locLat is num) ? locLat.toDouble() : double.tryParse(locLat.toString()) ?? lat;
          lng = (locLng is num) ? locLng.toDouble() : double.tryParse(locLng.toString()) ?? lng;
          locationFound = true;
          debugPrint('TrackChef: Got location from Map: $lat, $lng');
        }
      }
    }

    // Check customerLocation field
    if (!locationFound && customerLocation != null) {
      if (customerLocation is GeoPoint) {
        lat = customerLocation.latitude;
        lng = customerLocation.longitude;
        locationFound = true;
        debugPrint('TrackChef: Got customerLocation from GeoPoint: $lat, $lng');
      } else if (customerLocation is Map) {
        final locLat = customerLocation['lat'] ?? customerLocation['latitude'];
        final locLng = customerLocation['lng'] ?? customerLocation['longitude'];
        if (locLat != null && locLng != null) {
          lat = (locLat is num) ? locLat.toDouble() : double.tryParse(locLat.toString()) ?? lat;
          lng = (locLng is num) ? locLng.toDouble() : double.tryParse(locLng.toString()) ?? lng;
          locationFound = true;
          debugPrint('TrackChef: Got customerLocation from Map: $lat, $lng');
        }
      }
    }

    // Check serviceLocation field
    if (!locationFound && serviceLocation != null) {
      if (serviceLocation is GeoPoint) {
        lat = serviceLocation.latitude;
        lng = serviceLocation.longitude;
        locationFound = true;
        debugPrint('TrackChef: Got serviceLocation from GeoPoint: $lat, $lng');
      } else if (serviceLocation is Map) {
        final locLat = serviceLocation['lat'] ?? serviceLocation['latitude'];
        final locLng = serviceLocation['lng'] ?? serviceLocation['longitude'];
        if (locLat != null && locLng != null) {
          lat = (locLat is num) ? locLat.toDouble() : double.tryParse(locLat.toString()) ?? lat;
          lng = (locLng is num) ? locLng.toDouble() : double.tryParse(locLng.toString()) ?? lng;
          locationFound = true;
          debugPrint('TrackChef: Got serviceLocation from Map: $lat, $lng');
        }
      }
    }

    // If no location found in booking, try to get current location
    if (!locationFound) {
      debugPrint('TrackChef: No location in booking, trying to get current location...');
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        lat = position.latitude;
        lng = position.longitude;
        locationFound = true;
        debugPrint('TrackChef: Got current location: $lat, $lng');
      } catch (e) {
        debugPrint('TrackChef: Failed to get current location: $e');
        debugPrint('TrackChef: Using default Peshawar location');
      }
    }

    if (!mounted) return;

    // Open InDrive style live tracking
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IndriveLiveTrackingScreen(
          chefId: booking['chefId'] ?? '',
          chefName: booking['chefName'] ?? 'Chef',
          chefImage: booking['chefImage'],
          customerLocation: LatLng(lat, lng),
          bookingTime: booking['time'],
          bookingDate: booking['date'],
          onChat: () => _openChat(booking),
          onCall: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Calling chef...')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _rebookBooking(Map<String, dynamic> booking) async {
    // Show date picker for new date
    final newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (newDate == null || !mounted) return;

    // Show time picker for new time
    final newTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );

    if (newTime == null || !mounted) return;

    final dateStr = '${newDate.day}/${newDate.month}/${newDate.year}';
    final timeStr = newTime.format(context);

    final bookingId = booking['id'] as String?;
    if (bookingId == null) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final requestId = await BookingRequestService.rebookPreviousBooking(
      previousBookingId: bookingId,
      newDate: dateStr,
      newTime: timeStr,
    );

    if (mounted) {
      Navigator.pop(context); // Close loading

      if (requestId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rebook request sent! Waiting for chef response.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to rebook. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show review dialog for completed booking
  Future<void> _showReviewDialog(Map<String, dynamic> booking) async {
    final chefId = booking['chefId'] as String?;
    final bookingId = booking['id'] as String?;

    if (chefId == null || bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to review this booking'), backgroundColor: Colors.red),
      );
      return;
    }

    int selectedRating = 5;
    final reviewController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                const Text('Rate Your Experience'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'How was your experience with ${booking['chefName']}?',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                // Star Rating
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < selectedRating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 40,
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
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Review Text
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Share your experience (optional)',
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
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.send),
                label: const Text('Submit Review'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && mounted) {
      await _submitReview(bookingId, chefId, selectedRating, reviewController.text);
    }

    reviewController.dispose();
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1: return '😞 Poor';
      case 2: return '😐 Fair';
      case 3: return '🙂 Good';
      case 4: return '😊 Very Good';
      case 5: return '🤩 Excellent';
      default: return '';
    }
  }

  Future<void> _submitReview(String bookingId, String chefId, int rating, String review) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final firestore = FirebaseFirestore.instance;

      // Get customer info
      final customerDoc = await firestore.collection('users').doc(uid).get();
      final customerData = customerDoc.data();

      // Create review document
      await firestore.collection('reviews').add({
        'chefId': chefId,
        'customerId': uid,
        'customerName': customerData?['name'] ?? 'Customer',
        'customerImage': customerData?['image'] ?? '',
        'bookingId': bookingId,
        'rating': rating,
        'review': review,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update booking as reviewed
      await firestore.collection('bookings').doc(bookingId).update({
        'reviewed': true,
        'rating': rating,
      });

      // Update chef's average rating
      await _updateChefRating(chefId);

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your review! 🎉'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateChefRating(String chefId) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // Get all reviews for this chef
      final reviews = await firestore
          .collection('reviews')
          .where('chefId', isEqualTo: chefId)
          .get();

      if (reviews.docs.isEmpty) return;

      // Calculate average
      double total = 0;
      for (var doc in reviews.docs) {
        total += (doc.data()['rating'] ?? 0).toDouble();
      }
      final average = total / reviews.docs.length;

      // Update chef profile
      await firestore.collection('users').doc(chefId).update({
        'rating': double.parse(average.toStringAsFixed(1)),
        'reviewCount': reviews.docs.length,
      });
    } catch (e) {
      debugPrint('Error updating chef rating: $e');
    }
  }
}

/// Individual booking card widget
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback? onTap;
  final VoidCallback? onChat;
  final VoidCallback? onCancel;
  final VoidCallback? onRebook;
  final VoidCallback? onTrackChef;
  final VoidCallback? onReview;

  const _BookingCard({
    required this.booking,
    this.onTap,
    this.onChat,
    this.onCancel,
    this.onRebook,
    this.onTrackChef,
    this.onReview,
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
              // Header with chef info and status
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

              const SizedBox(height: 12),

              // Price
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total'),
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
                // Track Chef Button - Full width
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onTrackChef,
                    icon: const Icon(Icons.location_on),
                    label: const Text('Track Chef Location'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChat,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Chat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Review button for completed bookings
              if (status == 'completed' && booking['reviewed'] != true && onReview != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onReview,
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Leave a Review'),
                  ),
                ),
              ],

              // Rebook button for completed bookings
              if (status == 'completed') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onRebook,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Book Again'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Helper to get location string from booking data
  /// Handles GeoPoint, Map, or String types
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

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: Colors.grey[700])),
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
        text = 'Accepted';
        icon = Icons.check_circle;
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        icon = Icons.done_all;
        break;
      case 'rejected':
        color = Colors.orange;
        text = 'Rejected';
        icon = Icons.cancel;
        break;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_chef':
        color = Colors.red;
        text = 'Cancelled';
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
}

/// Pending Request Card - Shows order waiting for chef response
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
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Pending Status Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hourglass_top, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⏳ Waiting for Chef Response',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      Text(
                        'Sent ${_getTimeAgo(request['createdAt'])}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                // Animated waiting indicator
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
              ],
            ),
          ),

          // Request Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Chef Info
                Row(
                  children: [
                    CachedChefAvatar(
                      imageUrl: request['chefImage'],
                      name: request['chefName'],
                      radius: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request['chefName'] ?? 'Chef',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            request['serviceType'] == 'event'
                                ? 'Event Catering'
                                : 'Home Cooking',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Details Grid
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(Icons.calendar_today, 'Date', request['date'] ?? ''),
                      const SizedBox(height: 8),
                      _buildDetailRow(Icons.access_time, 'Time', request['time'] ?? ''),
                      const SizedBox(height: 8),
                      _buildDetailRow(Icons.location_on, 'Location', _getLocationStr(request)),
                      const SizedBox(height: 8),
                      _buildDetailRow(Icons.people, 'Guests', '${request['guestCount'] ?? 0} people'),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Price Offered
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Price Offer',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'Rs. ${request['offeredPrice'] ?? 0}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                // Note if exists
                if (request['note'] != null && request['note'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request['note'],
                            style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Cancel Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text('Cancel Request', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
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
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Helper to get location string from request data
  String _getLocationStr(Map<String, dynamic> request) {
    // First check if there's an address field
    if (request['address'] != null && request['address'].toString().isNotEmpty) {
      return request['address'].toString();
    }

    final location = request['location'];
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

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'just now';

    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      try {
        dateTime = timestamp.toDate();
      } catch (e) {
        return 'just now';
      }
    }

    final difference = DateTime.now().difference(dateTime);

    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    return '${difference.inDays} days ago';
  }
}

/// Countdown Timer Widget - Only rebuilds the timer text, not the entire card
class _CountdownTimer extends StatefulWidget {
  final DateTime expiresAt;
  final String requestId;
  final Function(bool isExpired, bool isExpiringSoon)? onStatusChange;

  const _CountdownTimer({
    required this.expiresAt,
    required this.requestId,
    this.onStatusChange,
  });

  @override
  State<_CountdownTimer> createState() => _CountdownTimerState();
}

class _CountdownTimerState extends State<_CountdownTimer> {
  Timer? _timer;
  Duration _remainingTime = Duration.zero;
  bool _hasExpired = false;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.expiresAt.difference(DateTime.now());
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (mounted) {
        final newRemainingTime = widget.expiresAt.difference(DateTime.now());

        // Only call setState for this small widget
        setState(() {
          _remainingTime = newRemainingTime;
        });

        // Notify parent about status change (expired/expiring soon)
        final isExpired = newRemainingTime.isNegative;
        final isExpiringSoon = newRemainingTime.inMinutes < 5 && !isExpired;
        widget.onStatusChange?.call(isExpired, isExpiringSoon);

        // If expired, update Firestore (only once)
        if (isExpired && !_hasExpired) {
          _hasExpired = true;
          await DealNegotiationService.expireRequest(widget.requestId);
        }
      }
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'Expired';

    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;

    if (mins > 0) {
      return '${mins}m ${secs}s';
    }
    return '${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    final isExpiringSoon = _remainingTime.inMinutes < 5 && !_remainingTime.isNegative;
    final isExpired = _remainingTime.isNegative;

    if (isExpired) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer,
              size: 14,
              color: isExpiringSoon ? Colors.red : Colors.deepPurple,
            ),
            const SizedBox(width: 4),
            Text(
              _formatDuration(_remainingTime),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isExpiringSoon ? Colors.red : Colors.deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Broadcast Request Card - Shows InDrive-style broadcast request with timer
class _BroadcastRequestCard extends StatefulWidget {
  final CookingRequest request;
  final VoidCallback? onViewOffers;
  final VoidCallback? onCancel;

  const _BroadcastRequestCard({
    required this.request,
    this.onViewOffers,
    this.onCancel,
  });

  @override
  State<_BroadcastRequestCard> createState() => _BroadcastRequestCardState();
}

class _BroadcastRequestCardState extends State<_BroadcastRequestCard> {
  bool _isExpired = false;
  bool _isExpiringSoon = false;

  @override
  void initState() {
    super.initState();
    final remaining = widget.request.remainingTime;
    _isExpired = remaining.isNegative;
    _isExpiringSoon = remaining.inMinutes < 5 && !_isExpired;
  }

  void _onTimerStatusChange(bool isExpired, bool isExpiringSoon) {
    // Only rebuild if status actually changed
    if (_isExpired != isExpired || _isExpiringSoon != isExpiringSoon) {
      setState(() {
        _isExpired = isExpired;
        _isExpiringSoon = isExpiringSoon;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Header with timer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isExpired
                    ? [Colors.grey.shade400, Colors.grey.shade500]
                    : _isExpiringSoon
                        ? [Colors.red.shade400, Colors.red.shade600]
                        : [Colors.deepPurple.shade400, Colors.deepPurple.shade600],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
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
                    children: [
                      Text(
                        _isExpired ? 'Request Expired' : 'Broadcast Request',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _isExpired
                            ? 'This request has expired'
                            : 'Waiting for chef offers',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
                // Timer - Using separate widget to prevent blinking
                _CountdownTimer(
                  expiresAt: widget.request.expiresAt,
                  requestId: widget.request.id,
                  onStatusChange: _onTimerStatusChange,
                ),
              ],
            ),
          ),

          // Request Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Service Type Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.request.serviceType == 'event' ? '🎉 Event Catering' : '🍳 Home Cooking',
                        style: TextStyle(
                          color: Colors.deepPurple.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Rs. ${widget.request.offeredPrice}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Details
                _buildDetailRow(Icons.calendar_today, 'Date', widget.request.date),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.access_time, 'Time', widget.request.time),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.location_on, 'Location', widget.request.address),
                const SizedBox(height: 8),
                _buildDetailRow(Icons.people, 'Guests', '${widget.request.guestCount} people'),

                // Note if exists
                if (widget.request.note != null && widget.request.note!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.request.note!,
                            style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Action Buttons
                if (!_isExpired) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onViewOffers,
                      icon: const Icon(Icons.visibility),
                      label: const Text('View Chef Offers'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: Text(
                      _isExpired ? 'Remove' : 'Cancel Request',
                      style: const TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
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
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

