import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomerProfileSetupScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const CustomerProfileSetupScreen({super.key, this.onComplete});

  @override
  State<CustomerProfileSetupScreen> createState() =>
      _CustomerProfileSetupScreenState();
}

class _CustomerProfileSetupScreenState
    extends State<CustomerProfileSetupScreen> {
  String step = "details"; // "details" or "phone-otp"

  final nameCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final cityCtrl = TextEditingController(text: "Lahore");
  final phoneCtrl = TextEditingController();
  final preferencesCtrl = TextEditingController();

  final List<TextEditingController> otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool isLoading = false;
  bool _loadingUserData = true;
  bool phoneVerified = false;
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    _loadExistingUserData();
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
          nameCtrl.text = data['name'];
        }
        // Pre-fill phone if available
        if (data['phone'] != null && data['phone'].toString().isNotEmpty) {
          phoneCtrl.text = data['phone'];
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => _loadingUserData = false);
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    addressCtrl.dispose();
    cityCtrl.dispose();
    phoneCtrl.dispose();
    preferencesCtrl.dispose();
    for (var controller in otpControllers) {
      controller.dispose();
    }
    for (var node in otpFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  bool canProceedToPhone() {
    return addressCtrl.text.isNotEmpty &&
           cityCtrl.text.isNotEmpty &&
           phoneCtrl.text.length >= 11;
  }

  // Directly save profile without OTP verification
  Future<void> handleContinue() async {
    if (!canProceedToPhone()) return;

    setState(() => isLoading = true);
    await _saveProfileAndComplete();
  }

  String getOtp() {
    return otpControllers.map((c) => c.text).join();
  }

  Future<void> handleSendPhoneOTP() async {
    if (phoneCtrl.text.length < 11) return;

    setState(() => isLoading = true);

    // Format phone number for Pakistan (+92)
    String phone = phoneCtrl.text.trim();
    if (phone.startsWith('0')) {
      phone = '+92${phone.substring(1)}';
    } else if (!phone.startsWith('+')) {
      phone = '+92$phone';
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (Android only)
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => isLoading = false);
          _showSnack('Verification failed: ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            isLoading = false;
            step = "phone-otp";
          });
          _showSnack('OTP sent to your phone');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => isLoading = false);
      _showSnack('Error: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Link phone to existing account
        await user.linkWithCredential(credential);
      }

      if (!mounted) return;
      await _saveProfileAndComplete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        // Phone already linked, proceed anyway
        await _saveProfileAndComplete();
      } else {
        setState(() => isLoading = false);
        _showSnack('Error: ${e.message}');
      }
    }
  }

  Future<void> _saveProfileAndComplete() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "id": uid,
        "uid": uid,  // Explicitly store Firebase Auth UID
        "role": "customer",
        "profileCompleted": true,
        "customerProfileComplete": true,
        "name": nameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "address": addressCtrl.text.trim(),
        "city": cityCtrl.text.trim(),
        "preferences": preferencesCtrl.text.trim(),
        "phoneVerified": false, // OTP verification disabled
        "createdAt": Timestamp.now(),
        "updatedAt": Timestamp.now(),
      }, SetOptions(merge: true));

      setState(() {
        isLoading = false;
        phoneVerified = true;
      });

      // Tell main.dart that profile is done
      if (widget.onComplete != null) widget.onComplete!();

    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        final msg = e is FirebaseException ? (e.message ?? e.code) : e.toString();
        _showSnack("Error: $msg");
      }
    }
  }

  Future<void> handleVerifyPhoneOTP() async {
    if (getOtp().length < 6) {
      _showSnack('Enter the 6-digit OTP');
      return;
    }

    if (_verificationId == null) {
      _showSnack('Please request OTP first');
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: getOtp(),
      );
      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      _showSnack('Invalid OTP: ${e.message}');
    } catch (e) {
      setState(() => isLoading = false);
      _showSnack('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUserData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    Navigator.of(context).maybePop();
                  },
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Complete Your Profile",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Help us personalize your experience",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _buildDetailsStep(),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: _buildDetailsFooter(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      children: [
        // Profile Icon
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: 48,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Address (Name is already collected during registration)
        _buildInputField(
          label: "Address *",
          controller: addressCtrl,
          placeholder: "House #, Street, Area",
          icon: Icons.location_on_outlined,
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // City
        _buildInputField(
          label: "City *",
          controller: cityCtrl,
          placeholder: "e.g., Lahore, Karachi, Islamabad",
          icon: Icons.location_city_outlined,
        ),
        const SizedBox(height: 16),

        // Phone Number
        _buildInputField(
          label: "Phone Number *",
          controller: phoneCtrl,
          placeholder: "03XX-XXXXXXX",
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          maxLength: 11,
        ),
        const SizedBox(height: 16),

        // Dietary Preferences
        _buildInputField(
          label: "Dietary Preferences (Optional)",
          controller: preferencesCtrl,
          placeholder: "Any dietary restrictions or preferences...",
          icon: Icons.restaurant_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 24),

        // Why we need this
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Why we need this?",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildInfoItem("Find chefs near you easily"),
              _buildInfoItem("Get personalized recommendations"),
              _buildInfoItem("Faster booking process"),
              _buildInfoItem("Direct communication with chefs"),
            ],
          ),
        ),
      ],
    );
  }

  // OTP step UI - kept for future use when phone verification is re-enabled
  // ignore: unused_element
  Widget _buildPhoneOtpStep() {
    return Column(
      children: [
        const SizedBox(height: 48),

        // Phone Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.phone_android,
            size: 32,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 16),

        const Text(
          "Verify Phone Number",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "We've sent a 6-digit code to ${phoneCtrl.text}",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // OTP Input
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
            return Container(
              width: 48,
              height: 56,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: otpControllers[index],
                focusNode: otpFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  counterText: "",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    ),
                  ),
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  if (value.isNotEmpty && index < 5) {
                    otpFocusNodes[index + 1].requestFocus();
                  }
                  if (value.isEmpty && index > 0) {
                    otpFocusNodes[index - 1].requestFocus();
                  }
                  setState(() {}); // Update button state
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 24),

        // Resend OTP
        Text(
          "Didn't receive the code?",
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        TextButton(
          onPressed: () {
            // Resend OTP logic
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("OTP resent!")),
            );
          },
          child: Text(
            "Resend OTP",
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canProceedToPhone() && !isLoading ? handleContinue : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isLoading ? "Saving..." : "Continue"),
          ),
        ),
      ],
    );
  }

  // OTP footer UI - kept for future use when phone verification is re-enabled
  // ignore: unused_element
  Widget _buildOtpFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: getOtp().length == 4 && !isLoading ? handleVerifyPhoneOTP : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isLoading ? "Verifying..." : "Verify & Start Exploring"),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            setState(() {
              step = "details";
              for (var c in otpControllers) {
                c.clear();
              }
            });
          },
          child: const Text("Change phone number"),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: placeholder,
            prefixIcon: Icon(icon, size: 20),
            counterText: "",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            helperText: helperText,
            helperStyle: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
