import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help & Support Screen
class HelpSupportScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const HelpSupportScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onBack,
              )
            : null,
        title: const Text('Help & Support'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withValues(alpha: 0.8),
                  ],
                ),
              ),
              child: const Column(
                children: [
                  Icon(Icons.support_agent, size: 60, color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'How can we help you?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'We\'re here to assist you',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Contact Options
            _buildSectionHeader(context, 'Contact Us'),
            _buildContactTile(
              context,
              icon: Icons.email,
              iconColor: Colors.blue,
              title: 'Email Support',
              subtitle: 'chefkart900@gmail.com',
              onTap: () => _launchEmail(context),
            ),
            _buildContactTile(
              context,
              icon: Icons.chat,
              iconColor: Colors.green,
              title: 'WhatsApp',
              subtitle: '0310 9887889',
              onTap: () => _launchWhatsApp(context),
            ),

            const Divider(height: 32),

            // FAQs
            _buildSectionHeader(context, 'Frequently Asked Questions'),
            _buildFaqTile(
              context,
              question: 'How do I book a chef?',
              answer: 'Browse chefs on the home screen, select a chef you like, and tap "Book Now". Fill in your requirements and send the request. The chef will respond to your booking.',
            ),
            _buildFaqTile(
              context,
              question: 'How do I cancel a booking?',
              answer: 'Go to My Bookings, find the booking you want to cancel, and tap the "Cancel" button. Note that cancellation policies may apply.',
            ),
            _buildFaqTile(
              context,
              question: 'How do payments work?',
              answer: 'Payment is made directly to the chef after the service is completed. You can pay via cash, bank transfer, or mobile wallets like JazzCash/Easypaisa.',
            ),
            _buildFaqTile(
              context,
              question: 'How do I become a chef on ChefKart?',
              answer: 'Register as a chef, complete your profile with your specialties and experience, upload required documents, and wait for verification. Once approved, you can start receiving booking requests.',
            ),
            _buildFaqTile(
              context,
              question: 'How are chefs verified?',
              answer: 'All chefs go through a verification process including ID verification, background check, and kitchen inspection to ensure quality and safety.',
            ),

            const Divider(height: 32),

            // App Info
            _buildSectionHeader(context, 'About'),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.info, color: Colors.grey[600], size: 24),
              ),
              title: const Text('App Version'),
              subtitle: const Text('1.0.0'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.description, color: Colors.grey[600], size: 24),
              ),
              title: const Text('Terms of Service'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showTerms(context),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.privacy_tip, color: Colors.grey[600], size: 24),
              ),
              title: const Text('Privacy Policy'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => _showPrivacyPolicy(context),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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

  Widget _buildContactTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildFaqTile(BuildContext context, {required String question, required String answer}) {
    return ExpansionTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.help_outline, color: Colors.orange, size: 20),
      ),
      title: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            answer,
            style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
          ),
        ),
      ],
    );
  }

  void _launchEmail(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'chefkart900@gmail.com',
      queryParameters: {'subject': 'ChefKart Support Request'},
    );
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app')),
        );
      }
    }
  }

  void _launchWhatsApp(BuildContext context) async {
    final Uri whatsappUri = Uri.parse('https://wa.me/923109887889?text=Hello, I need help with ChefKart');
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp')),
        );
      }
    }
  }

  void _showTerms(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms of Service'),
        content: SingleChildScrollView(
          child: Text(
            '''ChefKart Terms of Service

1. Acceptance of Terms
By using ChefKart, you agree to these terms and conditions.

2. Service Description
ChefKart connects customers with professional home chefs for cooking services.

3. User Responsibilities
- Provide accurate information
- Treat chefs and customers with respect
- Make payments as agreed

4. Chef Responsibilities
- Provide quality service
- Maintain hygiene standards
- Honor confirmed bookings

5. Cancellation Policy
- Cancellations should be made at least 24 hours in advance
- Late cancellations may incur fees

6. Liability
ChefKart facilitates connections but is not liable for the quality of services provided by chefs.

7. Privacy
Your data is handled according to our Privacy Policy.

8. Changes to Terms
We may update these terms from time to time.

For questions, contact chefkart900@gmail.com''',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: SingleChildScrollView(
          child: Text(
            '''ChefKart Privacy Policy

1. Information We Collect
- Personal information (name, email, phone)
- Location data
- Usage data

2. How We Use Your Information
- To provide our services
- To communicate with you
- To improve our app

3. Data Sharing
- We share necessary information with chefs/customers for bookings
- We do not sell your data to third parties

4. Data Security
We use industry-standard security measures to protect your data.

5. Your Rights
- Access your data
- Request deletion
- Opt out of marketing

6. Cookies
We use cookies to improve user experience.

7. Contact Us
For privacy concerns, contact chefkart900@gmail.com

Last updated: January 2026''',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
