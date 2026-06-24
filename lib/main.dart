import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'firebase_options.dart';
import 'services/onesignal_service.dart';

import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/customer_profile_setup_screen.dart';
import 'screens/chef_profile_setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/complete_chef_dashboard_screen.dart';
import 'screens/chef_profile_screen.dart';
import 'screens/send_booking_request_screen.dart';
import 'screens/request_waiting_screen.dart';
import 'screens/create_broadcast_request_screen.dart';
import 'screens/view_offers_screen.dart';
import 'models/chef.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize OneSignal - MUST be in main() before runApp()
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize('d653679f-c733-47a3-ab38-8137ab806807');
  OneSignal.Notifications.requestPermission(true);
  debugPrint('✅ OneSignal initialized in main()');

  // Initialize Supabase for image storage
  await Supabase.initialize(
    url: 'https://zeoyrcdcpffulnemybhe.supabase.co',
    anonKey: 'sb_publishable_sHJjOM4XsUctk8hNxLBzwg_QjtEnj8i',
  );

  // Check if onboarding was completed before
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  runApp(ChefKartApp(onboardingCompleted: onboardingDone));
}

class ChefKartApp extends StatefulWidget {
  final bool onboardingCompleted;

  const ChefKartApp({super.key, this.onboardingCompleted = false});

  @override
  State<ChefKartApp> createState() => _ChefKartAppState();
}

class _ChefKartAppState extends State<ChefKartApp> {
  late bool onboardingDone;
  String? _currentMode; // 'customer' or 'chef'
  // Cache the profile future to avoid re-fetching on every rebuild
  Future<Map<String, dynamic>>? _profileFuture;
  String? _lastUid;

  @override
  void initState() {
    super.initState();
    onboardingDone = widget.onboardingCompleted;
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    setState(() => onboardingDone = true);
  }

  Future<Map<String, dynamic>> _fetchUserProfile(String uid) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      final authUser = FirebaseAuth.instance.currentUser;
      final defaultData = {
        'id': uid,  // Store document ID
        'uid': uid,  // Store Firebase Auth UID for chat queries
        'email': authUser?.email ?? '',
        'role': '',
        'currentMode': '',
        'profileCompleted': false,
        'customerProfileComplete': false,
        'chefProfileComplete': false,
      };
      await docRef.set(
        {
          ...defaultData,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return defaultData;
    }
    final data = snapshot.data() as Map<String, dynamic>;

    // Fix old users without uid field - ensures chat queries work correctly
    if (data['uid'] == null || data['id'] == null) {
      await docRef.update({
        'id': uid,
        'uid': uid,
      });
      data['id'] = uid;
      data['uid'] = uid;
    }

    data['role'] = data['role'] ?? '';
    data['currentMode'] = data['currentMode'] ?? data['role'] ?? '';
    data['profileCompleted'] = data['profileCompleted'] ?? false;
    data['customerProfileComplete'] = data['customerProfileComplete'] ?? false;
    data['chefProfileComplete'] = data['chefProfileComplete'] ?? false;

    // Login to OneSignal with role-based Player ID
    // Player ID will be saved under oneSignalPlayerIds.{currentMode}
    final currentMode = data['currentMode'] ?? data['role'] ?? '';
    if (currentMode.isNotEmpty) {
      await OneSignalService.loginUserWithRole(
        uid: uid,
        role: currentMode, // 'chef' or 'customer'
        email: data['email'],
        name: data['name'],
      );
    }

    return data;
  }

