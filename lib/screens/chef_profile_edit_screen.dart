import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/cached_chef_image.dart';
import '../services/supabase_storage_service.dart';

/// Chef Profile Edit Screen with Tabs
class ChefProfileEditScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final int initialTab; // 0 = Profile, 1 = Specialties, 2 = Pricing

  const ChefProfileEditScreen({
    super.key,
    this.onBack,
    this.onSave,
    this.initialTab = 0,
  });

  @override
  State<ChefProfileEditScreen> createState() => _ChefProfileEditScreenState();
}

class _ChefProfileEditScreenState extends State<ChefProfileEditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  // Form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();
  final _priceController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();

  // Pricing controllers for each service type
  final _homeCookingPriceController = TextEditingController();
  final _eventCateringPriceController = TextEditingController();
  final _premiumServicePriceController = TextEditingController();

  String? _imageUrl;
  File? _newImage;
  Uint8List? _webImageBytes; // For web platform
  List<String> _selectedCuisines = [];
  List<String> _selectedSpecialties = [];
  bool _isAvailable = true;

  // Service availability toggles
  bool _homeCookingEnabled = true;
  bool _eventCateringEnabled = true;
  bool _premiumServiceEnabled = true;

  final List<String> _cuisineOptions = [
    'Pakistani', 'BBQ', 'Chinese', 'Continental',
    'Italian', 'Fast Food', 'Desserts', 'Traditional',
    'South Indian', 'Mughlai', 'Thai', 'Korean',
  ];

  final List<String> _specialtyOptions = [
    'Biryani', 'Karahi', 'Kebabs', 'Pulao',
    'Haleem', 'Nihari', 'Sajji', 'Tikka',
    'Chow Mein', 'Fried Rice', 'Pizza', 'Pasta',
    'Burger', 'Rolls', 'Paratha', 'Naan',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    _priceController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _homeCookingPriceController.dispose();
    _eventCateringPriceController.dispose();
    _premiumServicePriceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;

        // Get pricing data
        final pricing = data['pricing'] as Map<String, dynamic>? ?? {};

        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _emailController.text = data['email'] ?? _auth.currentUser?.email ?? '';
          _bioController.text = data['bio'] ?? data['about'] ?? '';
          _experienceController.text = data['experience'] ?? '';
          _priceController.text = (data['startingPrice'] ?? data['hourlyRate'] ?? '').toString();
          if (_priceController.text == '0') _priceController.text = '';
          _addressController.text = data['address'] ?? '';
          _cityController.text = data['city'] ?? '';
          _imageUrl = data['image'];
          _selectedCuisines = List<String>.from(data['cuisines'] ?? []);
          _selectedSpecialties = List<String>.from(data['specialties'] ?? data['dishes'] ?? []);
          _isAvailable = data['isAvailable'] ?? false;

          // Load pricing for each service
          final homeCooking = pricing['homeCooking'] as Map<String, dynamic>? ?? {};
          final eventCatering = pricing['eventCatering'] as Map<String, dynamic>? ?? {};
          final premiumService = pricing['premiumService'] as Map<String, dynamic>? ?? {};

          _homeCookingPriceController.text = (homeCooking['price'] ?? '').toString();
          if (_homeCookingPriceController.text == '0') _homeCookingPriceController.text = '';
          _homeCookingEnabled = homeCooking['enabled'] ?? true;

          _eventCateringPriceController.text = (eventCatering['price'] ?? '').toString();
          if (_eventCateringPriceController.text == '0') _eventCateringPriceController.text = '';
          _eventCateringEnabled = eventCatering['enabled'] ?? true;

          _premiumServicePriceController.text = (premiumService['price'] ?? '').toString();
          if (_premiumServicePriceController.text == '0') _premiumServicePriceController.text = '';
          _premiumServiceEnabled = premiumService['enabled'] ?? true;

          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile != null && mounted) {
        // Check if file is jpg/jpeg format
        final extension = pickedFile.path.toLowerCase().split('.').last;
        if (extension != 'jpg' && extension != 'jpeg') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a JPG/JPEG image only'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (kIsWeb) {
          // For web, read as bytes
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _webImageBytes = bytes;
            _newImage = null;
          });
        } else {
          // For mobile
          setState(() {
            _newImage = File(pickedFile.path);
            _webImageBytes = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_newImage == null && _webImageBytes == null) return _imageUrl;

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return null;

      // Use Supabase Storage Service
      final url = await SupabaseStorageService.uploadChefProfileImage(
        file: _newImage,
        bytes: _webImageBytes,
        userId: uid,
      );

      return url ?? _imageUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return _imageUrl;
    }
  }

  /// Get current location for chef profile
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Upload image if changed
      final imageUrl = await _uploadImage();

      // Get current location
      double? lat;
      double? lng;
      try {
        final position = await _getCurrentLocation();
        if (position != null) {
          lat = position.latitude;
          lng = position.longitude;
          debugPrint('Chef location updated: $lat, $lng');
        }
      } catch (e) {
        debugPrint('Could not get location: $e');
      }

      // Parse prices
      int startingPrice = 0;
      int homeCookingPrice = 0;
      int eventCateringPrice = 0;
      int premiumServicePrice = 0;

      try {
        startingPrice = int.parse(_priceController.text.trim());
      } catch (_) {}
      try {
        homeCookingPrice = int.parse(_homeCookingPriceController.text.trim());
      } catch (_) {}
      try {
        eventCateringPrice = int.parse(_eventCateringPriceController.text.trim());
      } catch (_) {}
      try {
        premiumServicePrice = int.parse(_premiumServicePriceController.text.trim());
      } catch (_) {}

      // Prepare pricing data
      final pricingData = {
        'homeCooking': {
          'price': homeCookingPrice,
          'enabled': _homeCookingEnabled,
          'name': 'Home Cooking',
          'description': 'Daily meal preparation for families',
        },
        'eventCatering': {
          'price': eventCateringPrice,
          'enabled': _eventCateringEnabled,
          'name': 'Event Catering',
          'description': 'Parties, gatherings, special occasions',
        },
        'premiumService': {
          'price': premiumServicePrice,
          'enabled': _premiumServiceEnabled,
          'name': 'Premium Services',
          'description': 'Multi-course meals, gourmet cooking',
        },
      };

      // Prepare data
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'bio': _bioController.text.trim(),
        'about': _bioController.text.trim(),
        'experience': _experienceController.text.trim(),
        'startingPrice': startingPrice,
        'hourlyRate': _priceController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'cuisines': _selectedCuisines,
        'specialties': _selectedSpecialties,
        'dishes': _selectedSpecialties,
        'isAvailable': _isAvailable,
        'pricing': pricingData,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add location if available
      if (lat != null && lng != null) {
        data['lat'] = lat;
        data['lng'] = lng;
      }

      if (imageUrl != null) {
        data['image'] = imageUrl;
      }

      await _firestore.collection('users').doc(uid).update(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSave?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
        title: const Text('Edit Profile'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveProfile,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'Profile'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Specialties'),
            Tab(icon: Icon(Icons.payments), text: 'Pricing'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProfileTab(),
                _buildSpecialtiesTab(),
                _buildPricingTab(),
              ],
            ),
    );
  }

  // ===========================================
  // TAB 1: Profile
  // ===========================================
  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Photo
            _buildPhotoSection(),

            const SizedBox(height: 24),

            // Personal Information
            _buildSectionTitle('Personal Information'),
            const SizedBox(height: 12),

            _buildTextField(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),

            _buildTextField(
              controller: _phoneController,
              label: 'Phone Number',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
              hint: '03XX-XXXXXXX',
            ),

            _buildTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.email,
              keyboardType: TextInputType.emailAddress,
              enabled: false,
            ),

            const SizedBox(height: 24),

            // Bio
            _buildSectionTitle('About You'),
            const SizedBox(height: 12),

            _buildTextField(
              controller: _bioController,
              label: 'Bio / Description',
              icon: Icons.description,
              maxLines: 4,
              hint: 'Tell customers about your cooking style, experience, and what makes you special...',
            ),

            _buildTextField(
              controller: _experienceController,
              label: 'Years of Experience',
              icon: Icons.work_history,
              hint: 'e.g., 5 years',
            ),

            const SizedBox(height: 24),

            // Location
            _buildSectionTitle('Location'),
            const SizedBox(height: 12),

            _buildTextField(
              controller: _addressController,
              label: 'Address',
              icon: Icons.location_on,
              maxLines: 2,
              hint: 'House #, Street, Area',
            ),

            _buildTextField(
              controller: _cityController,
              label: 'City',
              icon: Icons.location_city,
              hint: 'e.g., Karachi, Lahore, Islamabad',
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  // ===========================================
  // TAB 2: Specialties
  // ===========================================
  Widget _buildSpecialtiesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cuisines Section
          _buildSectionTitle('Cuisines You Cook'),
          const SizedBox(height: 8),
          Text(
            'Select the types of cuisines you specialize in',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildChipSelector(
            options: _cuisineOptions,
            selected: _selectedCuisines,
            onChanged: (list) => setState(() => _selectedCuisines = list),
            selectedColor: Colors.deepPurple,
          ),

          if (_selectedCuisines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '${_selectedCuisines.length} cuisine(s) selected',
                    style: const TextStyle(color: Colors.deepPurple),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Specialty Dishes Section
          _buildSectionTitle('Specialty Dishes'),
          const SizedBox(height: 8),
          Text(
            'Select the dishes you are best at cooking',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildChipSelector(
            options: _specialtyOptions,
            selected: _selectedSpecialties,
            onChanged: (list) => setState(() => _selectedSpecialties = list),
            selectedColor: Colors.orange,
          ),

          if (_selectedSpecialties.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.restaurant, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedSpecialties.join(', '),
                      style: const TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Tips
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Tips for Better Visibility',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '• Select 2-4 cuisines you are most confident in\n'
                  '• Add your signature dishes\n'
                  '• More specialties = More customers find you\n'
                  '• Keep your selections up to date',
                  style: TextStyle(
                    color: Colors.blue[800],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ===========================================
  // TAB 3: Pricing
  // ===========================================
  Widget _buildPricingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Set your prices for each service type. Enable/disable services you offer.',
                    style: TextStyle(color: Colors.blue[800], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Service 1: Home Cooking
          _buildEditableServiceCard(
            title: 'Home Cooking',
            description: 'Daily meal preparation for families',
            icon: Icons.home,
            color: Colors.blue,
            priceController: _homeCookingPriceController,
            enabled: _homeCookingEnabled,
            onEnabledChanged: (value) => setState(() => _homeCookingEnabled = value),
            suggestedRange: 'Suggested: Rs. 1,200 - 2,000',
          ),

          const SizedBox(height: 16),

          // Service 2: Event Catering
          _buildEditableServiceCard(
            title: 'Event Catering',
            description: 'Parties, gatherings, special occasions',
            icon: Icons.celebration,
            color: Colors.purple,
            priceController: _eventCateringPriceController,
            enabled: _eventCateringEnabled,
            onEnabledChanged: (value) => setState(() => _eventCateringEnabled = value),
            suggestedRange: 'Suggested: Rs. 2,500 - 5,000',
          ),

          const SizedBox(height: 16),

          // Service 3: Premium Services
          _buildEditableServiceCard(
            title: 'Premium Services',
            description: 'Multi-course meals, gourmet cooking',
            icon: Icons.star,
            color: Colors.amber,
            priceController: _premiumServicePriceController,
            enabled: _premiumServiceEnabled,
            onEnabledChanged: (value) => setState(() => _premiumServiceEnabled = value),
            suggestedRange: 'Suggested: Rs. 3,000+',
          ),

          const SizedBox(height: 32),

          // Availability Section
          _buildSectionTitle('General Availability'),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isAvailable
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isAvailable ? Colors.green : Colors.grey,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isAvailable ? Icons.visibility : Icons.visibility_off,
                  color: _isAvailable ? Colors.green : Colors.grey,
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAvailable ? 'Available for Bookings' : 'Not Available',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _isAvailable ? Colors.green[800] : Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isAvailable
                            ? 'Customers can find and book you'
                            : 'You are hidden from search',
                        style: TextStyle(
                          color: _isAvailable ? Colors.green[600] : Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isAvailable,
                  onChanged: (value) => setState(() => _isAvailable = value),
                  activeTrackColor: Colors.green.withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.green;
                    }
                    return Colors.grey;
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildEditableServiceCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required TextEditingController priceController,
    required bool enabled,
    required Function(bool) onEnabledChanged,
    required String suggestedRange,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? color.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled ? color.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Header with toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: enabled ? color.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: enabled ? color.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: enabled ? color : Colors.grey),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: enabled ? color : Colors.grey,
                        ),
                      ),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: enabled ? Colors.grey[700] : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: onEnabledChanged,
                  activeTrackColor: color.withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return color;
                    }
                    return Colors.grey;
                  }),
                ),
              ],
            ),
          ),

          // Price Input (only if enabled)
          if (enabled)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Price Input Field
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Rs.',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceController,
                            keyboardType: TextInputType.number,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: color.withValues(alpha: 0.3),
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        Text(
                          '/session',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Suggested Range
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        suggestedRange,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Disabled message
          if (!enabled)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Text(
                    'Enable to offer this service',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================
  // HELPER WIDGETS
  // ===========================================
  Widget _buildPhotoSection() {
    return Center(
      child: Stack(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 3,
                ),
              ),
              child: ClipOval(
                child: _webImageBytes != null
                    ? Image.memory(_webImageBytes!, fit: BoxFit.cover, width: 120, height: 120)
                    : _newImage != null
                        ? Image.file(_newImage!, fit: BoxFit.cover, width: 120, height: 120)
                        : (_imageUrl != null && _imageUrl!.isNotEmpty)
                            ? CachedChefImage(
                                imageUrl: _imageUrl!,
                                width: 120,
                                height: 120,
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey[400],
                                ),
                              ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: !enabled,
          fillColor: enabled ? null : Colors.grey[100],
        ),
      ),
    );
  }

  Widget _buildChipSelector({
    required List<String> options,
    required List<String> selected,
    required Function(List<String>) onChanged,
    Color selectedColor = Colors.deepPurple,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (value) {
            final newList = List<String>.from(selected);
            if (value) {
              newList.add(option);
            } else {
              newList.remove(option);
            }
            onChanged(newList);
          },
          selectedColor: selectedColor.withValues(alpha: 0.2),
          checkmarkColor: selectedColor,
          labelStyle: TextStyle(
            color: isSelected ? selectedColor : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}

