import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../services/supabase_storage_service.dart';

class ChefProfileSetupScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const ChefProfileSetupScreen({super.key, this.onComplete});

  @override
  State<ChefProfileSetupScreen> createState() => _ChefProfileSetupScreenState();
}

class _ChefProfileSetupScreenState extends State<ChefProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();

  final List<String> _cuisines = [];
  final List<String> _specialties = [];

  // Document upload state
  File? _cnicImage;
  File? _certificateImage;
  Uint8List? _cnicWebBytes; // For web platform
  Uint8List? _certificateWebBytes; // For web platform
  bool _cnicUploading = false;
  bool _certificateUploading = false;
  String? _cnicUrl;
  String? _certificateUrl;

  bool _savingProfile = false;
  bool _loadingUserData = true;
  int _step = 1;

  final ImagePicker _imagePicker = ImagePicker();

  // OTP verification is disabled - kept for future use if needed
  // ignore: unused_field
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _loadExistingUserData();
    _testSupabaseConnection(); // Test Supabase on init
  }

  Future<void> _testSupabaseConnection() async {
    final isConnected = await SupabaseStorageService.testConnection();
    debugPrint('Supabase connection test result: $isConnected');
  }

  Future<void> _loadExistingUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingUserData = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        // Pre-fill name from registration
        if (data['name'] != null && data['name'].toString().isNotEmpty) {
          _nameCtrl.text = data['name'];
        }
        // Pre-fill phone if available
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          _phoneCtrl.text = data['phone'];
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => _loadingUserData = false);
    }
  }

  // Show image source selection dialog
  Future<void> _showImageSourceDialog(String documentType) async {
    // For CNIC
    if (documentType == 'cnic') {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Upload CNIC Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Upload a clear photo of your original CNIC (front side only).',
                          style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Random or fake documents will be rejected.',
                          style: TextStyle(fontSize: 13, color: Colors.red.shade800, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.camera_alt, color: Colors.blue.shade700),
                  ),
                  title: const Text('Take Photo'),
                  subtitle: const Text('Use camera to capture'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera, documentType);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.photo_library, color: Colors.green.shade700),
                  ),
                  title: const Text('Choose from Gallery'),
                  subtitle: const Text('Select from your photos'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery, documentType);
                  },
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // For other documents (certificate) - allow gallery too
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Upload Certificate',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              // Camera option - only show on mobile (not supported on web)
              if (!kIsWeb)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.camera_alt, color: Colors.blue.shade700),
                  ),
                  title: const Text('Take Photo'),
                  subtitle: const Text('Use camera to capture'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera, documentType);
                  },
                ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: Colors.green.shade700),
                ),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Select from your photos'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery, documentType);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Pick image from camera or gallery
  Future<void> _pickImage(ImageSource source, String documentType) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (pickedFile == null) {
        // User cancelled, do nothing
        return;
      }

      if (kIsWeb) {
        // For web platform, use bytes
        final bytes = await pickedFile.readAsBytes();

        if (bytes.isEmpty) {
          _showSnack('Failed to read image file');
          return;
        }

        if (documentType == 'cnic') {
          setState(() {
            _cnicWebBytes = bytes;
            _cnicImage = null;
            _cnicUploading = true;
          });
          await _uploadDocumentBytes(bytes, 'cnic');
        } else {
          setState(() {
            _certificateWebBytes = bytes;
            _certificateImage = null;
            _certificateUploading = true;
          });
          await _uploadDocumentBytes(bytes, 'certificate');
        }
      } else {
        // For mobile platform, use File
        final file = File(pickedFile.path);

        if (!await file.exists()) {
          _showSnack('Failed to access image file');
          return;
        }

        if (documentType == 'cnic') {
          setState(() {
            _cnicImage = file;
            _cnicWebBytes = null;
            _cnicUploading = true;
          });
          await _uploadDocument(file, 'cnic');
        } else {
          setState(() {
            _certificateImage = file;
            _certificateWebBytes = null;
            _certificateUploading = true;
          });
          await _uploadDocument(file, 'certificate');
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      // Reset loading state on error
      if (mounted) {
        setState(() {
          if (documentType == 'cnic') {
            _cnicUploading = false;
          } else {
            _certificateUploading = false;
          }
        });
      }
      _showSnack('Error picking image: $e');
    }
  }

  // Upload document bytes to Supabase Storage (for web)
  Future<void> _uploadDocumentBytes(Uint8List bytes, String documentType) async {
    try {
      debugPrint('Starting Supabase upload for $documentType, bytes size: ${bytes.length}');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('Please login first');
        _resetUploadingState(documentType);
        return;
      }

      String? downloadUrl;

      if (documentType == 'cnic') {
        downloadUrl = await SupabaseStorageService.uploadCNIC(
          bytes: bytes,
          userId: user.uid,
        );
      } else {
        downloadUrl = await SupabaseStorageService.uploadCertificate(
          bytes: bytes,
          userId: user.uid,
        );
      }

      if (downloadUrl != null) {
        debugPrint('Upload complete, URL: $downloadUrl');

        if (mounted) {
          setState(() {
            if (documentType == 'cnic') {
              _cnicUrl = downloadUrl;
              _cnicUploading = false;
            } else {
              _certificateUrl = downloadUrl;
              _certificateUploading = false;
            }
          });
          _showSnack('${documentType == 'cnic' ? 'CNIC' : 'Certificate'} uploaded successfully!');
        }
      } else {
        throw Exception('Upload failed - no URL returned');
      }
    } catch (e) {
      debugPrint('Upload error for $documentType: $e');
      if (mounted) {
        _resetUploadingState(documentType);
        _showSnack('Upload failed: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e}');
      }
    }
  }

  void _resetUploadingState(String documentType) {
    setState(() {
      if (documentType == 'cnic') {
        _cnicUploading = false;
        _cnicWebBytes = null;
        _cnicImage = null;
      } else {
        _certificateUploading = false;
        _certificateWebBytes = null;
        _certificateImage = null;
      }
    });
  }

  // Upload document to Supabase Storage (for mobile)
  Future<void> _uploadDocument(File file, String documentType) async {
    try {
      debugPrint('Starting Supabase mobile upload for $documentType');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('Please login first');
        _resetUploadingState(documentType);
        return;
      }

      // Check if file exists
      if (!await file.exists()) {
        _showSnack('File not found');
        _resetUploadingState(documentType);
        return;
      }

      // Check file size
      final fileSize = await file.length();
      debugPrint('File size: $fileSize bytes');
      if (fileSize > 10 * 1024 * 1024) { // 10MB limit
        _showSnack('File too large. Please select a smaller image.');
        _resetUploadingState(documentType);
        return;
      }

      String? downloadUrl;

      if (documentType == 'cnic') {
        downloadUrl = await SupabaseStorageService.uploadCNIC(
          file: file,
          userId: user.uid,
        );
      } else {
        downloadUrl = await SupabaseStorageService.uploadCertificate(
          file: file,
          userId: user.uid,
        );
      }

      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        debugPrint('Upload complete, URL: $downloadUrl');

        if (mounted) {
          setState(() {
            if (documentType == 'cnic') {
              _cnicUrl = downloadUrl;
              _cnicUploading = false;
            } else {
              _certificateUrl = downloadUrl;
              _certificateUploading = false;
            }
          });
          _showSnack('${documentType == 'cnic' ? 'CNIC' : 'Certificate'} uploaded successfully!');
        }
      } else {
        debugPrint('Upload returned null or empty URL');
        // It could be RLS policy, missing bucket, or network
        throw Exception('Upload failed. Possible reasons: Network issue, or Server configuration (Storage Bucket not found).');
      }
    } catch (e) {
      debugPrint('Mobile upload error for $documentType: $e');
      if (mounted) {
        _resetUploadingState(documentType);
        String errorMsg = e.toString();
        if (errorMsg.contains('Exception:')) {
          errorMsg = errorMsg.replaceAll('Exception:', '').trim();
        }
        _showSnack(errorMsg.length > 80 ? '${errorMsg.substring(0, 80)}...' : errorMsg);
      }
    }
  }

  static const List<String> _cuisineOptions = [
    'Pakistani',
    'BBQ',
    'Chinese',
    'Continental',
    'Italian',
    'Fast Food',
    'Desserts',
    'Traditional',
  ];

  static const List<String> _specialtyOptions = [
    'Biryani',
    'Karahi',
    'Kebabs',
    'Pulao',
    'Haleem',
    'Nihari',
    'Sajji',
    'Tikka',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _bioCtrl.dispose();
    _experienceCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  /// Get current location for chef profile
  Future<LatLng?> _getCurrentLocation() async {
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

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  // OTP verification methods removed - phone verification is disabled
  // Users can proceed directly without OTP

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Please login first');
      return;
    }

    setState(() => _savingProfile = true);

    try {
      // Get chef's current location
      double lat = 34.0151; // Default Peshawar
      double lng = 71.5249;

      try {
        final location = await _getCurrentLocation();
        if (location != null) {
          lat = location.latitude;
          lng = location.longitude;
          debugPrint('Chef location saved: $lat, $lng');
        }
      } catch (e) {
        debugPrint('Could not get chef location: $e');
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'id': user.uid,
          'uid': user.uid,  // Explicitly store Firebase Auth UID
          'email': user.email,
          'role': 'chef',
          'profileCompleted': true,
          'chefProfileComplete': true,
          'name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'bio': _bioCtrl.text.trim(),
          'experience': _experienceCtrl.text.trim(),
          'cuisines': _cuisines,
          'specialties': _specialties,
          'startingPrice': int.tryParse(_rateCtrl.text.trim()) ?? 0,
          'lat': lat,  // Save chef's location
          'lng': lng,
          'documents': {
            'cnicUrl': _cnicUrl,
            'certificateUrl': _certificateUrl,
            'cnicUploaded': _cnicUrl != null,
            'certificateUploaded': _certificateUrl != null,
          },
          // Verification status fields
          'verification_status': 'pending', // pending, approved, rejected
          'verification_document_url': _cnicUrl,
          'verification_submitted_at': FieldValue.serverTimestamp(),
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      widget.onComplete?.call();
      _showSnack('Profile saved successfully');
    } on FirebaseException catch (e) {
      _showSnack(e.message ?? e.code);
    } catch (e) {
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  bool get _hasStepOneDetails =>
      _bioCtrl.text.trim().isNotEmpty &&
      _experienceCtrl.text.trim().isNotEmpty;

  bool get _isPhoneValid => _phoneCtrl.text.trim().length == 11;

  // OTP validation removed since phone verification is disabled

  bool _canProceed() {
    switch (_step) {
      case 1:
        // Phone verification disabled - only check basic details
        return _hasStepOneDetails && _isPhoneValid;
      case 2:
        return _cuisines.length >= 2 && _specialties.length >= 3;
      case 3:
        return _rateCtrl.text.trim().isNotEmpty;
      case 4:
        // Only CNIC is required, certificate is optional
        return _cnicUrl != null && !_cnicUploading;
      default:
        return false;
    }
  }

  void _toggleCuisine(String cuisine) {
    setState(() {
      if (_cuisines.contains(cuisine)) {
        _cuisines.remove(cuisine);
      } else {
        _cuisines.add(cuisine);
      }
    });
  }

  void _toggleSpecialty(String dish) {
    setState(() {
      if (_specialties.contains(dish)) {
        _specialties.remove(dish);
      } else {
        _specialties.add(dish);
      }
    });
  }

  Widget _buildDocumentUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required File? image,
    Uint8List? webBytes,
    required String? uploadedUrl,
    required bool isUploading,
    required VoidCallback onTap,
    required VoidCallback onRemove,
    bool isOptional = false,
  }) {
    final bool hasImage = image != null || webBytes != null || uploadedUrl != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasImage
              ? Colors.green.shade300
              : (isOptional ? Colors.grey.shade300 : Colors.orange.shade300),
          width: 2,
        ),
        color: hasImage ? Colors.green.shade50 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: hasImage
                      ? Colors.green.shade100
                      : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasImage ? Icons.check_circle : icon,
                  color: hasImage ? Colors.green : Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (isOptional) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Optional',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (isUploading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Uploading...', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else if (hasImage)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: webBytes != null
                      ? Image.memory(
                          webBytes,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        )
                      : image != null
                          ? Image.file(
                              image,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            )
                          : Image.network(
                          uploadedUrl!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const SizedBox(
                              height: 150,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 150,
                            width: double.infinity,
                            color: Colors.grey.shade200,
                            child: Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
                          ),
                        ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            )
          else
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 30),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(Icons.cloud_upload, size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to upload',
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Camera or Gallery',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {
              if (_step == 1) {
                Navigator.of(context).maybePop();
              } else {
                setState(() => _step -= 1);
              }
            },
            icon: const Icon(Icons.arrow_back),
          ),
          Row(
            children: List.generate(
              4,
              (index) => Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index + 1 <= _step
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildStepOne() {
    // Phone verification disabled - show only basic form
    // Name is already collected during registration
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _StepTitle(
          title: 'Tell us about yourself',
          subtitle: 'Help customers know more about you',
        ),
        const SizedBox(height: 24),
        _LabeledField(
          label: 'Phone Number *',
          controller: _phoneCtrl,
          hint: '03XX-XXXXXXX',
          keyboardType: TextInputType.phone,
          maxLength: 11,
          onChanged: () => setState(() {}),
        ),
        _LabeledField(
          label: 'Bio *',
          controller: _bioCtrl,
          hint: 'Tell customers about your cooking style...',
          maxLines: 4,
          onChanged: () => setState(() {}),
        ),
        _LabeledField(
          label: 'Years of Experience *',
          controller: _experienceCtrl,
          hint: 'e.g., 5 years',
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildStepTwo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Your Specialties',
          subtitle: 'Select the cuisines and dishes you excel at',
        ),
        const SizedBox(height: 16),
        _ChipSelector(
          label: 'Cuisines (select 2-4)',
          options: _cuisineOptions,
          selected: _cuisines,
          onTap: _toggleCuisine,
        ),
        const SizedBox(height: 16),
        _ChipSelector(
          label: 'Specialty Dishes (select 3-6)',
          options: _specialtyOptions,
          selected: _specialties,
          onTap: _toggleSpecialty,
        ),
      ],
    );
  }

  Widget _buildStepThree() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Set Your Rates',
          subtitle: 'How much do you charge for your services?',
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Starting Rate (Rs. per session)',
          controller: _rateCtrl,
          hint: 'e.g., 1500',
          keyboardType: TextInputType.number,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        _GuidelineCard(
          items: const [
            'Home cooking: Rs. 1,200 - 2,000',
            'Event catering: Rs. 2,500 - 5,000',
            'Premium services: Rs. 3,000+',
          ],
        ),
      ],
    );
  }

  Widget _buildStepFour() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Verification Documents',
          subtitle: 'Upload documents to verify your identity',
        ),
        const SizedBox(height: 16),

        // Important notice
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Important Instructions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Upload a clear photo of your original CNIC (front side only)\n'
                '• Make sure all text is readable\n'
                '• Camera capture is required for security',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue.shade800,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Warning about fake documents
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Random or fake documents will be rejected.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.red.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // CNIC Upload (Required)
        _buildDocumentUploadCard(
          title: 'CNIC/ID Card *',
          subtitle: 'Upload clear photo (front side)',
          icon: Icons.credit_card,
          image: _cnicImage,
          webBytes: _cnicWebBytes,
          uploadedUrl: _cnicUrl,
          isUploading: _cnicUploading,
          onTap: () => _showImageSourceDialog('cnic'),
          onRemove: () {
            setState(() {
              _cnicImage = null;
              _cnicWebBytes = null;
              _cnicUrl = null;
            });
          },
        ),

        const SizedBox(height: 16),

        // Certificate Upload (Optional)
        _buildDocumentUploadCard(
          title: 'Cooking Certificate',
          subtitle: 'Any cooking certification (Optional)',
          icon: Icons.workspace_premium,
          image: _certificateImage,
          webBytes: _certificateWebBytes,
          uploadedUrl: _certificateUrl,
          isUploading: _certificateUploading,
          isOptional: true,
          onTap: () => _showImageSourceDialog('certificate'),
          onRemove: () {
            setState(() {
              _certificateImage = null;
              _certificateWebBytes = null;
              _certificateUrl = null;
            });
          },
        ),

        const SizedBox(height: 16),
        _InfoBanner(
          text:
              'Your documents are under review after submission. Verification takes 24-48 hours.',
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case 1:
        return _buildStepOne();
      case 2:
        return _buildStepTwo();
      case 3:
        return _buildStepThree();
      case 4:
        return _buildStepFour();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter() {
    Widget action;
    String? validationMessage;

    if (_step == 1) {
      // Phone verification disabled - directly proceed to next step
      action = ElevatedButton(
        onPressed: _canProceed() ? () => setState(() => _step += 1) : null,
        child: const Text('Continue'),
      );
      // Show what's missing
      List<String> missing = [];
      if (_bioCtrl.text.trim().isEmpty) missing.add('Bio');
      if (_experienceCtrl.text.trim().isEmpty) missing.add('Experience');
      if (_phoneCtrl.text.trim().length != 11) missing.add('Phone (11 digits)');
      if (missing.isNotEmpty) {
        validationMessage = 'Required: ${missing.join(', ')}';
      }
    } else if (_step < 4) {
      action = ElevatedButton(
        onPressed: _canProceed()
            ? () => setState(() => _step += 1)
            : null,
        child: const Text('Continue'),
      );
    } else {
      action = ElevatedButton(
        onPressed: _canProceed() && !_savingProfile ? _saveProfile : null,
        child: Text(_savingProfile ? 'Saving…' : 'Complete Setup'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (validationMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                validationMessage,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: action,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUserData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildContent(),
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final VoidCallback? onChanged;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.maxLines,
    this.maxLength,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines ?? 1,
            maxLength: maxLength,
            onChanged: (_) => onChanged?.call(),
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipSelector extends StatelessWidget {
  final String label;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onTap;

  const _ChipSelector({
    required this.label,
    required this.options,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((item) {
            final active = selected.contains(item);
            return ChoiceChip(
              label: Text(item),
              selected: active,
              onSelected: (_) => onTap(item),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _GuidelineCard extends StatelessWidget {
  final List<String> items;

  const _GuidelineCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map((text) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(text, style: theme.textTheme.bodySmall),
                ))
            .toList(),
      ),
    );
  }
}


class _InfoBanner extends StatelessWidget {
  final String text;

  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

// ignore: unused_element
class _OtpField extends StatefulWidget {
  final ValueChanged<String> onOtpChanged;
  final int length;

  // ignore: unused_element_parameter
  const _OtpField({required this.onOtpChanged, this.length = 6});

  @override
  State<_OtpField> createState() => _OtpFieldState();
}

class _OtpFieldState extends State<_OtpField> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.length == 1 && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    widget.onOtpChanged(_otp);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.length, (index) {
        return Container(
          width: 48,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            maxLength: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            onChanged: (value) => _onChanged(index, value),
            decoration: InputDecoration(
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
