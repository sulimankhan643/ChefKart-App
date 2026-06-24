import 'package:flutter/material.dart';
import '../models/booking_request.dart';
import '../services/booking_request_service.dart';
import '../widgets/cached_chef_image.dart';

/// Screen shown to customer after sending request - waits for chef response
class RequestWaitingScreen extends StatefulWidget {
  final String requestId;
  final VoidCallback onBack;
  final VoidCallback onAccepted;
  final VoidCallback onRejected;

  const RequestWaitingScreen({
    super.key,
    required this.requestId,
    required this.onBack,
    required this.onAccepted,
    required this.onRejected,
  });

  @override
  State<RequestWaitingScreen> createState() => _RequestWaitingScreenState();
}

class _RequestWaitingScreenState extends State<RequestWaitingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _cancelRequest() async {
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
      setState(() => _isCancelling = true);
      final success = await BookingRequestService.cancelRequest(widget.requestId);

      if (mounted) {
        if (success) {
          widget.onBack();
        } else {
          setState(() => _isCancelling = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to cancel request'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Request Sent'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<BookingRequest?>(
        stream: BookingRequestService.streamRequest(widget.requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final request = snapshot.data;

          if (request == null) {
            return _buildErrorState();
          }

          // Check status changes
          if (request.isAccepted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onAccepted();
            });
          } else if (request.isRejected || request.isCancelledByChef) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onRejected();
            });
          }

          return _buildWaitingContent(request);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Request not found'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onBack,
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingContent(BookingRequest request) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Animated waiting indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: CachedChefAvatar(
                          imageUrl: request.chefImage,
                          name: request.chefName,
                          radius: 30,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 24),

          const Text(
            'Waiting for Response',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Your request has been sent to ${request.chefName}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),

          const SizedBox(height: 32),

          // Request Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                const Text(
                  'Request Summary',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSummaryRow('Chef', request.chefName),
                _buildSummaryRow('Date', request.date),
                _buildSummaryRow('Time', request.time),
                _buildSummaryRow('Location', request.location),
                _buildSummaryRow('Guests', '${request.guestCount} people'),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Offer',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Rs. ${request.offeredPrice}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Status indicator
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.orange.shade700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'The chef will respond to your request shortly. You will be notified once they accept or decline.',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Cancel button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isCancelling ? null : _cancelRequest,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCancelling
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Cancel Request',
                      style: TextStyle(color: Colors.red),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Screen shown when chef accepts the request
class RequestAcceptedScreen extends StatelessWidget {
  final String chefName;
  final VoidCallback onContinue;

  const RequestAcceptedScreen({
    super.key,
    required this.chefName,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  size: 64,
                  color: Colors.green.shade600,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Booking Confirmed! 🎉',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$chefName has accepted your booking request!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('View Booking Details'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen shown when chef rejects the request
class RequestRejectedScreen extends StatelessWidget {
  final String chefName;
  final VoidCallback onTryAnother;
  final VoidCallback onGoBack;

  const RequestRejectedScreen({
    super.key,
    required this.chefName,
    required this.onTryAnother,
    required this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule,
                  size: 64,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Chef Unavailable',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$chefName is currently unavailable. Please try another chef.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onTryAnother,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Find Another Chef'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onGoBack,
                  child: const Text('Go Back'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

