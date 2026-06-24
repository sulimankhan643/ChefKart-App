import 'package:flutter/material.dart';
import '../services/booking_request_service.dart';
import '../widgets/cached_chef_image.dart';

/// Detailed view of a single booking
class BookingDetailsScreen extends StatelessWidget {
  final String bookingId;
  final bool isChef; // true if viewer is chef, false if customer
  final VoidCallback onBack;
  final VoidCallback? onChat;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    required this.isChef,
    required this.onBack,
    this.onChat,
    this.onCancel,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: const Text('Booking Details'),
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: BookingRequestService.streamBooking(bookingId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final booking = snapshot.data;
          if (booking == null) {
            return _buildNotFound();
          }

          return _buildContent(context, booking);
        },
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Booking not found'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onBack, child: const Text('Go Back')),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, dynamic> booking) {
    final status = booking['status'] as String? ?? 'confirmed';
    final isConfirmed = status == 'confirmed';

    return SingleChildScrollView(
      child: Column(
        children: [
          // Status Banner
          _buildStatusBanner(status),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Person Card (chef or customer based on viewer)
                _buildPersonCard(context, booking),

                const SizedBox(height: 24),

                // Service Details
                _buildSectionTitle('Service Details'),
                const SizedBox(height: 12),
                _buildDetailsCard(booking),

                const SizedBox(height: 24),

                // Location
                _buildSectionTitle('Location'),
                const SizedBox(height: 12),
                _buildLocationCard(booking),

                const SizedBox(height: 24),

                // Price
                _buildSectionTitle('Payment'),
                const SizedBox(height: 12),
                _buildPriceCard(booking),

                // Notes
                if (booking['note'] != null && (booking['note'] as String).isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Special Notes'),
                  const SizedBox(height: 12),
                  _buildNotesCard(booking['note']),
                ],

                const SizedBox(height: 32),

                // Action Buttons
                if (isConfirmed) _buildActionButtons(context, booking),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(String status) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        text = 'Booking Confirmed';
        icon = Icons.check_circle;
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Service Completed';
        icon = Icons.done_all;
        break;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_chef':
        color = Colors.red;
        text = 'Booking Cancelled';
        icon = Icons.cancel;
        break;
      default:
        color = Colors.grey;
        text = status;
        icon = Icons.info;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      color: color.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonCard(BuildContext context, Map<String, dynamic> booking) {
    final name = isChef
        ? booking['customerName'] ?? 'Customer'
        : booking['chefName'] ?? 'Chef';
    final image = isChef
        ? booking['customerImage']
        : booking['chefImage'];
    final label = isChef ? 'Customer' : 'Your Chef';
    final phone = isChef ? booking['customerPhone'] : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CachedChefAvatar(
              imageUrl: image,
              name: name,
              radius: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (phone != null && phone.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            if (onChat != null)
              IconButton(
                onPressed: onChat,
                icon: Icon(
                  Icons.chat_bubble_outline,
                  color: Theme.of(context).primaryColor,
                ),
              ),
          ],
        ),
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

  Widget _buildDetailsCard(Map<String, dynamic> booking) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDetailRow(
              Icons.restaurant_menu,
              'Service Type',
              booking['serviceType'] == 'event'
                  ? 'Event Catering'
                  : 'Home Cooking',
            ),
            const Divider(height: 24),
            _buildDetailRow(
              Icons.calendar_today,
              'Date',
              booking['date'] ?? '-',
            ),
            const Divider(height: 24),
            _buildDetailRow(
              Icons.access_time,
              'Time',
              booking['time'] ?? '-',
            ),
            const Divider(height: 24),
            _buildDetailRow(
              Icons.people,
              'Guests',
              '${booking['guestCount'] ?? 0} people',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(Map<String, dynamic> booking) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.red[400]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking['location'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (booking['address'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          booking['address'],
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Map placeholder
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.map, size: 32, color: Colors.grey[400]),
                    const SizedBox(height: 8),
                    Text(
                      'Map View',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceCard(Map<String, dynamic> booking) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isChef ? 'Your Earnings' : 'Total Amount',
              style: const TextStyle(fontSize: 16),
            ),
            Text(
              'Rs. ${booking['price'] ?? 0}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(String note) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.note, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(note),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.grey[600])),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Map<String, dynamic> booking) {
    return Column(
      children: [
        // Chat button
        if (onChat != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(isChef ? 'Chat with Customer' : 'Chat with Chef'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

        const SizedBox(height: 12),

        // Complete button (chef only)
        if (isChef && onComplete != null)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onComplete,
              icon: const Icon(Icons.check),
              label: const Text('Mark as Completed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),

        const SizedBox(height: 12),

        // Cancel button
        if (onCancel != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCancel,
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              label: const Text(
                'Cancel Booking',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
      ],
    );
  }
}

