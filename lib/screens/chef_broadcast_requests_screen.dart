import 'dart:async';
import 'package:flutter/material.dart';
import '../models/cooking_request.dart';
import '../models/chef_offer.dart';
import '../services/deal_negotiation_service.dart';
import '../services/verification_service.dart';
import 'chef_documents_screen.dart';
import 'commission_payment_screen.dart';

/// Chef views nearby broadcast requests and sends offers (InDrive style)
class ChefBroadcastRequestsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ChefBroadcastRequestsScreen({super.key, this.onBack});

  @override
  State<ChefBroadcastRequestsScreen> createState() => _ChefBroadcastRequestsScreenState();
}

class _ChefBroadcastRequestsScreenState extends State<ChefBroadcastRequestsScreen>
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
        title: const Text('Available Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.broadcast_on_home), text: 'Nearby'),
            Tab(icon: Icon(Icons.local_offer), text: 'My Offers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _NearbyRequestsTab(),
          _MyOffersTab(),
        ],
      ),
    );
  }
}

/// Tab showing nearby broadcast requests
class _NearbyRequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CookingRequest>>(
      stream: DealNegotiationService.getChefNearbyRequests(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return _buildEmptyState(
            icon: Icons.search_off,
            title: 'No Requests Nearby',
            subtitle: 'New cooking requests will appear here',
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            // Force refresh by waiting briefly
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              return _BroadcastRequestCard(request: requests[index]);
            },
          ),
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
}

/// Card for displaying a broadcast request to chef
class _BroadcastRequestCard extends StatefulWidget {
  final CookingRequest request;

  const _BroadcastRequestCard({required this.request});

  @override
  State<_BroadcastRequestCard> createState() => _BroadcastRequestCardState();
}

