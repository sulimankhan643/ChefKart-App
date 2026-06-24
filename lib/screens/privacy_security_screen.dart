import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';

/// Privacy & Security Settings Screen
class PrivacySecurityScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const PrivacySecurityScreen({super.key, this.onBack});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  // Privacy Settings
  bool _showPhone = true;
  bool _showLocation = true;
  bool _showOnlineStatus = true;
  bool _allowDirectMessages = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        final privacy = data['privacySettings'] as Map<String, dynamic>? ?? {};

        setState(() {
          _showPhone = privacy['showPhone'] ?? true;
          _showLocation = privacy['showLocation'] ?? true;
          _showOnlineStatus = privacy['showOnlineStatus'] ?? true;
          _allowDirectMessages = privacy['allowDirectMessages'] ?? true;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore.collection('users').doc(uid).update({
        'privacySettings': {
          'showPhone': _showPhone,
          'showLocation': _showLocation,
          'showOnlineStatus': _showOnlineStatus,
          'allowDirectMessages': _allowDirectMessages,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Privacy settings saved!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
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

  Future<void> _changePassword() async {
    final email = _auth.currentUser?.email;
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email associated with this account')),
      );
      return;
    }

    try {
      await _auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: Colors.green,
          ),
        );
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
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Delete Account'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete your account?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('This action cannot be undone. All your data will be permanently deleted including:'),
            SizedBox(height: 8),
            Text('• Profile information'),
            Text('• Booking history'),
            Text('• Chat messages'),
            Text('• Reviews and ratings'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Deleting account...'),
            ],
          ),
        ),
      );
    }

    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        // Delete user's chats
        try {
          final chatsAsCustomer = await _firestore
              .collection('chats')
              .where('customerId', isEqualTo: uid)
              .get();
          for (var doc in chatsAsCustomer.docs) {
            await doc.reference.delete();
          }

          final chatsAsChef = await _firestore
              .collection('chats')
              .where('chefId', isEqualTo: uid)
              .get();
          for (var doc in chatsAsChef.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting chats: $e');
        }

        // Delete user's bookings
        try {
          final bookingsAsCustomer = await _firestore
              .collection('bookings')
              .where('customerId', isEqualTo: uid)
              .get();
          for (var doc in bookingsAsCustomer.docs) {
            await doc.reference.delete();
          }

          final bookingsAsChef = await _firestore
              .collection('bookings')
              .where('chefId', isEqualTo: uid)
              .get();
          for (var doc in bookingsAsChef.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting bookings: $e');
        }

        // Delete user's notifications
        try {
          final notifications = await _firestore
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .get();
          for (var doc in notifications.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          debugPrint('Error deleting notifications: $e');
        }

        // Delete user data from Firestore
        await _firestore.collection('users').doc(uid).delete();

        // Delete Firebase Auth account
        await _auth.currentUser?.delete();

        // Close loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }

        // Sign out and navigate to login
        await _auth.signOut();

        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate to login page - clear all routes
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } on FirebaseAuthException catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (e.code == 'requires-recent-login') {
        if (mounted) {
          // Show re-authentication dialog
          final shouldReauth = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Re-authentication Required'),
              content: const Text(
                'For security, you need to sign in again before deleting your account.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Sign Out & Try Again'),
                ),
              ],
            ),
          );

          if (shouldReauth == true && mounted) {
            await _auth.signOut();
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        title: const Text('Privacy & Security'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Privacy Section
                  _buildSectionHeader('Privacy'),
                  _buildSettingTile(
                    icon: Icons.phone,
                    iconColor: Colors.blue,
                    title: 'Show Phone Number',
                    subtitle: 'Allow others to see your phone number',
                    value: _showPhone,
                    onChanged: (value) => setState(() => _showPhone = value),
                  ),
                  _buildSettingTile(
                    icon: Icons.location_on,
                    iconColor: Colors.green,
                    title: 'Show Location',
                    subtitle: 'Show your approximate location to others',
                    value: _showLocation,
                    onChanged: (value) => setState(() => _showLocation = value),
                  ),
                  _buildSettingTile(
                    icon: Icons.circle,
                    iconColor: Colors.teal,
                    title: 'Show Online Status',
                    subtitle: 'Let others see when you are online',
                    value: _showOnlineStatus,
                    onChanged: (value) => setState(() => _showOnlineStatus = value),
                  ),
                  _buildSettingTile(
                    icon: Icons.message,
                    iconColor: Colors.purple,
                    title: 'Allow Direct Messages',
                    subtitle: 'Allow others to send you direct messages',
                    value: _allowDirectMessages,
                    onChanged: (value) => setState(() => _allowDirectMessages = value),
                  ),

                  const Divider(height: 32),

                  // Security Section
                  _buildSectionHeader('Security'),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.lock, color: Colors.orange, size: 24),
                    ),
                    title: const Text('Change Password'),
                    subtitle: const Text('Send password reset email'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: _changePassword,
                  ),

                  const Divider(height: 32),

                  // Danger Zone
                  _buildSectionHeader('Danger Zone'),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.delete_forever, color: Colors.red),
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text('Permanently delete your account and data'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red),
                      onTap: _deleteAccount,
                    ),
                  ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: iconColor.withValues(alpha: 0.5),
      ),
    );
  }
}
