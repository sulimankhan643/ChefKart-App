import 'package:flutter/material.dart';
import '../models/chef.dart';
import '../services/booking_request_service.dart';
import '../services/verification_service.dart';
import '../widgets/cached_chef_image.dart';
import 'cnic_verification_screen.dart';

/// Customer sends booking request to chef (InDrive Style)
class SendBookingRequestScreen extends StatefulWidget {
  final Chef chef;
  final VoidCallback onBack;
  final Function(String requestId) onRequestSent;

  const SendBookingRequestScreen({
    super.key,
    required this.chef,
    required this.onBack,
    required this.onRequestSent,
  });

  @override
  State<SendBookingRequestScreen> createState() => _SendBookingRequestScreenState();
}

class _SendBookingRequestScreenState extends State<SendBookingRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  String _serviceType = 'one-time';
  String _selectedDate = '';
  String _selectedTime = '';
  String _location = '';
  String _address = '';
  int _guestCount = 4;
  int _offeredPrice = 0;
  String _note = '';

  bool _isLoading = false;
  bool _hasPendingRequest = false;
  // Pre-fetched verification status for faster order placement
  Map<String, dynamic>? _cachedVerificationStatus;

  @override
  void initState() {
    super.initState();
    _offeredPrice = widget.chef.startingPrice;
    _checkPendingRequest();
    _prefetchVerificationStatus();
  }

  Future<void> _prefetchVerificationStatus() async {
    _cachedVerificationStatus = await VerificationService.getFullVerificationStatus();
  }

  Future<void> _checkPendingRequest() async {
    final hasPending = await BookingRequestService.hasPendingRequestToChef(widget.chef.uid);
    if (mounted) {
      setState(() => _hasPendingRequest = hasPending);
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );

    if (date != null) {
      setState(() {
        _selectedDate = '${date.day}/${date.month}/${date.year}';
      });
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );

    if (time != null && mounted) {
      setState(() {
        _selectedTime = time.format(context);
      });
    }
  }

  Future<void> _sendRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate.isEmpty || _selectedTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date and time')),
      );
      return;
    }

    // Use pre-fetched verification status (refresh if not yet loaded)
    final verificationStatus = _cachedVerificationStatus ??
        await VerificationService.getFullVerificationStatus();
    if (verificationStatus['isVerified'] != true) {
      if (mounted) {
        _showVerificationRequiredDialog();
      }
      return;
    }

    setState(() => _isLoading = true);

    final requestId = await BookingRequestService.sendRequest(
      chefId: widget.chef.uid,
      serviceType: _serviceType,
      date: _selectedDate,
      time: _selectedTime,
      location: _location,
      address: _address,
      guestCount: _guestCount,
      offeredPrice: _offeredPrice,
      note: _note,
    );

    setState(() => _isLoading = false);

    if (requestId != null) {

      widget.onRequestSent(requestId);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. Please try again.'),
            backgroundColor: Colors.red,
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
          'Please verify your CNIC before placing an order. This helps ensure safety for both customers and chefs.',
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
                  builder: (_) => CnicVerificationScreen(
                    onVerificationSubmitted: () {
                      // Refresh after verification
                    },
                  ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Send Booking Request'),
        elevation: 0,
      ),
      body: _hasPendingRequest
          ? _buildPendingRequestMessage()
          : _buildRequestForm(),
      bottomNavigationBar: _hasPendingRequest
          ? null
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendRequest,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Send Request • Rs. $_offeredPrice',
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ),
    );
  }

  Widget _buildPendingRequestMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pending_actions, size: 64, color: Colors.orange[400]),
            const SizedBox(height: 16),
            const Text(
              'Request Already Pending',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You already have a pending request to ${widget.chef.name}. Please wait for their response.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: widget.onBack,
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestForm() {
    return SingleChildScrollView(
      child: Column(
        children: [

          // Chef Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
            child: Row(
              children: [
                CachedChefAvatar(
                  imageUrl: widget.chef.image,
                  name: widget.chef.name,
                  radius: 30,
                  showVerifiedBadge: true,
                  isVerified: widget.chef.isVerified,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.chef.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text('${widget.chef.rating}', style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${widget.chef.reviewCount} reviews)',
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.chef.cuisines.join(', '),
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Form
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Type
                  const Text(
                    'Service Type',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildServiceTypeSelector(),

                  const SizedBox(height: 24),

                  // Date & Time
                  const Text(
                    'Date & Time',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDateTimeSelector(
                          icon: Icons.calendar_today,
                          label: _selectedDate.isEmpty ? 'Select Date' : _selectedDate,
                          onTap: _selectDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDateTimeSelector(
                          icon: Icons.access_time,
                          label: _selectedTime.isEmpty ? 'Select Time' : _selectedTime,
                          onTap: _selectTime,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Location
                  const Text(
                    'Location',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'City (e.g., Karachi, Lahore)',
                      prefixIcon: const Icon(Icons.location_city),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                    onChanged: (v) => _location = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Full Address',
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 2,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                    onChanged: (v) => _address = v,
                  ),

                  const SizedBox(height: 24),

                  // Guest Count
                  const Text(
                    'Number of Guests',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildGuestCountSelector(),

                  const SizedBox(height: 24),

                  // Price Offer
                  const Text(
                    'Your Price Offer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildPriceOfferSection(),

                  const SizedBox(height: 24),

                  // Additional Notes
                  const Text(
                    'Additional Notes (Optional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: InputDecoration(
                      hintText: 'Any special requests, dietary restrictions, etc.',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 3,
                    onChanged: (v) => _note = v,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTypeSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildServiceTypeOption(
            'one-time',
            'One-Time',
            Icons.restaurant,
            'Single cooking session',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildServiceTypeOption(
            'event',
            'Event',
            Icons.celebration,
            'Party or gathering',
          ),
        ),
      ],
    );
  }

  Widget _buildServiceTypeOption(String value, String title, IconData icon, String subtitle) {
    final isSelected = _serviceType == value;
    return InkWell(
      onTap: () => setState(() => _serviceType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : Colors.black,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeSelector({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestCountSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.people),
              const SizedBox(width: 12),
              Text('$_guestCount guests'),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _guestCount > 1
                    ? () => setState(() => _guestCount--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_guestCount',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: _guestCount < 50
                    ? () => setState(() => _guestCount++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceOfferSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chef\'s Starting Rate',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    'Rs. ${widget.chef.startingPrice}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Negotiable',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Price Input Box
          Text(
            'Enter Your Price Offer (Rs.)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _offeredPrice.toString(),
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
            decoration: InputDecoration(
              prefixText: 'Rs. ',
              prefixStyle: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.green.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
              ),
              hintText: 'Enter price',
              hintStyle: TextStyle(
                fontSize: 18,
                color: Colors.grey[400],
                fontWeight: FontWeight.normal,
              ),
            ),
            onChanged: (value) {
              final price = int.tryParse(value);
              if (price != null && price > 0) {
                setState(() => _offeredPrice = price);
              }
            },
          ),

          const SizedBox(height: 16),

          // Quick Price Buttons
          Text(
            'Quick Select:',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickPriceButton(widget.chef.startingPrice, 'Starting'),
              _buildQuickPriceButton((widget.chef.startingPrice * 1.2).round(), '+20%'),
              _buildQuickPriceButton((widget.chef.startingPrice * 1.5).round(), '+50%'),
              _buildQuickPriceButton((widget.chef.startingPrice * 2).round(), 'Double'),
            ],
          ),

          const SizedBox(height: 16),

          // Slider for fine-tuning
          Slider(
            value: _offeredPrice.toDouble().clamp(
              (widget.chef.startingPrice * 0.5).toDouble(),
              (widget.chef.startingPrice * 3).toDouble(),
            ),
            min: (widget.chef.startingPrice * 0.5).toDouble(),
            max: (widget.chef.startingPrice * 3).toDouble(),
            divisions: 50,
            label: 'Rs. $_offeredPrice',
            activeColor: Theme.of(context).primaryColor,
            onChanged: (v) => setState(() => _offeredPrice = v.round()),
          ),

          // Price comparison hint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _offeredPrice >= widget.chef.startingPrice
                        ? '✓ Good offer! Chef is likely to accept.'
                        : '⚠ Below starting rate. Chef may negotiate.',
                    style: TextStyle(
                      color: _offeredPrice >= widget.chef.startingPrice
                          ? Colors.green[700]
                          : Colors.orange[700],
                      fontSize: 12,
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

  Widget _buildQuickPriceButton(int price, String label) {
    final isSelected = _offeredPrice == price;
    return InkWell(
      onTap: () => setState(() => _offeredPrice = price),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
          ),
        ),
        child: Column(
          children: [
            Text(
              'Rs. $price',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.black,
                fontSize: 12,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white70 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