class _BroadcastRequestCardState extends State<_BroadcastRequestCard> {
  bool _isLoading = false;
  bool _hasOffered = false;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _isExpired = widget.request.remainingTime.isNegative;
    _checkExistingOffer();
  }

  void _onTimerExpired() {
    if (mounted) {
      setState(() => _isExpired = true);
    }
  }

  Future<void> _checkExistingOffer() async {
    // Check if chef already has a pending offer
    final offers = await DealNegotiationService.getChefPendingOffers().first;
    final hasOffer = offers.any((o) => o.requestId == widget.request.id);
    if (mounted) {
      setState(() => _hasOffered = hasOffer);
    }
  }

  Future<void> _acceptPrice() async {
    // Check if chef is verified before sending offer
    final verificationStatus = await VerificationService.getFullVerificationStatus();
    if (mounted && verificationStatus['isVerified'] != true) {
      _showVerificationRequiredDialog();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final offerId = await DealNegotiationService.acceptCustomerPrice(widget.request.id);

      if (mounted) {
        setState(() => _isLoading = false);
        if (offerId != null) {
          setState(() => _hasOffered = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offer sent! Waiting for customer confirmation.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send offer. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on CommissionBlockedException catch (e) {
      // Commission limit reached - show popup to pay commission
      if (mounted) {
        setState(() => _isLoading = false);
        _showCommissionBlockedDialog(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show dialog when chef's orders are blocked due to commission limit
  void _showCommissionBlockedDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.block, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Order Limit Reached',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Pay your pending commission via EasyPaisa to continue accepting orders.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CommissionPaymentScreen()),
              );
            },
            icon: const Icon(Icons.payment, size: 18),
            label: const Text('Pay Commission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
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
          'Please verify your CNIC before sending offers. This helps ensure trust and safety for customers.',
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

  Future<void> _showCounterOfferDialog() async {
    // Check if chef is verified before sending counter offer
    final verificationStatus = await VerificationService.getFullVerificationStatus();
    if (mounted && verificationStatus['isVerified'] != true) {
      _showVerificationRequiredDialog();
      return;
    }

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CounterOfferBottomSheet(
        originalPrice: widget.request.offeredPrice,
        customerName: widget.request.customerName,
      ),
    );

    if (result != null && mounted) {
      setState(() => _isLoading = true);

      try {
        final offerId = await DealNegotiationService.sendCounterOffer(
          requestId: widget.request.id,
          counterPrice: result['price'],
          message: result['message'],
        );

        if (mounted) {
          setState(() => _isLoading = false);
          if (offerId != null) {
            setState(() => _hasOffered = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Counter offer sent!'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to send counter offer.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } on CommissionBlockedException catch (e) {
        // Commission limit reached - show popup to pay commission
        if (mounted) {
          setState(() => _isLoading = false);
          _showCommissionBlockedDialog(e.message);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpired) {
      return const SizedBox.shrink(); // Hide expired requests
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with timer
          _ChefRequestHeader(
            request: widget.request,
            onExpired: _onTimerExpired,
          ),

          // Request Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date, Time, Guests
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildDetailChip(Icons.calendar_today, widget.request.date),
                    _buildDetailChip(Icons.access_time, widget.request.time),
                    _buildDetailChip(Icons.people, '${widget.request.guestCount} guests'),
                  ],
                ),
                const SizedBox(height: 12),
                // Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on, color: Colors.grey.shade400, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.request.address,
                        style: TextStyle(color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Cuisine Preferences
                if (widget.request.cuisinePreferences.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.request.cuisinePreferences.map((c) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          c,
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                // Note
                if (widget.request.note != null && widget.request.note!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, color: Colors.grey.shade400, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.request.note!,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Price & Actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Customer's Offered Price
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'Customer offers: ',
                        style: TextStyle(color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'Rs. ${widget.request.offeredPrice}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action Buttons
                if (_hasOffered)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Offer sent! Waiting for customer...',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showCounterOfferDialog,
                          icon: const Icon(Icons.edit),
                          label: const Text('Counter'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _acceptPrice,
                          icon: const Icon(Icons.check),
                          label: const Text('Accept Price'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Info
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Chat enabled only after customer confirms',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for counter offer input
class _CounterOfferBottomSheet extends StatefulWidget {
  final int originalPrice;
  final String customerName;

  const _CounterOfferBottomSheet({
    required this.originalPrice,
    required this.customerName,
  });

  @override
  State<_CounterOfferBottomSheet> createState() => _CounterOfferBottomSheetState();
}

class _CounterOfferBottomSheetState extends State<_CounterOfferBottomSheet> {
  late int _counterPrice;
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _counterPrice = widget.originalPrice;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Widget _buildQuickAdjustChip(int adj) {
    final newPrice = widget.originalPrice + adj;
    return ActionChip(
      label: Text(adj > 0 ? '+$adj' : '$adj'),
      onPressed: newPrice > 0
          ? () => setState(() => _counterPrice = newPrice)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final priceDiff = _counterPrice - widget.originalPrice;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Send Counter Offer',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Customer ${widget.customerName} offered Rs. ${widget.originalPrice}',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),

          // Price Input
          const Text('Your Price', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
              color: Colors.orange.withValues(alpha: 0.05),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _counterPrice > 100
                          ? () => setState(() => _counterPrice -= 100)
                          : null,
                      icon: const Icon(Icons.remove_circle),
                      iconSize: 36,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        Text(
                          'Rs. $_counterPrice',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        if (priceDiff != 0)
                          Text(
                            priceDiff > 0 ? '+$priceDiff from offer' : '$priceDiff from offer',
                            style: TextStyle(
                              color: priceDiff > 0 ? Colors.red : Colors.green,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: () => setState(() => _counterPrice += 100),
                      icon: const Icon(Icons.add_circle),
                      iconSize: 36,
                      color: Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Quick adjustments
                Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickAdjustChip(-500),
                    _buildQuickAdjustChip(-200),
                    _buildQuickAdjustChip(200),
                    _buildQuickAdjustChip(500),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Message (Optional)
          const Text('Brief Message (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _messageController,
            maxLines: 2,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: 'e.g., I specialize in this cuisine...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  'price': _counterPrice,
                  'message': _messageController.text.trim().isEmpty
                      ? null
                      : _messageController.text.trim(),
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Send Counter Offer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Tab showing chef's sent offers
class _MyOffersTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChefOffer>>(
      stream: DealNegotiationService.getChefAllOffers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final offers = snapshot.data ?? [];

        if (offers.isEmpty) {
          return _buildEmptyState(
            icon: Icons.local_offer_outlined,
            title: 'No Offers Sent',
            subtitle: 'Your sent offers will appear here',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: offers.length,
          itemBuilder: (context, index) {
            return _OfferHistoryCard(offer: offers[index]);
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
}

/// Card showing offer history
class _OfferHistoryCard extends StatelessWidget {
  final ChefOffer offer;

  const _OfferHistoryCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (offer.status) {
      case ChefOfferStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusText = 'Waiting';
        break;
      case ChefOfferStatus.accepted:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Confirmed';
        break;
      case ChefOfferStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Not Selected';
        break;
      case ChefOfferStatus.withdrawn:
        statusColor = Colors.grey;
        statusIcon = Icons.undo;
        statusText = 'Withdrawn';
        break;
      case ChefOfferStatus.expired:
        statusColor = Colors.grey;
        statusIcon = Icons.timer_off;
        statusText = 'Expired';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(statusIcon, color: statusColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.isCounterOffer
                      ? 'Counter Offer: Rs. ${offer.offeredPrice}'
                      : 'Accepted Price: Rs. ${offer.offeredPrice}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Original: Rs. ${offer.originalPrice}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Timer-based header widget for chef request cards - prevents blinking
class _ChefRequestHeader extends StatefulWidget {
  final CookingRequest request;
  final VoidCallback onExpired;

  const _ChefRequestHeader({
    required this.request,
    required this.onExpired,
  });

  @override
  State<_ChefRequestHeader> createState() => _ChefRequestHeaderState();
}

class _ChefRequestHeaderState extends State<_ChefRequestHeader> {
  Timer? _timer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remainingTime = widget.request.expiresAt.difference(DateTime.now());
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        final newTime = widget.request.expiresAt.difference(DateTime.now());
        setState(() {
          _remainingTime = newTime;
        });

        if (newTime.isNegative) {
          timer.cancel();
          widget.onExpired();
        }
      }
    });
  }

  String _getServiceTypeLabel(String type) {
    switch (type) {
      case 'home-cooking':
        return '🍳 Home Cooking';
      case 'event':
        return '🎉 Event Catering';
      default:
        return '🍽️ Cooking Service';
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remainingTime.inMinutes;
    final seconds = _remainingTime.inSeconds % 60;
    final isUrgent = minutes < 5 && !_remainingTime.isNegative;

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isUrgent
                ? [Colors.red.shade50, Colors.red.shade100]
                : [Colors.deepPurple.shade50, Colors.deepPurple.shade100],
          ),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.person,
                color: Colors.deepPurple.shade400,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.request.customerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    _getServiceTypeLabel(widget.request.serviceType),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Timer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isUrgent ? Colors.red : Colors.deepPurple,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
