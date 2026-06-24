import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Notification Settings Screen
class NotificationSettingsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const NotificationSettingsScreen({super.key, this.onBack});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  // Notification Preferences
  bool _pushEnabled = true;
  bool _bookingUpdates = true;
  bool _chatMessages = true;
  bool _promotions = false;
  bool _reminders = true;
  bool _sound = true;
  bool _vibration = true;

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
        final settings = data['notificationSettings'] as Map<String, dynamic>? ?? {};

        setState(() {
          _pushEnabled = settings['pushEnabled'] ?? true;
          _bookingUpdates = settings['bookingUpdates'] ?? true;
          _chatMessages = settings['chatMessages'] ?? true;
          _promotions = settings['promotions'] ?? false;
          _reminders = settings['reminders'] ?? true;
          _sound = settings['sound'] ?? true;
          _vibration = settings['vibration'] ?? true;
          _isLoading = false;
        });
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
        'notificationSettings': {
          'pushEnabled': _pushEnabled,
          'bookingUpdates': _bookingUpdates,
          'chatMessages': _chatMessages,
          'promotions': _promotions,
          'reminders': _reminders,
          'sound': _sound,
          'vibration': _vibration,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved!'),
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
        title: const Text('Notification Settings'),
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
                  // Master Toggle
                  _buildMasterToggle(),

                  const Divider(height: 1),

                  // Notification Categories
                  if (_pushEnabled) ...[
                    _buildSectionHeader('Notification Categories'),
                    _buildSettingTile(
                      icon: Icons.calendar_today,
                      iconColor: Colors.blue,
                      title: 'Booking Updates',
                      subtitle: 'Get notified when booking status changes',
                      value: _bookingUpdates,
                      onChanged: (value) => setState(() => _bookingUpdates = value),
                    ),
                    _buildSettingTile(
                      icon: Icons.chat_bubble,
                      iconColor: Colors.green,
                      title: 'Chat Messages',
                      subtitle: 'Get notified for new messages',
                      value: _chatMessages,
                      onChanged: (value) => setState(() => _chatMessages = value),
                    ),
                    _buildSettingTile(
                      icon: Icons.alarm,
                      iconColor: Colors.orange,
                      title: 'Reminders',
                      subtitle: 'Booking reminders before scheduled time',
                      value: _reminders,
                      onChanged: (value) => setState(() => _reminders = value),
                    ),
                    _buildSettingTile(
                      icon: Icons.local_offer,
                      iconColor: Colors.purple,
                      title: 'Promotions & Offers',
                      subtitle: 'Special deals and discounts',
                      value: _promotions,
                      onChanged: (value) => setState(() => _promotions = value),
                    ),

                    const Divider(height: 1),

                    // Sound & Vibration
                    _buildSectionHeader('Sound & Vibration'),
                    _buildSettingTile(
                      icon: Icons.volume_up,
                      iconColor: Colors.teal,
                      title: 'Sound',
                      subtitle: 'Play sound for notifications',
                      value: _sound,
                      onChanged: (value) => setState(() => _sound = value),
                    ),
                    _buildSettingTile(
                      icon: Icons.vibration,
                      iconColor: Colors.indigo,
                      title: 'Vibration',
                      subtitle: 'Vibrate for notifications',
                      value: _vibration,
                      onChanged: (value) => setState(() => _vibration = value),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Info Box
                  _buildInfoBox(),

                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildMasterToggle() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _pushEnabled
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _pushEnabled ? Colors.green : Colors.grey,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _pushEnabled ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _pushEnabled ? Icons.notifications_active : Icons.notifications_off,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Push Notifications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _pushEnabled ? Colors.green[800] : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _pushEnabled
                      ? 'You will receive push notifications'
                      : 'All notifications are turned off',
                  style: TextStyle(
                    fontSize: 13,
                    color: _pushEnabled ? Colors.green[600] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _pushEnabled,
            onChanged: (value) => setState(() => _pushEnabled = value),
            activeTrackColor: Colors.green.shade200,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
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
        onChanged: _pushEnabled ? onChanged : null,
        activeTrackColor: iconColor.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You can also manage notification permissions in your device settings.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

