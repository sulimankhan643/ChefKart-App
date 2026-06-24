import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/booking_request.dart';
import '../services/booking_request_service.dart';
import '../services/verification_service.dart';
import '../widgets/cached_chef_image.dart';
import 'chef_documents_screen.dart';

/// Chef's screen to view and respond to booking requests (InDrive Style)
class ChefRequestsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ChefRequestsScreen({super.key, this.onBack});

  @override
  State<ChefRequestsScreen> createState() => _ChefRequestsScreenState();
}

class _ChefRequestsScreenState extends State<ChefRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: const Text('Booking Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingRequestsTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildPendingRequestsTab() {
    final currentUser = FirebaseAuth.instance.currentUser;
    debugPrint('=== CHEF REQUESTS SCREEN ===');
    debugPrint('Current user UID: ${currentUser?.uid}');

    return StreamBuilder<List<BookingRequest>>(
      stream: BookingRequestService.getChefPendingRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          debugPrint('Error in stream: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}'),
                const SizedBox(height: 8),
                Text('Your ID: ${currentUser?.uid ?? "Not logged in"}'),
              ],
            ),
          );
        }

        final requests = snapshot.data ?? [];
        debugPrint('Received ${requests.length} requests in UI');

        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No Pending Requests',
            subtitle: 'Your ID: ${currentUser?.uid ?? "Unknown"}\nNew booking requests will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            return _InDriveRequestCard(
              request: requests[index],
              onAccept: () => _handleAccept(requests[index]),
              onReject: () => _handleReject(requests[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<List<BookingRequest>>(
      stream: BookingRequestService.getChefAllRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = (snapshot.data ?? [])
            .where((r) => r.status != 'pending')
            .toList();

        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.history,
            title: 'No History',
            subtitle: 'Your request history will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            return _RequestHistoryCard(request: requests[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _handleAccept(BookingRequest request) async {
    // Check if chef is verified before accepting
    final verificationStatus = await VerificationService.getFullVerificationStatus();
    if (!mounted) return;

    if (verificationStatus['isVerified'] != true) {
      _showVerificationRequiredDialog();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Request?'),
        content: Text(
          'Accept booking from ${request.customerName} for Rs. ${request.offeredPrice}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await BookingRequestService.acceptRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Booking accepted successfully!'
                  : 'Failed to accept. Try again.',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReject(BookingRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request?'),
        content: Text(
          'Are you sure you want to reject the request from ${request.customerName}?',
        ),
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
      final success = await BookingRequestService.rejectRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Request rejected' : 'Failed to reject. Try again.',
            ),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
      }
    }
  }

  void _showVerificationRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_user,
                color: Color(0xFFFF6B35),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Verification Required',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: const Text(
          'Please verify your CNIC before accepting booking requests. This helps ensure trust and safety for customers.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChefDocumentsScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Verify Now'),
          ),
        ],
      ),
    );
  }
}

/// InDrive-style request card with Accept/Reject buttons
class _InDriveRequestCard extends StatelessWidget {
  final BookingRequest request;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _InDriveRequestCard({
    required this.request,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Column(
        children: [
          // Header with customer info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CachedChefAvatar(
                  imageUrl: request.customerImage,
                  name: request.customerName,
                  radius: 25,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.customerName,
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
                // Time badge with expiry warning
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isAboutToExpire(request.createdAt)
                        ? Colors.red.shade100
                        : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isAboutToExpire(request.createdAt))
                        const Icon(Icons.timer_off, size: 12, color: Colors.red),
                      if (_isAboutToExpire(request.createdAt))
                        const SizedBox(width: 4),
                      Text(
                        _isAboutToExpire(request.createdAt)
                            ? 'Expires soon!'
                            : _getTimeAgo(request.createdAt),
                        style: TextStyle(
                          color: _isAboutToExpire(request.createdAt)
                              ? Colors.red.shade800
                              : Colors.orange.shade800,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
                _buildDetailRow(Icons.calendar_today, 'Date', request.date),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.access_time, 'Time', request.time),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.location_on, 'Location', request.location),
                const SizedBox(height: 12),
                _buildDetailRow(Icons.people, 'Guests', '${request.guestCount} people'),
                const SizedBox(height: 12),
                _buildDetailRow(
                  Icons.restaurant_menu,
                  'Service',
                  request.serviceType == 'event' ? 'Event Catering' : 'One-Time Service',
                ),
                if (request.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.note, 'Note', request.note),
                ],
              ],
            ),
          ),

          // Price Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Offered Price: ',
                  style: TextStyle(fontSize: 16),
                ),
                Text(
                  'Rs. ${request.offeredPrice}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons (InDrive Style)
          Container(
            padding: const EdgeInsets.all(16),
            child: _isExpired(request.createdAt)
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_off, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Request expired',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : Row(
              children: [
                // Reject Button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, color: Colors.red),
                    label: const Text(
                      'Reject',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Accept Button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ), // Row ends here
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  String _getTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Check if request is about to expire (< 5 min left)
  bool _isAboutToExpire(DateTime time) {
    final diff = DateTime.now().difference(time);
    return diff.inMinutes >= 25 && diff.inMinutes < 30;
  }

  /// Check if request is expired (> 30 min)
  bool _isExpired(DateTime time) {
    final diff = DateTime.now().difference(time);
    return diff.inMinutes >= 30;
  }
}

/// History card showing past requests
class _RequestHistoryCard extends StatelessWidget {
  final BookingRequest request;

  const _RequestHistoryCard({required this.request});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CachedChefAvatar(
          imageUrl: request.customerImage,
          name: request.customerName,
          radius: 24,
        ),
        title: Text(request.customerName),
        subtitle: Text(
          '${request.date} • Rs. ${request.offeredPrice}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: _buildStatusBadge(),
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    String text;
    IconData icon;

    switch (request.status) {
      case 'accepted':
        color = Colors.green;
        text = 'Accepted';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Rejected';
        icon = Icons.cancel;
        break;
      case 'cancelled':
        color = Colors.grey;
        text = 'Cancelled';
        icon = Icons.block;
        break;
      default:
        color = Colors.orange;
        text = 'Pending';
        icon = Icons.pending;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

