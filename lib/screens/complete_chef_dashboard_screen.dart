import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import '../services/booking_request_service.dart';
import '../services/chat_service.dart';
import '../services/location_service.dart';
import '../services/deal_negotiation_service.dart';
import '../services/onesignal_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_storage_service.dart';
import '../services/presence_service.dart';
import '../models/cooking_request.dart';
import '../widgets/cached_chef_image.dart';
import 'chef_documents_screen.dart';
import 'chef_profile_edit_screen.dart';
import 'chef_route_map_screen.dart';
import 'chat_list_screen.dart';
import 'chat_screen.dart';
import 'notification_settings_screen.dart';
import 'notifications_screen.dart';
import 'privacy_security_screen.dart';
import 'help_support_screen.dart';
import 'chef_broadcast_requests_screen.dart';
import 'commission_payment_screen.dart';

/// Complete Chef Dashboard with Drawer and all features
class CompleteChefDashboardScreen extends StatefulWidget {
  final Function(String screen, {Map<String, dynamic>? data})? onNavigate;
  final VoidCallback? onSwitchToCustomer; // InDrive-style mode switch

  const CompleteChefDashboardScreen({
    super.key,
    this.onNavigate,
    this.onSwitchToCustomer,
  });

  @override
  State<CompleteChefDashboardScreen> createState() => _CompleteChefDashboardScreenState();
}

