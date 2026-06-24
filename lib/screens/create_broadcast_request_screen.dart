import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/deal_negotiation_service.dart';
import '../services/verification_service.dart';
import 'cnic_verification_screen.dart';

/// Customer creates a broadcast cooking request (InDrive style)
class CreateBroadcastRequestScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(String requestId) onRequestCreated;

  const CreateBroadcastRequestScreen({
    super.key,
    required this.onBack,
    required this.onRequestCreated,
  });

  @override
  State<CreateBroadcastRequestScreen> createState() => _CreateBroadcastRequestScreenState();
}

class _CreateBroadcastRequestScreenState extends State<CreateBroadcastRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  // Form fields
  String _serviceType = 'home-cooking';
  String _selectedDate = '';
  String _selectedTime = '';
  String _address = '';
  int _guestCount = 4;
  int _offeredPrice = 1500;
  String _note = '';
  final List<String> _selectedCuisines = [];
  double _broadcastRadius = 10.0;
  int _expirationMinutes = 15;

  bool _isLoading = false;
  bool _hasActiveRequest = false;
  // Pre-fetched verification status for faster request creation
  Map<String, dynamic>? _cachedVerificationStatus;

  final List<String> _serviceTypes = [
    'home-cooking',
    'event-catering',
    'premium',
  ];

  final Map<String, String> _serviceTypeLabels = {
    'home-cooking': 'Home Cooking',
    'event-catering': 'Event/Party Catering',
    'premium': 'Premium Service',
  };

  final Map<String, IconData> _serviceTypeIcons = {
    'home-cooking': Icons.home,
    'event-catering': Icons.celebration,
    'premium': Icons.star,
  };

  final List<String> _cuisineOptions = [
    'Pakistani', 'BBQ', 'Chinese', 'Continental',
    'Italian', 'Fast Food', 'Desserts', 'Traditional',
  ];

  @override
  void initState() {
    super.initState();
    _checkActiveRequest();
    _prefetchVerificationStatus();
  }

  Future<void> _prefetchVerificationStatus() async {
    _cachedVerificationStatus = await VerificationService.getFullVerificationStatus();
  }

  Future<void> _checkActiveRequest() async {
    final hasActive = await DealNegotiationService.hasActivePendingRequest();
    if (mounted) {
      setState(() => _hasActiveRequest = hasActive);
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

  Future<void> _createRequest() async {
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
    if (!mounted) return;

    if (verificationStatus['isVerified'] != true) {
      _showVerificationRequiredDialog();
      return;
    }

    setState(() => _isLoading = true);

    // Get user's location
    GeoPoint? location;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final userData = userDoc.data();
        if (userData != null && userData['lat'] != null && userData['lng'] != null) {
          location = GeoPoint(
            userData['lat'].toDouble(),
            userData['lng'].toDouble(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }

    final requestId = await DealNegotiationService.createBroadcastRequest(
      serviceType: _serviceType,
      date: _selectedDate,
      time: _selectedTime,
      address: _address,
      guestCount: _guestCount,
      offeredPrice: _offeredPrice,
      note: _note,
      cuisinePreferences: _selectedCuisines,
      broadcastRadiusKm: _broadcastRadius,
      expirationMinutes: _expirationMinutes,
      customerLocation: location,
    );

    setState(() => _isLoading = false);

    if (requestId != null) {
      debugPrint('CreateBroadcastRequestScreen: Request created with ID: $requestId');
      debugPrint('CreateBroadcastRequestScreen: Navigating to view_offers');
      widget.onRequestCreated(requestId);
    } else {
      debugPrint('CreateBroadcastRequestScreen: Request creation FAILED');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create request. Please try again.'),
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
          'Please verify your CNIC before finding a chef. This helps ensure safety for both customers and chefs.',
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
    if (_hasActiveRequest) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('Find a Chef'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pending_actions, size: 80, color: Colors.orange[400]),
                const SizedBox(height: 24),
                const Text(
                  'You Have an Active Request',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Please wait for chef offers or cancel your existing request before creating a new one.',
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.visibility),
                  label: const Text('View Active Request'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: const Text('Find a Chef'),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade100],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.broadcast_on_home, color: Colors.deepPurple.shade700, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Broadcast Your Request',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.deepPurple.shade800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nearby chefs will see your request and send offers',
                            style: TextStyle(
                              color: Colors.deepPurple.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Service Type Selection
              _buildSectionTitle('What do you need?'),
              const SizedBox(height: 12),
              _buildServiceTypeSelector(),

              const SizedBox(height: 24),

              // Date & Time
              _buildSectionTitle('When?'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDateTimeButton(
                      icon: Icons.calendar_today,
                      label: _selectedDate.isEmpty ? 'Select Date' : _selectedDate,
                      onTap: _selectDate,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDateTimeButton(
                      icon: Icons.access_time,
                      label: _selectedTime.isEmpty ? 'Select Time' : _selectedTime,
                      onTap: _selectTime,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Guest Count
              _buildSectionTitle('Number of Guests'),
              const SizedBox(height: 12),
              _buildGuestCountSelector(),

              const SizedBox(height: 24),

              // Address
              _buildSectionTitle('Address'),
              const SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  hintText: 'Enter your full address',
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your address';
                  }
                  return null;
                },
                onChanged: (value) => _address = value,
              ),

              const SizedBox(height: 24),

              // Cuisine Preferences
              _buildSectionTitle('Cuisine Preferences (Optional)'),
              const SizedBox(height: 12),
              _buildCuisineSelector(),

              const SizedBox(height: 24),

              // Your Offered Price
              _buildSectionTitle('Your Offered Price'),
              const SizedBox(height: 8),
              Text(
                'Set the price you\'re willing to pay. Chefs can accept or counter.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 12),
              _buildPriceInput(),

              const SizedBox(height: 24),

              // Additional Note
              _buildSectionTitle('Additional Note (Optional)'),
              const SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  hintText: 'Any special requirements or dietary restrictions...',
                  prefixIcon: const Icon(Icons.note_add),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
                onChanged: (value) => _note = value,
              ),

              const SizedBox(height: 24),

              // Broadcast Settings
              _buildAdvancedSettings(),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
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
            onPressed: _isLoading ? null : _createRequest,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded),
                      SizedBox(width: 8),
                      Text(
                        'Broadcast to Chefs',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
          ),
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

  Widget _buildServiceTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: RadioGroup<String>(
        groupValue: _serviceType,
        onChanged: (value) {
          if (value != null) setState(() => _serviceType = value);
        },
        child: Column(
        children: _serviceTypes.map((type) {
          final isSelected = _serviceType == type;
          return InkWell(
            onTap: () => setState(() => _serviceType = type),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.deepPurple.withValues(alpha: 0.1) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.deepPurple.withValues(alpha: 0.2)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _serviceTypeIcons[type],
                      color: isSelected ? Colors.deepPurple : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _serviceTypeLabels[type] ?? type,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.deepPurple : Colors.black87,
                      ),
                    ),
                  ),
                  Radio<String>(
                    value: type,
                    activeColor: Colors.deepPurple,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      ),
    );
  }

  Widget _buildDateTimeButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.deepPurple, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: label.contains('Select') ? Colors.grey : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestCountSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.people, color: Colors.deepPurple),
              const SizedBox(width: 12),
              Text('$_guestCount guests', style: const TextStyle(fontSize: 16)),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: _guestCount > 1
                    ? () => setState(() => _guestCount--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.deepPurple,
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
                color: Colors.deepPurple,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCuisineSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _cuisineOptions.map((cuisine) {
        final isSelected = _selectedCuisines.contains(cuisine);
        return FilterChip(
          label: Text(cuisine),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedCuisines.add(cuisine);
              } else {
                _selectedCuisines.remove(cuisine);
              }
            });
          },
          selectedColor: Colors.deepPurple.withValues(alpha: 0.2),
          checkmarkColor: Colors.deepPurple,
        );
      }).toList(),
    );
  }

  Widget _buildPriceInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
        color: Colors.deepPurple.withValues(alpha: 0.05),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Rs. ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade800,
                ),
              ),
              SizedBox(
                width: 120,
                child: TextFormField(
                  initialValue: _offeredPrice.toString(),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade800,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      setState(() => _offeredPrice = parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Quick price buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [1000, 1500, 2000, 2500, 3000].map((price) {
              return ActionChip(
                label: Text('Rs. $price'),
                onPressed: () => setState(() => _offeredPrice = price),
                backgroundColor: _offeredPrice == price
                    ? Colors.deepPurple
                    : Colors.grey.shade100,
                labelStyle: TextStyle(
                  color: _offeredPrice == price ? Colors.white : Colors.black87,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSettings() {
    return ExpansionTile(
      title: const Text('Advanced Settings'),
      leading: const Icon(Icons.settings),
      children: [
        ListTile(
          title: const Text('Search Radius'),
          subtitle: Text('${_broadcastRadius.toInt()} km'),
          trailing: SizedBox(
            width: 150,
            child: Slider(
              value: _broadcastRadius,
              min: 5,
              max: 50,
              divisions: 9,
              onChanged: (value) => setState(() => _broadcastRadius = value),
              activeColor: Colors.deepPurple,
            ),
          ),
        ),
        ListTile(
          title: const Text('Request Expires In'),
          subtitle: Text('$_expirationMinutes minutes'),
          trailing: DropdownButton<int>(
            value: _expirationMinutes,
            items: [1, 5, 10, 15, 30, 45, 60].map((mins) {
              return DropdownMenuItem(
                value: mins,
                child: Text('$mins min'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _expirationMinutes = value);
              }
            },
          ),
        ),
      ],
    );
  }
}