  /// Switch between Chef and Customer mode (InDrive style)
  /// Only updates currentMode, NOT the role field
  Future<void> _switchMode(String uid, String newMode) async {
    // Only update currentMode, NOT role (role stays as the original account type)
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'currentMode': newMode});

    // Update OneSignal - saves player ID for the new mode
    await OneSignalService.updateRoleAndSavePlayerId(uid, newMode);

    setState(() {
      _currentMode = newMode;
      _profileFuture = null; // Invalidate cache to refresh profile
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChefKart',
      theme: ThemeData(
        primaryColor: const Color(0xFFFF8C00), // Orange from logo
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8C00),
          primary: const Color(0xFFFF8C00), // Orange
          secondary: const Color(0xFF2B3A67), // Navy blue from logo
        ),
      ),
      home: _buildFlow(),
    );
  }

  Widget _buildFlow() {
    if (!onboardingDone) {
      return OnboardingScreen(
        onComplete: () {
          _completeOnboarding();
        },
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return AuthScreen(
            onAuthComplete: () {},
          );
        }

        final user = snapshot.data!;

        // Check if email is verified
        if (!user.emailVerified) {
          // Sign out and show auth screen with verification message
          return _EmailVerificationRequiredScreen(
            email: user.email ?? '',
            onBackToLogin: () async {
              await FirebaseAuth.instance.signOut();
            },
          );
        }

        final uid = user.uid;

        // Cache the future - only re-fetch if uid changes
        if (_lastUid != uid || _profileFuture == null) {
          _lastUid = uid;
          _profileFuture = _fetchUserProfile(uid);
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: _profileFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (snap.hasError || !snap.hasData) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Unable to load your profile. Please try again.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snap.data!;
            final role = data["role"] ?? '';
            final currentMode = _currentMode ?? data["currentMode"] ?? role;
            final customerProfileComplete = data["customerProfileComplete"] ?? false;
            final chefProfileComplete = data["chefProfileComplete"] ?? false;

            // If no role selected, show role selection
            if (role.isEmpty) {
              return RoleSelectionScreen(
                onRoleSelected: (selectedRole) async {
                  await FirebaseFirestore.instance
                      .collection("users")
                      .doc(uid)
                      .update({
                    "role": selectedRole,
                    "currentMode": selectedRole,
                  });
                  setState(() {
                    _currentMode = selectedRole;
                    _profileFuture = null;
                  });
                },
              );
            }

            // Check profile completion based on current mode
            if (currentMode == "customer" && !customerProfileComplete) {
              return CustomerProfileSetupScreen(
                onComplete: () async {
                  await FirebaseFirestore.instance
                      .collection("users")
                      .doc(uid)
                      .update({
                    "customerProfileComplete": true,
                    "profileCompleted": true,
                  });
                  setState(() => _profileFuture = null);
                },
              );
            }

            if (currentMode == "chef" && !chefProfileComplete) {
              return ChefProfileSetupScreen(
                onComplete: () async {
                  await FirebaseFirestore.instance
                      .collection("users")
                      .doc(uid)
                      .update({
                    "chefProfileComplete": true,
                    "profileCompleted": true,
                  });
                  setState(() => _profileFuture = null);
                },
              );
            }

            // Show dashboard based on current mode
            if (currentMode == "customer") {
              return _CustomerDashboard(
                uid: uid,
                onSwitchToChef: () => _switchMode(uid, 'chef'),
              );
            }

            return CompleteChefDashboardScreen(
              // Always allow switching to customer mode - will show profile setup if not complete
              onSwitchToCustomer: () => _switchMode(uid, 'customer'),
            );
          },
        );
      },
    );
  }
}

/// Customer Dashboard with proper navigation for booking flow
class _CustomerDashboard extends StatefulWidget {
  final String uid;
  final VoidCallback onSwitchToChef;

  const _CustomerDashboard({
    required this.uid,
    required this.onSwitchToChef,
  });

