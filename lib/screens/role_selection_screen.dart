import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'chef_profile_setup_screen.dart';
import 'customer_profile_setup_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  final ValueChanged<String>? onRoleSelected;
  final VoidCallback? onBack;
  const RoleSelectionScreen({super.key, this.onRoleSelected, this.onBack});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _saving = false;
  String? _pendingRole;

  Future<void> _handleInternalSelection(String role) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login first')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _pendingRole = role;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'role': role,
          'profileCompleted': false,
          'updatedAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      if (role == 'chef') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const ChefProfileSetupScreen(),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const CustomerProfileSetupScreen(),
          ),
        );
      }
    } catch (e) {
      final msg = e is FirebaseException ? (e.message ?? e.code) : e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $msg')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _pendingRole = null;
        });
      }
    }
  }

  void _onRoleTap(String role) {
    if (_saving) return;

    if (widget.onRoleSelected != null) {
      widget.onRoleSelected!(role);
    } else {
      _handleInternalSelection(role);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.outlineVariant;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: widget.onBack ?? () {
                      // Default back: sign out and go back
                      FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.restaurant_menu,
                      color: theme.colorScheme.onPrimary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome to ChefKart!',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose your role to continue',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _RoleCard(
                      title: "I'm a Customer",
                      description:
                          'Book verified chefs for home cooking, events, and special occasions.',
                      highlights: const [
                        'Find nearby verified chefs',
                        'Filter by cuisine and preferences',
                        'Easy booking and local payments',
                      ],
                      icon: Icons.person_outline,
                      iconColor: theme.colorScheme.primary,
                      badgeColor: theme.colorScheme.secondary,
                      borderColor: dividerColor,
                      onTap: () => _onRoleTap('customer'),
                      busy: _saving && _pendingRole == 'customer',
                    ),
                    const SizedBox(height: 16),
                    _RoleCard(
                      title: "I'm a Chef",
                      description:
                          'Offer your culinary services and earn from home cooking.',
                      highlights: const [
                        'Create professional profile',
                        'Manage bookings and availability',
                        'Earn with flexible schedule',
                      ],
                      icon: Icons.emoji_food_beverage_outlined,
                      iconColor: theme.colorScheme.secondary,
                      badgeColor: theme.colorScheme.primary,
                      borderColor: dividerColor,
                      onTap: () => _onRoleTap('chef'),
                      busy: _saving && _pendingRole == 'chef',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Text(
                'You can always switch roles later in your profile settings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String description;
  final List<String> highlights;
  final IconData icon;
  final Color iconColor;
  final Color badgeColor;
  final Color borderColor;
  final VoidCallback onTap;
  final bool busy;

  const _RoleCard({
    required this.title,
    required this.description,
    required this.highlights,
    required this.icon,
    required this.iconColor,
    required this.badgeColor,
    required this.borderColor,
    required this.onTap,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.colorScheme.surface;

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: busy ? theme.colorScheme.primary : borderColor,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy)
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...highlights.map(
              (point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6, right: 12),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: busy ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Select',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 16, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
