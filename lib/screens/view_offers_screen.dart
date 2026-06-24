import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cooking_request.dart';
import '../models/chef_offer.dart';
import '../services/deal_negotiation_service.dart';
import '../widgets/cached_chef_image.dart';

/// Customer views their broadcast request and incoming chef offers (InDrive style)
class ViewOffersScreen extends StatefulWidget {
  final String requestId;
  final VoidCallback onBack;
  final VoidCallback onConfirmed;
  final VoidCallback onExpired;

  const ViewOffersScreen({
    super.key,
    required this.requestId,
    required this.onBack,
    required this.onConfirmed,
    required this.onExpired,
  });

  @override
  State<ViewOffersScreen> createState() => _ViewOffersScreenState();
}

class _ViewOffersScreenState extends State<ViewOffersScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isCancelling = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    debugPrint('ViewOffersScreen: Init with requestId: ${widget.requestId}');
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
        content: const Text(
          'Are you sure you want to cancel this request? All pending offers will be discarded.',
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
      setState(() => _isCancelling = true);
      final success = await DealNegotiationService.cancelRequest(widget.requestId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request cancelled')),
          );
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

  Future<void> _confirmOffer(ChefOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Chef?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm ${offer.chefName} for Rs. ${offer.offeredPrice}?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.chat, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chat will be enabled after confirmation',
                      style: TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ),
                ],
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await DealNegotiationService.confirmChefOffer(offer.id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${offer.chefName} confirmed! You can now chat.'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onConfirmed();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to confirm. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _rejectOffer(ChefOffer offer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Offer?'),
        content: Text('Reject offer from ${offer.chefName}?'),
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
      await DealNegotiationService.rejectChefOffer(offer.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Chef Offers'),
        actions: [
          if (_isCancelling)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _cancelRequest,
              icon: const Icon(Icons.close, color: Colors.red),
              label: const Text('Cancel', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: StreamBuilder<CookingRequest?>(
        stream: DealNegotiationService.streamRequest(widget.requestId),
        builder: (context, requestSnapshot) {
          // Show loading while waiting
          if (requestSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your request...'),
                ],
              ),
            );
          }

          // Handle errors
          if (requestSnapshot.hasError) {
            debugPrint('ViewOffersScreen error: ${requestSnapshot.error}');
            return _buildErrorState('Error loading request: ${requestSnapshot.error}');
          }

          final request = requestSnapshot.data;

          // Request not found - retry a few times as Firestore may have latency
          if (request == null) {
            debugPrint('ViewOffersScreen: Request ${widget.requestId} not found (retry $_retryCount)');

            if (_retryCount < _maxRetries) {
              // Schedule a retry
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() => _retryCount++);
                }
              });

              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading request...'),
                    SizedBox(height: 8),
                    Text(
                      'Please wait',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              );
            }

            return _buildErrorState('Request not found. It may have been cancelled or expired.');
          }

          // Reset retry count when request is found
          if (_retryCount > 0) {
            _retryCount = 0;
          }

          debugPrint('ViewOffersScreen: Request found - status: ${request.status.name}');

          // Handle confirmed status - navigate to success
          if (request.isConfirmed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onConfirmed();
            });
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 64),
                  SizedBox(height: 16),
                  Text('Chef Confirmed!'),
                ],
              ),
            );
          }

          // Handle cancelled/expired - but only if status is explicitly set
          if (request.isCancelled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onExpired();
            });
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel, color: Colors.orange, size: 64),
                  SizedBox(height: 16),
                  Text('Request Cancelled'),
                ],
              ),
            );
          }

          if (request.isExpired) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onExpired();
            });
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer_off, color: Colors.orange, size: 64),
                  SizedBox(height: 16),
                  Text('Request Expired'),
                ],
              ),
            );
          }

          // Start timer if not already started
          // Timer is now handled by _OfferTimerBanner widget itself

          return Column(
            children: [
              // Request Summary Card
              _buildRequestSummary(request),

              // Timer Banner - uses its own state to prevent blinking
              _OfferTimerBanner(
                expiresAt: request.expiresAt,
                requestId: widget.requestId,
                onExpired: widget.onExpired,
              ),

              // Offers List
              Expanded(
                child: StreamBuilder<List<ChefOffer>>(
                  stream: DealNegotiationService.streamOffersForRequest(widget.requestId),
                  builder: (context, offersSnapshot) {
                    final offers = offersSnapshot.data ?? [];
                    final pendingOffers = offers.where((o) => o.isPending).toList();

                    if (pendingOffers.isEmpty) {
                      return _buildWaitingForOffers();
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: pendingOffers.length,
                      itemBuilder: (context, index) {
                        return _buildOfferCard(pendingOffers[index], request.offeredPrice);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRequestSummary(CookingRequest request) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: Colors.deepPurple.shade400),
              const SizedBox(width: 8),
              const Text(
                'Your Request',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(Icons.calendar_today, request.date),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.access_time, request.time),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.people, '${request.guestCount} guests'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your Price: ',
                  style: TextStyle(color: Colors.deepPurple.shade600),
                ),
                Text(
                  'Rs. ${request.offeredPrice}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.deepPurple.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }


  Widget _buildWaitingForOffers() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.broadcast_on_home,
                size: 48,
                color: Colors.deepPurple.shade400,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Broadcasting to Nearby Chefs...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Waiting for chefs to send their offers',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(ChefOffer offer, int originalPrice) {
    final isCounterOffer = offer.isCounterOffer;
    final priceDiff = offer.offeredPrice - originalPrice;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCounterOffer
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          // Chef Info Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isCounterOffer
                  ? Colors.orange.withValues(alpha: 0.05)
                  : Colors.green.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                // Chef Image
                ClipOval(
                  child: offer.chefImage != null
                      ? CachedChefImage(
                          imageUrl: offer.chefImage!,
                          width: 56,
                          height: 56,
                        )
                      : Container(
                          width: 56,
                          height: 56,
                          color: Colors.grey[200],
                          child: const Icon(Icons.person, color: Colors.grey),
                        ),
                ),
                const SizedBox(width: 12),
                // Chef Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.chefName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          Text(
                            ' ${offer.chefRating.toStringAsFixed(1)} (${offer.chefReviewCount})',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                          ),
                          if (offer.chefDistanceKm != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.location_on, color: Colors.grey[400], size: 16),
                            Text(
                              ' ${offer.chefDistanceKm!.toStringAsFixed(1)} km',
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Offer Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCounterOffer ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isCounterOffer ? 'Counter' : 'Accept',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Cuisines
          if (offer.chefCuisines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: offer.chefCuisines.take(4).map((cuisine) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      cuisine,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  );
                }).toList(),
              ),
            ),

          // Price Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offered Price',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Rs. ${offer.offeredPrice}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              color: isCounterOffer
                                  ? Colors.orange.shade800
                                  : Colors.green.shade800,
                            ),
                          ),
                          if (priceDiff != 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: priceDiff > 0
                                    ? Colors.red.withValues(alpha: 0.1)
                                    : Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                priceDiff > 0 ? '+$priceDiff' : '$priceDiff',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: priceDiff > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Chef's Message
          if (offer.message != null && offer.message!.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.message, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      offer.message!,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectOffer(offer),
                    icon: const Icon(Icons.close),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmOffer(offer),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirm Chef'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info about chat
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade400),
                const SizedBox(width: 8),
                Text(
                  'Chat enabled only after confirmation',
                  style: TextStyle(color: Colors.blue.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(message),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onBack,
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }
}

/// Timer Banner Widget - Handles its own state to prevent parent rebuild blinking
class _OfferTimerBanner extends StatefulWidget {
  final DateTime expiresAt;
  final String requestId;
  final VoidCallback onExpired;

  const _OfferTimerBanner({
    required this.expiresAt,
    required this.requestId,
    required this.onExpired,
  });

  @override
  State<_OfferTimerBanner> createState() => _OfferTimerBannerState();
}

class _OfferTimerBannerState extends State<_OfferTimerBanner> {
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
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (mounted) {
        final newRemainingTime = widget.expiresAt.difference(DateTime.now());

        setState(() {
          _remainingTime = newRemainingTime;
        });

        if (newRemainingTime.isNegative && !_hasExpired) {
          _hasExpired = true;
          timer.cancel();
          debugPrint('OfferTimerBanner: Timer expired, expiring request ${widget.requestId}');
          await DealNegotiationService.expireRequest(widget.requestId);
          if (mounted) {
            widget.onExpired();
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remainingTime.inMinutes;
    final seconds = _remainingTime.inSeconds % 60;
    final isUrgent = _remainingTime.inMinutes < 5 && !_remainingTime.isNegative;
    final isExpired = _remainingTime.isNegative;

    if (isExpired) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_off, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Request expired',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUrgent ? Colors.red.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUrgent ? Colors.red.shade200 : Colors.orange.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timer,
              color: isUrgent ? Colors.red : Colors.orange.shade700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Request expires in:',
                style: TextStyle(
                  color: isUrgent ? Colors.red.shade700 : Colors.orange.shade800,
                ),
              ),
            ),
            Text(
              '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isUrgent ? Colors.red : Colors.orange.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
