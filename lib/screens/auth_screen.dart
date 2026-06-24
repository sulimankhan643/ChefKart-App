import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthComplete;
  final VoidCallback? onBack;

  const AuthScreen({super.key, this.onAuthComplete, this.onBack});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, signup, forgotPassword, emailVerificationPending }
enum _SelectedRole { customer, chef }

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmPasswordCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isResendingVerification = false;
  _AuthMode _mode = _AuthMode.login;
  _SelectedRole _selectedRole = _SelectedRole.customer; // Default role
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _pendingVerificationEmail;

  @override
  void initState() {
    super.initState();
    _checkPendingVerification();
  }

  // Check if there's a pending email verification from previous session
  Future<void> _checkPendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingEmail = prefs.getString('pending_verification_email');
    if (pendingEmail != null && pendingEmail.isNotEmpty) {
      setState(() {
        _pendingVerificationEmail = pendingEmail;
        _mode = _AuthMode.emailVerificationPending;
      });
    }
  }

  // Save pending verification email to persist across rebuilds
  Future<void> _savePendingVerification(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_verification_email', email);
  }

  // Clear pending verification when user logs in or cancels
  Future<void> _clearPendingVerification() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_verification_email');
  }

  bool get _isValidEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_emailCtrl.text.trim());


  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    // Clear any existing snackbars first
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ==================== EMAIL LOGIN ====================
  Future<void> _handleEmailLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || !_isValidEmail) {
      _showSnack('Please enter a valid email', isError: true);
      return;
    }
    if (password.isEmpty) {
      _showSnack('Please enter your password', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Try to login directly with Firebase Auth
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Check if email is verified
      if (credential.user != null && !credential.user!.emailVerified) {
        // Sign out the user since email is not verified
        await FirebaseAuth.instance.signOut();
        await _savePendingVerification(email);
        if (mounted) {
          setState(() {
            _pendingVerificationEmail = email;
            _mode = _AuthMode.emailVerificationPending;
          });
        }
        return;
      }

      // Clear any pending verification
      await _clearPendingVerification();

      _showSnack('Login successful!');
      widget.onAuthComplete?.call();
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code}');
      if (mounted) {
        setState(() => _isLoading = false);
        _showLoginErrorMessage(e.code);
      }
      return;
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnack('Login failed. Please try again.', isError: true);
      }
      return;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // Show login error message based on error code
  void _showLoginErrorMessage(String errorCode) {
    String message;

    switch (errorCode) {
      case 'user-not-found':
      case 'USER_NOT_FOUND':
        message = 'Account doesn\'t exist.';
        break;
      case 'wrong-password':
      case 'WRONG_PASSWORD':
        message = 'Wrong password.';
        break;
      case 'invalid-credential':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'invalid-login-credentials':
        message = 'Account doesn\'t exist or wrong password.';
        break;
      case 'too-many-requests':
        message = 'Too many attempts. Try later.';
        break;
      case 'user-disabled':
        message = 'Account disabled.';
        break;
      case 'network-request-failed':
        message = 'Network error.';
        break;
      default:
        message = 'Login failed.';
    }

    _showSnack(message, isError: true);
  }


  // ==================== EMAIL SIGNUP ====================
  Future<void> _handleSignUp() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirmPassword = _confirmPasswordCtrl.text.trim();

    if (name.isEmpty) {
      _showSnack('Please enter your name', isError: true);
      return;
    }
    if (email.isEmpty || !_isValidEmail) {
      _showSnack('Please enter a valid email', isError: true);
      return;
    }
    if (password.isEmpty || password.length < 6) {
      _showSnack('Password must be at least 6 characters', isError: true);
      return;
    }
    if (password != confirmPassword) {
      _showSnack('Passwords do not match', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Send email verification
      await credential.user!.sendEmailVerification();

      // Get selected role
      final roleString = _selectedRole == _SelectedRole.chef ? 'chef' : 'customer';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'id': credential.user!.uid,  // Store document ID
        'uid': credential.user!.uid,  // Store Firebase Auth UID for chat queries
        'name': name,
        'email': email,
        'role': roleString,
        'currentMode': roleString, // InDrive-style: current active mode
        'customerProfileComplete': false,
        'chefProfileComplete': false,
        'profileCompleted': false,
        'emailVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Sign out the user until they verify their email
      await FirebaseAuth.instance.signOut();

      // Save pending verification to persist across rebuilds
      await _savePendingVerification(email);

      // Show verification pending screen
      setState(() {
        _pendingVerificationEmail = email;
        _mode = _AuthMode.emailVerificationPending;
      });
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _showSnack('Sign up failed. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== RESEND VERIFICATION EMAIL ====================
  Future<void> _handleResendVerification() async {
    if (_pendingVerificationEmail == null) return;

    setState(() => _isResendingVerification = true);

    try {
      // We need to sign in temporarily to resend verification
      final password = _passwordCtrl.text.trim();
      if (password.isEmpty) {
        _showSnack('Please enter your password to resend verification', isError: true);
        setState(() => _isResendingVerification = false);
        return;
      }

      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _pendingVerificationEmail!,
        password: password,
      );

      await credential.user!.sendEmailVerification();
      await FirebaseAuth.instance.signOut();

      _showSnack('Verification email sent! Check your inbox.');
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } catch (e) {
      _showSnack('Failed to resend verification email.', isError: true);
    } finally {
      if (mounted) setState(() => _isResendingVerification = false);
    }
  }

  // ==================== HANDLE AUTH ERRORS ====================
  void _handleAuthError(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'user-not-found':
        message = 'Account not found. Please create a new account.';
        break;
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Incorrect password. Please try again.';
        break;
      case 'email-already-in-use':
        message = 'Account already exists. Please login.';
        break;
      case 'weak-password':
        message = 'Password is too weak. Use at least 6 characters.';
        break;
      case 'invalid-email':
        message = 'Invalid email address format.';
        break;
      case 'too-many-requests':
        message = 'Too many attempts. Please try again later.';
        break;
      case 'user-disabled':
        message = 'This account has been disabled.';
        break;
      case 'operation-not-allowed':
        message = 'Email/password sign-in is not enabled.';
        break;
      default:
        message = e.message ?? 'Authentication failed. Please try again.';
    }
    _showSnack(message, isError: true);
  }

  // ==================== FORGOT PASSWORD ====================
  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty || !_isValidEmail) {
      _showSnack('Please enter a valid email', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnack('Password reset email sent! Check your inbox.');
      setState(() => _mode = _AuthMode.login);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showSnack('No account found with this email.', isError: true);
      } else {
        _showSnack('Failed to send reset email: ${e.message}', isError: true);
      }
    } catch (e) {
      _showSnack('Failed to send reset email.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== GOOGLE SIGN-IN ====================
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);

    GoogleSignInAccount? googleUser;

    try {
      // Step 1: Initialize GoogleSignIn with serverClientId and scopes
      // serverClientId (Web Client ID) is REQUIRED to get idToken for Firebase Auth
      debugPrint('Google Sign-In: Step 1 - Initializing...');
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: '329240607872-u53q53opa097hqbpmq41b1gr62n9d2ij.apps.googleusercontent.com',
      );

      // Disconnect any previous session to ensure fresh tokens
      try {
        await googleSignIn.disconnect();
      } catch (_) {}

      // Step 2: Trigger sign-in
      debugPrint('Google Sign-In: Step 2 - Triggering sign-in flow...');
      googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        debugPrint('Google Sign-In: User cancelled');
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      debugPrint('Google Sign-In: Step 3 - Got user: ${googleUser.email}');

      // Step 3: Get authentication tokens
      debugPrint('Google Sign-In: Step 4 - Getting authentication...');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      debugPrint('Google Sign-In: Step 5 - Tokens: accessToken=${googleAuth.accessToken != null}, idToken=${googleAuth.idToken != null}');

      // Check if we have at least one token
      if (googleAuth.accessToken == null && googleAuth.idToken == null) {
        debugPrint('Google Sign-In: ERROR - No tokens received at all');
        _showSnack('Authentication failed. No token received.', isError: true);
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      // Step 4: Create Firebase credential (idToken is preferred but accessToken also works)
      debugPrint('Google Sign-In: Step 6 - Creating Firebase credential...');
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Step 5: Sign in to Firebase
      debugPrint('Google Sign-In: Step 7 - Signing in to Firebase...');
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      debugPrint('Google Sign-In: Step 8 - Firebase auth successful: ${user?.uid}');

      if (user == null) {
        _showSnack('Google sign-in failed. Please try again.', isError: true);
        return;
      }

      // Step 6: Check/Create user document
      debugPrint('Google Sign-In: Step 9 - Checking user document...');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('Google Sign-In: Step 10 - Creating new user...');
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'name': user.displayName ?? '',
          'profileImage': user.photoURL ?? '',
          'role': _selectedRole == _SelectedRole.chef ? 'chef' : 'customer',
          'isProfileComplete': false,
          'createdAt': FieldValue.serverTimestamp(),
          'authProvider': 'google',
        });
        _showSnack('Account created successfully!');
      } else {
        _showSnack('Welcome back!');
      }

      await _clearPendingVerification();
      debugPrint('Google Sign-In: SUCCESS - Navigating to home...');
      widget.onAuthComplete?.call();

    } on FirebaseAuthException catch (e) {
      debugPrint('Google Sign-In: FirebaseAuthException: ${e.code} - ${e.message}');

      String errorMessage;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          errorMessage = 'This email is already registered with a different method.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid credential. Please try again.';
          break;
        case 'operation-not-allowed':
          errorMessage = 'Google Sign-In is not enabled in Firebase. Contact admin.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        default:
          errorMessage = 'Authentication failed: ${e.message}';
      }
      _showSnack(errorMessage, isError: true);

    } catch (e, stackTrace) {
      debugPrint('Google Sign-In: EXCEPTION: $e');
      debugPrint('Google Sign-In: Stack: $stackTrace');

      String errorMessage = 'Google sign-in failed.';
      String errorStr = e.toString().toLowerCase();

      if (errorStr.contains('apiexception: 10') || errorStr.contains('developer_error')) {
        errorMessage = 'Configuration error (SHA-1 mismatch). Contact developer.';
      } else if (errorStr.contains('apiexception: 12500')) {
        errorMessage = 'Google Play Services needs update.';
      } else if (errorStr.contains('apiexception: 7') || errorStr.contains('network')) {
        errorMessage = 'Network error. Check your internet connection.';
      } else if (errorStr.contains('sign_in_canceled') || errorStr.contains('canceled')) {
        errorMessage = 'Sign-in was cancelled.';
      } else if (errorStr.contains('sign_in_failed')) {
        errorMessage = 'Sign-in failed. Check Firebase Google Sign-In is enabled.';
      }

      _showSnack(errorMessage, isError: true);
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _clearFields() {
    _passwordCtrl.clear();
    _confirmPasswordCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 120,
                  height: 120,
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
                const SizedBox(height: 16),
                Text(
                  'ChefKart',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _mode == _AuthMode.login
                      ? 'Login to your account'
                      : _mode == _AuthMode.signup
                          ? 'Create a new account'
                          : _mode == _AuthMode.emailVerificationPending
                              ? 'Verify your email'
                              : 'Reset your password',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),

                // Form Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Email Verification Pending UI
                      if (_mode == _AuthMode.emailVerificationPending) ...[
                        // Email Icon with animation effect
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.green.shade200, width: 2),
                          ),
                          child: Icon(
                            Icons.mark_email_read_outlined,
                            size: 36,
                            color: Colors.green.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        const Text(
                          'Verify Your Email',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtitle
                        Text(
                          'We sent a verification link to',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Email address
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _pendingVerificationEmail ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Instructions
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Click the link in your email to verify your account',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // I've Verified Button (Primary)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () async {
                                    await _clearPendingVerification();
                                    setState(() {
                                      _emailCtrl.text = _pendingVerificationEmail ?? '';
                                      _pendingVerificationEmail = null;
                                      _mode = _AuthMode.login;
                                    });
                                    _showSnack('Great! Now you can log in.');
                                  },
                            icon: const Icon(Icons.check_circle_outline, size: 20),
                            label: const Text(
                              'I\'ve Verified My Email',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider with text
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Didn\'t receive email?',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Password field for resend
                        TextField(
                          controller: _passwordCtrl,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Enter password to resend',
                            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                            prefixIcon: Icon(Icons.lock_outline, size: 20, color: Colors.grey.shade600),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Resend button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _isResendingVerification ? null : _handleResendVerification,
                            icon: _isResendingVerification
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.blue.shade600,
                                    ),
                                  )
                                : Icon(Icons.send_outlined, size: 18, color: Colors.blue.shade600),
                            label: Text(
                              _isResendingVerification ? 'Sending...' : 'Resend Verification Email',
                              style: TextStyle(fontSize: 14, color: Colors.blue.shade600),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.blue.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Phone login removed - email only login

                      // Name field (only for signup)
                      if (_mode == _AuthMode.signup) ...[
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            hintText: 'Full Name',
                            prefixIcon: const Icon(Icons.person_outline, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // EMAIL LOGIN FORM - email only (phone login removed)
                      if (_mode == _AuthMode.login || _mode == _AuthMode.signup || _mode == _AuthMode.forgotPassword) ...[
                        // Email field
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Email address',
                            prefixIcon: const Icon(Icons.email_outlined, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),

                        // Password fields (not for forgot password)
                        if (_mode != _AuthMode.forgotPassword) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ],

                        // Confirm password (only for signup)
                        if (_mode == _AuthMode.signup) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _confirmPasswordCtrl,
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              hintText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_outline, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Role Selection (InDrive Style)
                          const Text(
                            'I want to join as:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedRole = _SelectedRole.customer),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _selectedRole == _SelectedRole.customer
                                            ? Theme.of(context).primaryColor
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.person,
                                            size: 22,
                                            color: _selectedRole == _SelectedRole.customer
                                                ? Colors.white
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Customer',
                                            style: TextStyle(
                                              color: _selectedRole == _SelectedRole.customer
                                                  ? Colors.white
                                                  : Colors.grey.shade600,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _selectedRole = _SelectedRole.chef),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _selectedRole == _SelectedRole.chef
                                            ? const Color(0xFFFF6B35)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.restaurant_menu,
                                            size: 22,
                                            color: _selectedRole == _SelectedRole.chef
                                                ? Colors.white
                                                : Colors.grey.shade600,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Chef',
                                            style: TextStyle(
                                              color: _selectedRole == _SelectedRole.chef
                                                  ? Colors.white
                                                  : Colors.grey.shade600,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Forgot password link (only for email login)
                        if (_mode == _AuthMode.login) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                _clearFields();
                                setState(() => _mode = _AuthMode.forgotPassword);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],

                      // Phone login removed - email only

                      const SizedBox(height: 12),

                      // Main action button
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _getMainAction(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _getButtonText(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Divider with OR
                if (_mode != _AuthMode.forgotPassword && _mode != _AuthMode.emailVerificationPending) ...[
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade400)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade400)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Google Sign-In Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isGoogleLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.grey.shade600,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Google Logo
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Image.network(
                                    'https://www.google.com/favicon.ico',
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.g_mobiledata,
                                      size: 24,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  _mode == _AuthMode.login
                                      ? 'Continue with Google'
                                      : 'Sign up with Google',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Create new account / Login button
                if (_mode == _AuthMode.login)
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () {
                        _clearFields();
                        setState(() => _mode = _AuthMode.signup);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Create New Account',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else if (_mode != _AuthMode.emailVerificationPending)
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton(
                      onPressed: () async {
                        _clearFields();
                        await _clearPendingVerification();
                        setState(() {
                          _pendingVerificationEmail = null;
                          _mode = _AuthMode.login;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                        side: BorderSide(
                          color: Theme.of(context).primaryColor,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Already have an account? Log In',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  VoidCallback? _getMainAction() {
    if (_mode == _AuthMode.login) {
      return _handleEmailLogin;
    } else if (_mode == _AuthMode.signup) {
      return _handleSignUp;
    } else if (_mode == _AuthMode.emailVerificationPending) {
      return null; // Buttons handled separately in the UI
    } else {
      return _handleForgotPassword;
    }
  }

  String _getButtonText() {
    if (_mode == _AuthMode.login) {
      return 'Log In';
    } else if (_mode == _AuthMode.signup) {
      return 'Sign Up';
    } else if (_mode == _AuthMode.emailVerificationPending) {
      return 'Verify Email';
    } else {
      return 'Send Reset Link';
    }
  }
}