  @override
  State<_CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<_CustomerDashboard> {
  String _currentScreen = 'home';
  Chef? _selectedChef;
  String? _pendingRequestId;

  void _navigateTo(String screen, {Chef? chef, String? requestId}) {
    setState(() {
      _currentScreen = screen;
      if (chef != null) _selectedChef = chef;
      if (requestId != null) _pendingRequestId = requestId;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentScreen) {
      case 'chef_profile':
        if (_selectedChef == null) {
          return HomeScreen(
            onChefSelect: (chef) => _navigateTo('chef_profile', chef: chef),
            onSwitchToChef: widget.onSwitchToChef,
            onFindChef: () => _navigateTo('broadcast_request'),
            onViewOffers: (requestId) => _navigateTo('view_offers', requestId: requestId),
          );
        }
        return ChefProfileScreen(
          chef: _selectedChef!,
          onBack: () => _navigateTo('home'),
          onBook: () => _navigateTo('send_request'),
        );

      case 'send_request':
        if (_selectedChef == null) {
          return HomeScreen(
            onChefSelect: (chef) => _navigateTo('chef_profile', chef: chef),
            onSwitchToChef: widget.onSwitchToChef,
            onFindChef: () => _navigateTo('broadcast_request'),
            onViewOffers: (requestId) => _navigateTo('view_offers', requestId: requestId),
          );
        }
        return SendBookingRequestScreen(
          chef: _selectedChef!,
          onBack: () => _navigateTo('chef_profile'),
          onRequestSent: (requestId) => _navigateTo('waiting', requestId: requestId),
        );

      case 'waiting':
        if (_pendingRequestId == null) {
          return HomeScreen(
            onChefSelect: (chef) => _navigateTo('chef_profile', chef: chef),
            onSwitchToChef: widget.onSwitchToChef,
            onFindChef: () => _navigateTo('broadcast_request'),
            onViewOffers: (requestId) => _navigateTo('view_offers', requestId: requestId),
          );
        }
        return RequestWaitingScreen(
          requestId: _pendingRequestId!,
          onBack: () => _navigateTo('home'),
          onAccepted: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Booking Accepted! Check My Bookings.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            _navigateTo('home');
          },
          onRejected: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('😔 Chef is not available. Try another chef.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            _navigateTo('home');
          },
        );

      // InDrive-style broadcast request flow
      case 'broadcast_request':
        return CreateBroadcastRequestScreen(
          onBack: () => _navigateTo('home'),
          onRequestCreated: (requestId) => _navigateTo('view_offers', requestId: requestId),
        );

      case 'view_offers':
        if (_pendingRequestId == null) {
          return HomeScreen(
            onChefSelect: (chef) => _navigateTo('chef_profile', chef: chef),
            onSwitchToChef: widget.onSwitchToChef,
            onFindChef: () => _navigateTo('broadcast_request'),
            onViewOffers: (requestId) => _navigateTo('view_offers', requestId: requestId),
          );
        }
        return ViewOffersScreen(
          requestId: _pendingRequestId!,
          onBack: () => _navigateTo('home'),
          onConfirmed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Chef Confirmed! Check My Bookings for details.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            _navigateTo('home');
          },
          onExpired: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ Request expired. Please try again.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
            _navigateTo('home');
          },
        );


      default:
        return HomeScreen(
          onChefSelect: (chef) => _navigateTo('chef_profile', chef: chef),
          onSwitchToChef: widget.onSwitchToChef,
          onFindChef: () => _navigateTo('broadcast_request'),
          onViewOffers: (requestId) => _navigateTo('view_offers', requestId: requestId),
        );
    }
  }
}

/// Screen shown when user is logged in but email is not verified
class _EmailVerificationRequiredScreen extends StatefulWidget {
  final String email;
  final VoidCallback onBackToLogin;

  const _EmailVerificationRequiredScreen({
    required this.email,
    required this.onBackToLogin,
  });

  @override
  State<_EmailVerificationRequiredScreen> createState() => _EmailVerificationRequiredScreenState();
}

class _EmailVerificationRequiredScreenState extends State<_EmailVerificationRequiredScreen> {
  bool _isResending = false;
  bool _isChecking = false;

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResending = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent! Check your inbox.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send email: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _checkVerification() async {
    setState(() => _isChecking = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;
        if (refreshedUser != null && refreshedUser.emailVerified) {
          // Update Firestore to mark email as verified
          await FirebaseFirestore.instance
              .collection('users')
              .doc(refreshedUser.uid)
              .update({'emailVerified': true});

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email verified successfully!'),
                backgroundColor: Colors.green,
              ),
            );
          }
          // The StreamBuilder will automatically update
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Email not yet verified. Please check your inbox.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Verification Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mark_email_unread_outlined,
                        size: 48,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Verify Your Email',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We sent a verification link to:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.email,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Please click the link in your email to verify your account and continue.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // Check Verification Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isChecking ? null : _checkVerification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isChecking
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'I\'ve Verified My Email',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Resend Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isResending ? null : _resendVerificationEmail,
                        icon: _isResending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_isResending ? 'Sending...' : 'Resend Email'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Back to Login
                    TextButton(
                      onPressed: widget.onBackToLogin,
                      child: const Text('Sign Out & Use Different Account'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