class _CompleteChefDashboardScreenState extends State<CompleteChefDashboardScreen>
    with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Map<String, dynamic>? chefData;
  bool isLoading = true;
  int _currentIndex = 0;

  // Stats
  int totalBookings = 0;
  int pendingBookings = 0;
  int acceptedBookings = 0;
  int completedBookings = 0;
  double totalEarnings = 0;
  double realRating = 0.0;
  int reviewCount = 0;
  int unreadMessages = 0;

  // Commission tracking (Earning Cycle Based)
  double currentCycleEarnings = 0; // Earnings in current commission cycle
  double commissionPending = 0;    // Pending commission to pay
  bool isOrderBlocked = false;     // Whether new orders are blocked

  // Chef's current location
  LatLng? _chefLocation;
  bool _isLocationLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChefData();
    _loadStats();
    _loadRealRating();
    _listenToUnreadMessages();
    _loadAndUpdateChefLocation(); // Load chef's real location
    _autoFixWrongChefIds(); // Auto-fix any wrong chefIds
    _loadCommissionData(); // Load commission tracking data

    // Set chef online via presence service (heartbeat-based)
    PresenceService.goOnline();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Set chef offline when leaving the dashboard
    PresenceService.goOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground — set chef online
        PresenceService.goOnline();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App went to background or closed — set chef offline
        PresenceService.goOffline();
        break;
      default:
        break;
    }
  }

  /// Auto-fix: Update any pending requests with wrong chefId to current chef's UID
  /// This handles cases where old data has incorrect chefId stored
  Future<void> _autoFixWrongChefIds() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Known wrong chefId that was being saved due to bug
      const wrongChefId = 'dYBQdjiCyEYGW8kV8mJ9GxNJScG3';

      // Check if there are any pending requests with wrong chefId
      final wrongRequests = await _firestore
          .collection('bookingRequests')
          .where('chefId', isEqualTo: wrongChefId)
          .where('status', isEqualTo: 'pending')
          .get();

      if (wrongRequests.docs.isNotEmpty) {
        debugPrint('Auto-fixing ${wrongRequests.docs.length} requests with wrong chefId');

        // Update each request with correct chefId
        for (var doc in wrongRequests.docs) {
          await doc.reference.update({'chefId': uid});
        }

        debugPrint('Fixed ${wrongRequests.docs.length} requests');

        // Refresh stats
        if (mounted) {
          _loadStats();
        }
      }
    } catch (e) {
      debugPrint('Auto-fix error: $e');
    }
  }

  /// Load chef's current location and update in Firestore
  Future<void> _loadAndUpdateChefLocation() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      debugPrint('Chef Dashboard: Loading location...');
      final location = await LocationService.getCurrentLocationWithFallback();

      if (location != null && mounted) {
        debugPrint('Chef Dashboard: Got location: ${location.latitude}, ${location.longitude}');

        setState(() {
          _chefLocation = location;
          _isLocationLoading = false;
        });

        // Update chef's location in Firestore
        await _firestore.collection('users').doc(uid).update({
          'lat': location.latitude,
          'lng': location.longitude,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint('Chef Dashboard: Location saved to Firestore');
      } else {
        debugPrint('Chef Dashboard: Could not get location');
        if (mounted) {
          setState(() => _isLocationLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Chef Dashboard: Error updating location: $e');
      if (mounted) {
        setState(() => _isLocationLoading = false);
      }
    }
  }

  void _listenToUnreadMessages() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    ChatService().getUnreadCount(uid, isChef: true).listen((messageCount) {
      if (mounted) {
        setState(() => unreadMessages = messageCount);
      }
    });
  }

  Future<void> _loadChefData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;

        // Ensure isAvailable field exists (default to false — PresenceService will set it online)
        if (!data.containsKey('isAvailable')) {
          await _firestore.collection('users').doc(uid).update({
            'isAvailable': false,
          });
          data['isAvailable'] = false;
        }

        setState(() {
          chefData = Map<String, dynamic>.from(data); // Mutable copy
          isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() => isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading chef data: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Get verification status text for drawer menu
  String _getVerificationStatusText() {
    if (chefData == null) return 'Upload your CNIC';

    // Check both field names for compatibility
    final status = chefData!['verificationStatus'] ?? chefData!['verification_status'] ?? 'not_submitted';
    switch (status) {
      case 'pending':
        return 'Under review';
      case 'verified':
      case 'approved':
        return 'Verified ✓';
      case 'rejected':
        return 'Rejected - Re-upload';
      default:
        return 'Upload your CNIC';
    }
  }

  /// Show profile picture upload options
  void _showProfilePictureOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Update Profile Picture',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt, color: Color(0xFFFF6B35)),
                ),
                title: const Text('Take Photo'),
                subtitle: const Text('Use camera to take a new picture'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.blue),
                ),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Select an existing photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickProfileImage(ImageSource.gallery);
                },
              ),
              if (chefData?['image'] != null && chefData!['image'].toString().isNotEmpty)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  title: const Text('Remove Photo'),
                  subtitle: const Text('Delete current profile picture'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeProfileImage();
                  },
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick and upload profile image
  Future<void> _pickProfileImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Close drawer
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(color: Color(0xFFFF6B35)),
                SizedBox(width: 20),
                Text('Uploading picture...'),
              ],
            ),
          ),
        );
      }

      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      // Upload to Supabase
      final imageFile = File(pickedFile.path);
      final imageUrl = await SupabaseStorageService.uploadChefProfileImage(
        file: imageFile,
        userId: uid,
      );

      if (imageUrl != null) {
        // Update Firestore
        await _firestore.collection('users').doc(uid).update({
          'image': imageUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Reload chef data
        await _loadChefData();

        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to upload image. Try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking/uploading image: $e');
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Remove profile image
  Future<void> _removeProfileImage() async {
    try {
      // Close drawer
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Update Firestore to remove image
      await _firestore.collection('users').doc(uid).update({
        'image': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reload chef data
      await _loadChefData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error removing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build verification status banner for dashboard
  Widget _buildVerificationBanner() {
    if (chefData == null) return const SizedBox.shrink();

    // Check both field names for compatibility
    String status = chefData!['verificationStatus'] ?? chefData!['verification_status'] ?? 'not_submitted';
    final cnicUrl = chefData!['cnicUrl'];

    // If no CNIC uploaded but status is pending, treat as not_submitted
    if ((cnicUrl == null || cnicUrl.toString().isEmpty) && status == 'pending') {
      status = 'not_submitted';
    }

    // Don't show banner if already approved/verified
    if (status == 'approved' || status == 'verified') return const SizedBox.shrink();

    Color bannerColor;
    IconData bannerIcon;
    String bannerTitle;
    String bannerMessage;
    bool showUploadButton = false;

    switch (status) {
      case 'pending':
        bannerColor = Colors.orange;
        bannerIcon = Icons.hourglass_empty;
        bannerTitle = 'Verification Under Review';
        bannerMessage = 'Your CNIC documents are being verified. This usually takes 24-48 hours.';
        break;
      case 'rejected':
        bannerColor = Colors.red;
        bannerIcon = Icons.cancel_outlined;
        bannerTitle = 'Verification Rejected';
        bannerMessage = chefData!['rejectionReason'] ?? chefData!['verification_rejection_reason'] ?? 'Please re-upload a clear photo of your CNIC.';
        showUploadButton = true;
        break;
      default:
        bannerColor = Colors.blue;
        bannerIcon = Icons.upload_file;
        bannerTitle = 'Complete Verification';
        bannerMessage = 'Upload your CNIC to get verified and receive more bookings.';
        showUploadButton = true;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bannerIcon, color: bannerColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bannerTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: bannerColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bannerMessage,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          if (showUploadButton) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChefDocumentsScreen(
                        onSave: () {
                          _loadChefData();
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.upload, size: 18),
                label: Text(status == 'rejected' ? 'Re-upload CNIC' : 'Upload CNIC'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: bannerColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build order blocked warning banner
  /// Shows when earning cycle reaches 5000 PKR threshold
  /// "Chef lifetime earnings are permanent. Orders are blocked only when unpaid
  /// cycle earnings reach 5000 PKR, and unblocked after commission settlement."
  Widget _buildOrderBlockedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Order Limit Reached!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your earning cycle has reached Rs. 5,000. You cannot accept new orders until you pay your pending commission.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.red.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cycle Earnings:', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Rs. ${currentCycleEarnings.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Pending Commission (10%):', style: TextStyle(fontWeight: FontWeight.w500)),
                    Text('Rs. ${commissionPending.toStringAsFixed(0)}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CommissionPaymentScreen()),
                ).then((_) => _loadCommissionData()); // Refresh after payment
              },
              icon: const Icon(Icons.payment, size: 20),
              label: const Text('Pay Commission Now'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build earning cycle warning when approaching limit
  Widget _buildEarningCycleWarning() {
    final remaining = 5000 - currentCycleEarnings;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Approaching limit! Rs. ${remaining.toStringAsFixed(0)} remaining in this earning cycle.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build earning cycle progress card
  Widget _buildEarningCycleCard() {
    final progress = (currentCycleEarnings / 5000).clamp(0.0, 1.0);
    final progressPercent = (progress * 100).toStringAsFixed(0);

    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Current Earning Cycle',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                'Rs. ${currentCycleEarnings.toStringAsFixed(0)} / 5,000',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: progress >= 0.8 ? Colors.orange.shade700 : Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= 1.0 ? Colors.red :
                progress >= 0.8 ? Colors.orange :
                Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$progressPercent% of cycle limit',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              if (commissionPending > 0)
                Text(
                  'Commission: Rs. ${commissionPending.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade600,
                  ),
                ),
            ],
          ),
          if (commissionPending > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CommissionPaymentScreen()),
                  ).then((_) => _loadCommissionData());
                },
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Pay Commission', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  side: BorderSide(color: Colors.blue.shade400),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadStats() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Get pending requests
      final pendingSnapshot = await _firestore
          .collection('bookingRequests')
          .where('chefId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();

      // Get all bookings
      final bookingsSnapshot = await _firestore
          .collection('bookings')
          .where('chefId', isEqualTo: uid)
          .get();

      int accepted = 0;
      int completed = 0;
      double earnings = 0;

      for (var doc in bookingsSnapshot.docs) {
        final status = doc.data()['status'];
        final amount = (doc.data()['price'] ?? doc.data()['total'] ?? 0).toDouble();

        if (status == 'confirmed') accepted++;
        if (status == 'completed') {
          completed++;
          earnings += amount;
        }
      }

      if (mounted) {
        setState(() {
          pendingBookings = pendingSnapshot.docs.length;
          totalBookings = bookingsSnapshot.docs.length;
          acceptedBookings = accepted;
          completedBookings = completed;
          totalEarnings = earnings;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  /// Load real rating calculated from reviews collection
  Future<void> _loadRealRating() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Get all reviews for this chef
      final reviewsSnapshot = await _firestore
          .collection('reviews')
          .where('chefId', isEqualTo: uid)
          .get();

      if (reviewsSnapshot.docs.isEmpty) {
        if (mounted) {
          setState(() {
            realRating = 0.0;
            reviewCount = 0;
          });
        }
        return;
      }

      // Calculate average rating
      double totalRating = 0;
      for (var doc in reviewsSnapshot.docs) {
        totalRating += (doc.data()['rating'] ?? 0).toDouble();
      }

      final avgRating = totalRating / reviewsSnapshot.docs.length;

      if (mounted) {
        setState(() {
          realRating = double.parse(avgRating.toStringAsFixed(1));
          reviewCount = reviewsSnapshot.docs.length;
        });
      }

      // Also update the chef's profile with calculated rating
      await _firestore.collection('users').doc(uid).update({
        'rating': realRating,
        'reviewCount': reviewCount,
      });

    } catch (e) {
      debugPrint('Error loading real rating: $e');
    }
  }

  /// Load commission tracking data from Firestore
  /// This tracks the earning cycle-based blocking system:
  /// - current_cycle_earnings: Earnings until commission is paid (resets after payment)
  /// - total_earnings: Lifetime earnings (NEVER reset)
  /// - commission_pending: Pending commission amount (10% of cycle earnings)
  /// - is_order_blocked: True when cycle earnings >= 5000 PKR
  Future<void> _loadCommissionData() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final userDoc = await _firestore.collection('users').doc(uid).get();
      final data = userDoc.data();

      if (data != null && mounted) {
        setState(() {
          currentCycleEarnings = (data['current_cycle_earnings'] ?? 0.0).toDouble();
          commissionPending = (data['commission_pending'] ?? 0.0).toDouble();

          // IMPORTANT: Only consider orders blocked if:
          // 1. is_order_blocked flag is true from Firestore AND
          // 2. Current cycle earnings actually >= 5000 AND
          // 3. Commission is actually pending
          // This ensures after payment is approved (cycle reset), orders are unblocked
          final firestoreBlocked = data['is_order_blocked'] ?? false;
          isOrderBlocked = firestoreBlocked &&
                           currentCycleEarnings >= 5000 &&
                           commissionPending > 0;

          // Also update totalEarnings from Firestore (lifetime earnings)
          final firestoreTotalEarnings = (data['total_earnings'] ?? 0.0).toDouble();
          if (firestoreTotalEarnings > totalEarnings) {
            totalEarnings = firestoreTotalEarnings;
          }
        });

        debugPrint('Commission data loaded:');
        debugPrint('  - Current cycle earnings: Rs. $currentCycleEarnings');
        debugPrint('  - Pending commission: Rs. $commissionPending');
        debugPrint('  - Orders blocked: $isOrderBlocked');
        debugPrint('  - Total earnings (lifetime): Rs. $totalEarnings');
      }
    } catch (e) {
      debugPrint('Error loading commission data: $e');
    }
  }

  Future<void> _toggleAvailability(bool value) async {
    // Immediately update UI for responsive feel
    final previousValue = chefData?['isAvailable'] ?? false;

    setState(() {
      if (chefData != null) {
        chefData!['isAvailable'] = value;
      }
    });

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        // Revert if no user
        setState(() {
          if (chefData != null) {
            chefData!['isAvailable'] = previousValue;
          }
        });
        return;
      }

      await _firestore.collection('users').doc(uid).update({
        'isAvailable': value,
        'lastOnlineAt': FieldValue.serverTimestamp(),
      });

      // Sync with PresenceService for heartbeat management
      if (value) {
        PresenceService.goOnline();
        // Chef is going online - start sharing location (both Firestore and Realtime DB)
        LocationService.startRealtimeLocationUpdates(uid);
        LocationService.startChefFirestoreLocationUpdates();
      } else {
        PresenceService.goOffline();
        // Chef is going offline - stop sharing location
        LocationService.stopRealtimeLocationUpdates(uid);
        LocationService.stopChefFirestoreLocationUpdates();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  value ? Icons.location_on : Icons.location_off,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    value ? 'You are now online' : 'You are now offline',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: value ? Colors.green : Colors.grey,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error toggling availability: $e');
      // Revert on error
      setState(() {
        if (chefData != null) {
          chefData!['isAvailable'] = previousValue;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Logout from OneSignal first
      await OneSignalService.logoutUser();
      await _auth.signOut();
      widget.onNavigate?.call('auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 400;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                isSmallScreen ? 'Chef' : 'Chef Dashboard',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isSmallScreen ? 'Chef' : 'Chef Mode',
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Online/Offline Toggle with status indicator
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: chefData?['isAvailable'] == true ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 40,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Switch(
                      value: chefData?['isAvailable'] ?? false,
                      onChanged: _toggleAvailability,
                      activeTrackColor: Colors.green.shade200,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Notification Bell
          StreamBuilder<int>(
            stream: NotificationService.getUnreadCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.notifications_outlined, size: 22),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotificationsScreen(
                        onBack: () => Navigator.pop(context),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh, size: 22),
            onPressed: () {
              _loadChefData();
              _loadStats();
              _loadRealRating();
            },
          ),
        ],
      ),
      drawer: _buildChefDrawer(),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildDashboardTab(),
                _buildBookingsTab(),
                _buildEarningsTab(),
                _buildReviewsTab(),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingBookings > 0,
              label: Text('$pendingBookings'),
              child: const Icon(Icons.calendar_today_outlined),
            ),
            selectedIcon: const Icon(Icons.calendar_today),
            label: 'Bookings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Earnings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.star_outline),
            selectedIcon: Icon(Icons.star),
            label: 'Reviews',
          ),
        ],
      ),
    );
  }

  // ===========================================
  // CHEF DRAWER - Complete with all options
  // ===========================================
  Widget _buildChefDrawer() {
    return Drawer(
      child: Column(
        children: [
          // Drawer Header with chef info - Beautiful Orange-White Theme
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF6B35), // Warm orange
                  const Color(0xFFFF8C42), // Light orange
                  const Color(0xFFFFE8DC), // Very light peach/cream
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Picture with upload functionality
                GestureDetector(
                  onTap: () => _showProfilePictureOptions(),
                  child: Stack(
                    children: [
                      Container(
                        width: 85,
                        height: 85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: chefData?['image'] != null && chefData!['image'].toString().isNotEmpty
                              ? CachedChefImage(
                                  imageUrl: chefData!['image'],
                                  width: 85,
                                  height: 85,
                                )
                              : Container(
                                  color: Colors.white,
                                  child: const Icon(
                                    Icons.person,
                                    size: 45,
                                    color: Color(0xFFFF6B35),
                                  ),
                                ),
                        ),
                      ),
                      // Camera overlay icon
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B35),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Name with shadow for better visibility
                Text(
                  chefData?['name'] ?? 'Chef',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    shadows: [
                      Shadow(
                        color: Colors.black26,
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Email
                Text(
                  chefData?['email'] ?? _auth.currentUser?.email ?? '',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 13,
                    shadows: const [
                      Shadow(
                        color: Colors.black12,
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Rating - with white background badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        reviewCount > 0
                            ? '${realRating.toStringAsFixed(1)} ($reviewCount reviews)'
                            : 'No reviews yet',
                        style: const TextStyle(
                          color: Color(0xFFFF6B35),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Online Status - Enhanced badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: chefData?['isAvailable'] == true
                        ? Colors.green.shade600
                        : Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (chefData?['isAvailable'] == true ? Colors.green : Colors.grey).withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        chefData?['isAvailable'] == true ? 'Online' : 'Offline',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Mode Switch Card (InDrive Style) - Always shown
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.green.shade600, Colors.green.shade400],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.person, color: Colors.white),
                    title: const Text(
                      'Switch to Customer Mode',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Book chefs for yourself',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      widget.onSwitchToCustomer?.call();
                    },
                  ),
                ),

                // Quick Access - Live Map
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade400],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.map, color: Colors.white),
                    title: const Text(
                      'Open Live Map',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _chefLocation != null
                          ? 'Your location is being tracked'
                          : 'View map with your location',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    trailing: _isLocationLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.navigation, color: Colors.white, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChefRouteMapScreen(
                            customerLocation: _chefLocation ?? const LatLng(34.0151, 71.5249),
                            customerName: 'My Location',
                            isChefView: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Account Section
                _buildDrawerSectionTitle('ACCOUNT'),
                _buildDrawerMenuItem(
                  icon: Icons.person_outline,
                  title: 'My Profile',
                  subtitle: 'View and edit your profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChefProfileEditScreen(
                          initialTab: 0, // Profile tab
                          onSave: () {
                            _loadChefData();
                            _loadRealRating();
                          },
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerMenuItem(
                  icon: Icons.verified_user_outlined,
                  title: 'CNIC Verification',
                  subtitle: _getVerificationStatusText(),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChefDocumentsScreen(
                          onSave: () {
                            _loadChefData();
                          },
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerMenuItem(
                  icon: Icons.chat_bubble_outline,
                  title: 'Messages',
                  subtitle: unreadMessages > 0
                      ? '$unreadMessages unread messages'
                      : 'Chat with customers',
                  badge: unreadMessages,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChatListScreen(isChefView: true),
                      ),
                    );
                  },
                ),

                const Divider(),


                // Settings Section
                _buildDrawerSectionTitle('SETTINGS'),
                _buildDrawerMenuItem(
                  icon: Icons.visibility,
                  title: 'Availability',
                  subtitle: chefData?['isAvailable'] == true ? 'You are Online' : 'You are Offline',
                  trailing: Switch(
                    value: chefData?['isAvailable'] ?? false,
                    onChanged: (value) {
                      _toggleAvailability(value);
                    },
                    activeTrackColor: Colors.green.shade200,
                  ),
                  onTap: () {},
                ),
                _buildDrawerMenuItem(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage notification settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerMenuItem(
                  icon: Icons.security,
                  title: 'Privacy & Security',
                  subtitle: 'Password, privacy settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PrivacySecurityScreen(
                          onBack: () => Navigator.pop(context),
                        ),
                      ),
                    );
                  },
                ),

                const Divider(),

                // Support Section
                _buildDrawerSectionTitle('SUPPORT'),
                _buildDrawerMenuItem(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  subtitle: 'FAQs, contact us',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HelpSupportScreen(
                          onBack: () => Navigator.pop(context),
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerMenuItem(
                  icon: Icons.info_outline,
                  title: 'About ChefKart',
                  subtitle: 'App info, version',
                  onTap: () {
                    Navigator.pop(context);
                    _showAboutDialog();
                  },
                ),
                _buildDrawerMenuItem(
                  icon: Icons.policy_outlined,
                  title: 'Terms & Conditions',
                  subtitle: 'Privacy policy, terms',
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Add Terms screen
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Terms & Conditions coming soon')),
                    );
                  },
                ),

                const Divider(),

                // Danger Zone
                _buildDrawerMenuItem(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out of your account',
                  iconColor: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    _logout();
                  },
                ),

                const SizedBox(height: 20),

                // App Version
                Center(
                  child: Text(
                    'ChefKart v1.0.0',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildDrawerMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
    int badge = 0,
  }) {
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (iconColor ?? Colors.deepPurple).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor ?? Colors.deepPurple, size: 22),
          ),
          if (badge > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: iconColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: trailing ?? Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'ChefKart',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.deepPurple,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.restaurant, color: Colors.white),
      ),
      children: [
        const Text('Find verified home chefs at your doorstep.'),
        const SizedBox(height: 10),
        const Text('© 2025 ChefKart. All rights reserved.'),
      ],
    );
  }


  // ===========================================
  // DASHBOARD TAB
  // ===========================================
  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadChefData();
        await _loadStats();
        await _loadRealRating();
        await _loadCommissionData(); // Also refresh commission data
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Verification Status Banner
            _buildVerificationBanner(),

            // ORDER BLOCKED WARNING BANNER
            // Shows when earning cycle threshold (5000 PKR) is reached AND commission is pending
            // After commission payment is approved, cycle is reset and banner should not show
            if (isOrderBlocked && commissionPending > 0 && currentCycleEarnings >= 5000)
              _buildOrderBlockedBanner(),

            // Commission Cycle Warning (show when approaching limit but not yet blocked)
            if (!isOrderBlocked && currentCycleEarnings >= 4000 && currentCycleEarnings < 5000)
              _buildEarningCycleWarning(),

            // Stats Cards Row 1
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.payments,
                    iconColor: Colors.green,
                    label: 'Total Earnings',
                    value: 'Rs. ${totalEarnings.toStringAsFixed(0)}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.star,
                    iconColor: Colors.amber,
                    label: 'Rating',
                    value: reviewCount > 0 ? realRating.toStringAsFixed(1) : '0.0',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Earning Cycle Stats (shows current cycle progress)
            if (currentCycleEarnings > 0) _buildEarningCycleCard(),

            const SizedBox(height: 12),

            // Stats Cards Row 2
            Row(
              children: [
                Expanded(
                  child: _buildMiniStatCard(
                    label: 'Total Bookings',
                    value: '$totalBookings',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniStatCard(
                    label: 'Pending',
                    value: '$pendingBookings',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniStatCard(
                    label: 'Accepted',
                    value: '$acceptedBookings',
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Location Status Card
            _buildLocationStatusCard(),

            const SizedBox(height: 24),


            // 🔥 Broadcast Requests Section (InDrive-style)
            _buildBroadcastRequestsSection(),

            const SizedBox(height: 24),

            // Pending Requests Section
            _buildSectionHeader(
              'Direct Requests',
              badge: pendingBookings,
              onSeeAll: () => setState(() => _currentIndex = 1),
            ),

            _buildPendingRequestsPreview(),

            const SizedBox(height: 24),

            // Upcoming Bookings Section
            _buildSectionHeader(
              'Upcoming Bookings',
              onSeeAll: () => setState(() => _currentIndex = 1),
            ),
            _buildUpcomingBookingsPreview(),

            const SizedBox(height: 24),

            // Bottom Action Buttons
            _buildActionButton(
              icon: Icons.calendar_month,
              label: 'Manage Schedule & Availability',
              onTap: () => _showAvailabilitySheet(),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Build location status card showing chef's current location
  Widget _buildLocationStatusCard() {
    final bool hasLocation = _chefLocation != null;
    final bool isOnline = chefData?['isAvailable'] ?? false;

    return GestureDetector(
      onTap: () {
        if (hasLocation) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChefRouteMapScreen(
                customerLocation: _chefLocation!,
                customerName: 'My Location',
                isChefView: true,
              ),
            ),
          );
        } else {
          _loadAndUpdateChefLocation();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasLocation
                ? [Colors.green.shade50, Colors.green.shade100]
                : [Colors.orange.shade50, Colors.orange.shade100],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasLocation ? Colors.green.shade300 : Colors.orange.shade300,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasLocation ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
              child: _isLocationLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      hasLocation ? Icons.location_on : Icons.location_off,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasLocation ? '📍 Location Active' : '📍 Location Not Set',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: hasLocation ? Colors.green.shade800 : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasLocation
                        ? 'Lat: ${_chefLocation!.latitude.toStringAsFixed(4)}, Lng: ${_chefLocation!.longitude.toStringAsFixed(4)}'
                        : 'Tap to update your location',
                    style: TextStyle(
                      fontSize: 12,
                      color: hasLocation ? Colors.green.shade600 : Colors.orange.shade600,
                    ),
                  ),
                  if (isOnline && hasLocation)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Live tracking enabled',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              ),
            Icon(
              Icons.chevron_right,
              color: hasLocation ? Colors.green.shade600 : Colors.orange.shade600,
            ),
          ],
        ),
      ),
    );
  }


  /// Build broadcast requests section (InDrive-style)
  Widget _buildBroadcastRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.broadcast_on_home, color: Colors.deepPurple.shade700, size: 20),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Broadcast Requests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChefBroadcastRequestsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade50, Colors.purple.shade50],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.deepPurple.shade100),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.deepPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Customers broadcast requests to all nearby chefs. Send offers to win jobs!',
                      style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<CookingRequest>>(
                stream: DealNegotiationService.getChefNearbyRequests(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final requests = snapshot.data ?? [];

                  if (requests.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No active requests nearby',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Make sure you are online to receive requests',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      // Show count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${requests.length} Active Request${requests.length > 1 ? 's' : ''}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Show first 2 requests
                      ...requests.take(2).map((request) => _buildBroadcastRequestCard(request)),
                      if (requests.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+${requests.length - 2} more requests',
                            style: TextStyle(color: Colors.deepPurple.shade600, fontWeight: FontWeight.w500),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build a single broadcast request card
  Widget _buildBroadcastRequestCard(CookingRequest request) {
    final remainingMins = request.remainingTime.inMinutes;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Customer avatar
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.deepPurple.shade100,
            child: Text(
              request.customerName.isNotEmpty ? request.customerName[0].toUpperCase() : 'C',
              style: TextStyle(color: Colors.deepPurple.shade700, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      request.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: remainingMins < 10 ? Colors.red.shade100 : Colors.green.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${remainingMins}m left',
                        style: TextStyle(
                          fontSize: 11,
                          color: remainingMins < 10 ? Colors.red.shade700 : Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${request.serviceType} • ${request.date} at ${request.time}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${request.guestCount} guests',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    Text(
                      'Rs. ${request.offeredPrice}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade700,
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

  Widget _buildMiniStatCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {int badge = 0, VoidCallback? onSeeAll}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        if (onSeeAll != null)
          TextButton(
            onPressed: onSeeAll,
            child: const Text('See All'),
          ),
      ],
    );
  }


  Widget _buildPendingRequestsPreview() {
    final currentUid = _auth.currentUser?.uid;
    debugPrint('_buildPendingRequestsPreview: Chef UID = $currentUid');

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bookingRequests')
          .where('chefId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Error loading pending requests: ${snapshot.error}');
          return _buildEmptyCard(
            icon: Icons.error_outline,
            message: 'Error loading requests',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        debugPrint('_buildPendingRequestsPreview: Found ${snapshot.data?.docs.length ?? 0} requests');

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyCard(
            icon: Icons.inbox,
            message: 'No pending requests',
          );
        }

        // Sort locally by createdAt descending and limit to 3
        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime);
        });
        final limitedDocs = docs.take(3).toList();

        return Column(
          children: limitedDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            debugPrint('  Request ${doc.id}: chefId=${data['chefId']}, customer=${data['customerName']}');
            return _RequestCard(
              data: data,
              requestId: doc.id,
              onAccept: () => _acceptRequest(doc.id),
              onReject: () => _rejectRequest(doc.id),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildUpcomingBookingsPreview() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bookings')
          .where('chefId', isEqualTo: _auth.currentUser?.uid)
          .where('status', isEqualTo: 'confirmed')
          .orderBy('createdAt', descending: true)
          .limit(3)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyCard(
            icon: Icons.calendar_today,
            message: 'No upcoming bookings',
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _BookingCard(
              data: data,
              bookingId: doc.id,
              onComplete: () => _completeBooking(doc.id),
              onChat: () => _openChatWithCustomer(data, doc.id),
              onNavigate: () => _navigateToCustomer(data),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmptyCard({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }


  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(label),
          const Spacer(),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  // ===========================================
  // BOOKINGS TAB
  // ===========================================
  Widget _buildBookingsTab() {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pending'),
              Tab(text: 'Accepted'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildRequestsList('pending'),
                _buildBookingsList('confirmed'),
                _buildBookingsList('completed'),
                _buildBookingsList('cancelled'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bookingRequests')
          .where('chefId', isEqualTo: _auth.currentUser?.uid)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No $status requests',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _RequestCard(
              data: data,
              requestId: docs[index].id,
              onAccept: () => _acceptRequest(docs[index].id),
              onReject: () => _rejectRequest(docs[index].id),
            );
          },
        );
      },
    );
  }

  Widget _buildBookingsList(String status) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('bookings')
          .where('chefId', isEqualTo: _auth.currentUser?.uid)
          .where('status', isEqualTo: status)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No $status bookings',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _BookingCard(
              data: data,
              bookingId: docs[index].id,
              showComplete: status == 'confirmed',
              onComplete: status == 'confirmed'
                  ? () => _completeBooking(docs[index].id)
                  : null,
              onChat: status == 'confirmed'
                  ? () => _openChatWithCustomer(data, docs[index].id)
                  : null,
              onNavigate: status == 'confirmed'
                  ? () => _navigateToCustomer(data)
                  : null,
            );
          },
        );
      },
    );
  }

  // ===========================================
  // EARNINGS TAB
  // ===========================================
  Widget _buildEarningsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Commission Card (COD Model) - Pay via EasyPaisa
          _buildCommissionPaymentCard(),

          const SizedBox(height: 16),

          // Total Earnings Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade700],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'Total Earnings',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Rs. ${totalEarnings.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '$completedBookings',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Completed',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          completedBookings > 0
                              ? 'Rs. ${(totalEarnings / completedBookings).toStringAsFixed(0)}'
                              : 'Rs. 0',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Avg/Booking',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Recent Earnings
          const Text(
            'Recent Earnings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('bookings')
                .where('chefId', isEqualTo: _auth.currentUser?.uid)
                .where('status', isEqualTo: 'completed')
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              // Handle loading state
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              // Handle errors
              if (snapshot.hasError) {
                debugPrint('Recent Earnings Error: ${snapshot.error}');
                return _buildEmptyCard(
                  icon: Icons.error_outline,
                  message: 'Error loading earnings',
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyCard(
                  icon: Icons.receipt_long,
                  message: 'No completed bookings yet',
                );
              }

              // Sort by completedAt in memory (avoids needing composite index)
              final docs = snapshot.data!.docs.toList();
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = aData['completedAt'] as Timestamp?;
                final bTime = bData['completedAt'] as Timestamp?;
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime); // Descending
              });

              return Column(
                children: docs.take(10).map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final price = (data['price'] ?? data['total'] ?? 0).toDouble();
                  final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CachedChefAvatar(
                        imageUrl: data['customerImage'],
                        name: data['customerName'],
                        radius: 20,
                      ),
                      title: Text(data['customerName'] ?? 'Customer'),
                      subtitle: Text(
                        completedAt != null
                            ? '${completedAt.day}/${completedAt.month}/${completedAt.year}'
                            : data['date'] ?? '',
                      ),
                      trailing: Text(
                        'Rs. ${price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // View Full Report Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to Earnings tab (index 2)
                setState(() => _currentIndex = 2);
              },
              icon: const Icon(Icons.bar_chart),
              label: const Text('View Full Earnings Report'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================
  // COMMISSION PAYMENT CARD (COD Model)
  // ===========================================
  /// Commission card for chef to pay platform commission via EasyPaisa
  /// This implements the Cash on Delivery (COD) commission model:
  /// - Chef collects full cash from customer
  /// - Platform takes 10% commission
  /// - Chef pays commission separately via EasyPaisa
  Widget _buildCommissionPaymentCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_auth.currentUser?.uid).snapshots(),
      builder: (context, snapshot) {
        double pendingCommission = 0;
        double paidCommission = 0;
        bool paymentPending = false;
        bool shouldBlock = false;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          pendingCommission = (data?['commission_pending'] ?? 0.0).toDouble();
          paidCommission = (data?['commission_paid'] ?? 0.0).toDouble();
          paymentPending = data?['commission_payment_pending'] ?? false;
          shouldBlock = pendingCommission > 5000; // Block if > Rs. 5000
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pendingCommission > 0 ? Colors.orange.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: pendingCommission > 0 ? Colors.orange.shade300 : Colors.green.shade300,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        pendingCommission > 0 ? Icons.warning_amber_rounded : Icons.check_circle,
                        color: pendingCommission > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Platform Commission',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: pendingCommission > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: pendingCommission > 0 ? Colors.orange.shade100 : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '10%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: pendingCommission > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Pending and Paid Row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pending', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text(
                          'Rs. ${pendingCommission.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: pendingCommission > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: Colors.grey.shade300),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Total Paid', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text(
                            'Rs. ${paidCommission.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Warning if blocked
              if (shouldBlock) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New orders blocked! Pay commission to continue.',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Payment under review notice
              if (paymentPending) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_empty, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Payment under review',
                          style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Pay Commission Button
              if (pendingCommission > 0 && !paymentPending) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommissionPaymentScreen(
                            onBack: () => Navigator.pop(context),
                            onPaymentSuccess: () {
                              // Refresh will happen automatically via StreamBuilder
                            },
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('Pay Commission via EasyPaisa'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],

              // Info text
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Commission: 10% per order. Pay via EasyPaisa: 03439758616 (Ishtiaq Afzal)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ===========================================
  // REVIEWS TAB
  // ===========================================
  Widget _buildReviewsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rating Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade400, Colors.orange.shade600],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  reviewCount > 0 ? realRating.toStringAsFixed(1) : '0.0',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < realRating.round()
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.white,
                      size: 24,
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  '$reviewCount reviews',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Recent Reviews
          const Text(
            'Recent Reviews',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('reviews')
                .where('chefId', isEqualTo: _auth.currentUser?.uid)
                .orderBy('createdAt', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyCard(
                  icon: Icons.rate_review,
                  message: 'No reviews yet',
                );
              }

              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final rating = data['rating'] as int? ?? 5;
                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CachedChefAvatar(
                                imageUrl: data['customerImage'],
                                name: data['customerName'],
                                radius: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['customerName'] ?? 'Customer',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    if (createdAt != null)
                                      Text(
                                        '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(rating).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.star,
                                      size: 16,
                                      color: _getRatingColor(rating),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$rating',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _getRatingColor(rating),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (data['review'] != null && data['review'].toString().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              data['review'],
                              style: TextStyle(
                                color: Colors.grey[800],
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // View All Reviews Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to Reviews tab (index 3)
                setState(() => _currentIndex = 3);
              },
              icon: const Icon(Icons.reviews),
              label: const Text('View All Reviews'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRatingColor(int rating) {
    if (rating >= 4) return Colors.green;
    if (rating >= 3) return Colors.amber;
    return Colors.red;
  }

  // ===========================================
  // HELPER METHODS
  // ===========================================
  void _showAvailabilitySheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Availability Settings',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: (chefData?['isAvailable'] == true)
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          chefData?['isAvailable'] == true
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: chefData?['isAvailable'] == true
                              ? Colors.green
                              : Colors.grey,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chefData?['isAvailable'] == true
                                    ? 'You are Online'
                                    : 'You are Offline',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                chefData?['isAvailable'] == true
                                    ? 'Customers can send you booking requests'
                                    : 'You won\'t receive new booking requests',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: chefData?['isAvailable'] ?? false,
                          onChanged: (value) async {
                            await _toggleAvailability(value);
                            setModalState(() {});
                          },
                          activeTrackColor: Colors.green.shade200,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'When offline, your profile will be hidden from search results.',
                            style: TextStyle(fontSize: 12, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _acceptRequest(String requestId) async {
    final success = await BookingRequestService.acceptRequest(requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Booking accepted!' : 'Failed to accept'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) {
        _loadStats();
      }
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Request?'),
        content: const Text('Are you sure you want to reject this booking request?'),
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
      final success = await BookingRequestService.rejectRequest(requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Request rejected' : 'Failed to reject'),
            backgroundColor: success ? Colors.orange : Colors.red,
          ),
        );
        if (success) {
          _loadStats();
        }
      }
    }
  }

  Future<void> _completeBooking(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Completed?'),
        content: const Text('Are you sure the service has been completed?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await BookingRequestService.markBookingCompleted(bookingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Booking marked as completed!' : 'Failed'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) {
          _loadStats();
        }
      }
    }
  }

  /// Open chat with customer
  void _openChatWithCustomer(Map<String, dynamic> data, String bookingId) async {
    final chatId = data['chatId'] as String?;
    final customerName = data['customerName'] as String? ?? 'Customer';
    final customerImage = data['customerImage'] as String?;
    final customerId = data['customerId'] as String?;
    final requestId = data['requestId'] as String?;

    debugPrint('=== Opening Chat from Dashboard ===');
    debugPrint('chatId: $chatId, bookingId: $bookingId, customerId: $customerId');

    // Method 1: Use chatId directly if available
    if (chatId != null && chatId.isNotEmpty) {
      _navigateToChat(chatId, customerName, customerImage);
      return;
    }

    // Method 2: Search by bookingId
    if (bookingId.isNotEmpty) {
      try {
        final chatQuery = await _firestore
            .collection('chats')
            .where('bookingId', isEqualTo: bookingId)
            .limit(1)
            .get();

        if (chatQuery.docs.isNotEmpty) {
          _navigateToChat(chatQuery.docs.first.id, customerName, customerImage);
          return;
        }
      } catch (e) {
        debugPrint('Error searching by bookingId: $e');
      }
    }

    // Method 3: Search by requestId
    if (requestId != null && requestId.isNotEmpty) {
      try {
        final chatQuery = await _firestore
            .collection('chats')
            .where('requestId', isEqualTo: requestId)
            .limit(1)
            .get();

        if (chatQuery.docs.isNotEmpty) {
          _navigateToChat(chatQuery.docs.first.id, customerName, customerImage);
          return;
        }
      } catch (e) {
        debugPrint('Error searching by requestId: $e');
      }
    }

    // Method 4: Search by customerId and filter by chefId locally
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final currentChefId = _auth.currentUser?.uid;
        final chatQuery = await _firestore
            .collection('chats')
            .where('customerId', isEqualTo: customerId)
            .limit(10)
            .get();

        for (var doc in chatQuery.docs) {
          if (doc.data()['chefId'] == currentChefId) {
            _navigateToChat(doc.id, customerName, customerImage);
            return;
          }
        }
      } catch (e) {
        debugPrint('Error searching by customerId: $e');
      }
    }

    // No chat found
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat not available for this booking'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// Navigate to chat screen
  void _navigateToChat(String chatId, String customerName, String? customerImage) {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUserName: customerName,
            otherUserImage: customerImage,
            isChefView: true,
          ),
        ),
      );
    }
  }

  /// Navigate to customer location using map
  void _navigateToCustomer(Map<String, dynamic> bookingData) async {
    // Get customer location from booking data or Firestore
    double? lat;
    double? lng;

    // Try to get from booking data
    if (bookingData['customerLocation'] != null) {
      final loc = bookingData['customerLocation'];
      lat = (loc['lat'] ?? loc['latitude'])?.toDouble();
      lng = (loc['lng'] ?? loc['longitude'])?.toDouble();
    }

    // If not in booking, try to get from customer's user document
    if (lat == null || lng == null) {
      final customerId = bookingData['customerId'];
      if (customerId != null) {
        try {
          final customerDoc = await _firestore.collection('users').doc(customerId).get();
          if (customerDoc.exists) {
            final customerData = customerDoc.data();
            final location = customerData?['location'] ?? customerData?['liveLocation'];
            if (location != null) {
              lat = (location['lat'] ?? location['latitude'])?.toDouble();
              lng = (location['lng'] ?? location['longitude'])?.toDouble();
            }
          }
        } catch (e) {
          debugPrint('Error getting customer location: $e');
        }
      }
    }

    // Default to Peshawar if no location found
    lat ??= 34.0151;
    lng ??= 71.5249;

    // Get chef ID
    final chefId = _auth.currentUser?.uid;

    // Start chef's real-time location updates (InDrive style - every 3 seconds)
    if (chefId != null) {
      LocationService.startRealtimeLocationUpdates(chefId);

      // Show snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📍 Live location sharing started'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChefRouteMapScreen(
            customerLocation: LatLng(lat!, lng!),
            customerName: bookingData['customerName'] ?? 'Customer',
            customerAddress: bookingData['address'],
            isChefView: true,
          ),
        ),
      ).then((_) {
        // Stop location sharing when returning from map
        if (chefId != null) {
          LocationService.stopRealtimeLocationUpdates(chefId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📍 Live location sharing stopped'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      });
    }
  }
}

// ===========================================
// REQUEST CARD WIDGET
// ===========================================
class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String requestId;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  const _RequestCard({
    required this.data,
    required this.requestId,
    this.onAccept,
    this.onReject,
  });

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _isLoading = false;

  Future<void> _handleAccept() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    widget.onAccept?.call();
    // Don't reset loading - card will be removed from list
  }

  Future<void> _handleReject() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    widget.onReject?.call();
    // Don't reset loading - card will be removed from list
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CachedChefAvatar(
                  imageUrl: data['customerImage'],
                  name: data['customerName'],
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['customerName'] ?? 'Customer',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Text(
                        'New booking request',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Rs. ${data['offeredPrice'] ?? data['price'] ?? 0}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Details
            Row(
              children: [
                _buildDetail(Icons.calendar_today, data['date'] ?? '-'),
                const SizedBox(width: 24),
                _buildDetail(Icons.access_time, data['time'] ?? '-'),
                const SizedBox(width: 24),
                _buildDetail(Icons.people, '${data['guestCount'] ?? 0} guests'),
              ],
            ),

            if (data['address'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      data['address'],
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _handleReject,
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Reject', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _handleAccept,
                          icon: const Icon(Icons.check),
                          label: const Text('Accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
      ],
    );
  }
}

// ===========================================
// BOOKING CARD WIDGET
// ===========================================
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String bookingId;
  final bool showComplete;
  final VoidCallback? onComplete;
  final VoidCallback? onChat;
  final VoidCallback? onNavigate;

  const _BookingCard({
    required this.data,
    required this.bookingId,
    this.showComplete = false,
    this.onComplete,
    this.onChat,
    this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'confirmed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CachedChefAvatar(
                  imageUrl: data['customerImage'],
                  name: data['customerName'],
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['customerName'] ?? 'Customer',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        data['serviceType'] ?? 'Cooking Service',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(status),
              ],
            ),

            const SizedBox(height: 12),

            // Details
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildDetail(Icons.calendar_today, data['date'] ?? '-'),
                  _buildDetail(Icons.access_time, data['time'] ?? '-'),
                  _buildDetail(
                    Icons.payments,
                    'Rs. ${data['price'] ?? data['total'] ?? 0}',
                  ),
                ],
              ),
            ),

            // Actions for confirmed bookings
            if (status == 'confirmed' && (onComplete != null || onChat != null || onNavigate != null)) ...[
              const SizedBox(height: 12),
              // Navigate button - full width
              if (onNavigate != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Navigate to Customer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              if (onNavigate != null) const SizedBox(height: 8),
              Row(
                children: [
                  if (onChat != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onChat,
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('Chat'),
                      ),
                    ),
                  if (onChat != null && onComplete != null)
                    const SizedBox(width: 12),
                  if (onComplete != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onComplete,
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Mark Complete'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;

    switch (status) {
      case 'confirmed':
        color = Colors.green;
        text = 'Confirmed';
        break;
      case 'completed':
        color = Colors.blue;
        text = 'Completed';
        break;
      case 'cancelled':
        color = Colors.red;
        text = 'Cancelled';
        break;
      default:
        color = Colors.grey;
        text = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDetail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }
}

