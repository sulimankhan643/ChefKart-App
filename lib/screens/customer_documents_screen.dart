import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_storage_service.dart';
import '../widgets/cached_chef_image.dart';

/// Customer Documents Screen - Upload and manage verification documents
/// Same as ChefDocumentsScreen but for customers
class CustomerDocumentsScreen extends StatefulWidget {
  final VoidCallback? onSave;
  final VoidCallback? onBack;

  const CustomerDocumentsScreen({super.key, this.onSave, this.onBack});

  @override
  State<CustomerDocumentsScreen> createState() => _CustomerDocumentsScreenState();
}

class _CustomerDocumentsScreenState extends State<CustomerDocumentsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imagePicker = ImagePicker();

  bool _isLoading = true;

  // Document state
  String? _cnicUrl;
  File? _cnicImage;
  Uint8List? _cnicWebBytes;
  bool _cnicUploading = false;

  // Verification status
  String _verificationStatus = 'not_submitted'; // not_submitted, pending, verified, rejected
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _cnicUrl = data['cnicUrl'];
          _verificationStatus = data['verificationStatus'] ?? 'not_submitted';
          _rejectionReason = data['verificationRejectionReason'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading documents: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
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
              const SizedBox(height: 20),
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
                    _selectImage(ImageSource.camera);
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
                  _selectImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (pickedFile == null) return;

      setState(() => _cnicUploading = true);

      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        _showSnack('Please login first');
        _resetUploadingState();
        return;
      }

      String? downloadUrl;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        _cnicWebBytes = bytes;
        downloadUrl = await SupabaseStorageService.uploadCNIC(
          bytes: bytes,
          userId: uid,
        );
      } else {
        final file = File(pickedFile.path);
        _cnicImage = file;
        downloadUrl = await SupabaseStorageService.uploadCNIC(
          file: file,
          userId: uid,
        );
      }

      if (downloadUrl != null) {
        // Save to Firestore
        await _firestore.collection('users').doc(uid).update({
          'cnicUrl': downloadUrl,
          'verificationStatus': 'pending',
          'verificationSubmittedAt': FieldValue.serverTimestamp(),
          'verificationRejectionReason': null,
        });

        setState(() {
          _cnicUrl = downloadUrl;
          _cnicUploading = false;
          _verificationStatus = 'pending';
          _rejectionReason = null;
        });

        _showSnack('CNIC uploaded successfully! Verification pending.');
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      debugPrint('Error uploading CNIC: $e');
      _resetUploadingState();
      _showSnack('Upload failed: $e');
    }
  }

  void _resetUploadingState() {
    setState(() {
      _cnicUploading = false;
      _cnicImage = null;
      _cnicWebBytes = null;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CNIC Verification'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Verification Status Banner
                  _buildStatusBanner(),
                  const SizedBox(height: 24),

                  // Show instructions only if not verified
                  if (_verificationStatus != 'verified') ...[
                    _buildInstructionsCard(),
                    const SizedBox(height: 24),
                  ],

                  // CNIC Document Card
                  _buildDocumentCard(),

                  const SizedBox(height: 24),

                  // Info Section
                  if (_verificationStatus == 'pending')
                    _buildPendingInfoCard(),

                  if (_verificationStatus == 'verified')
                    _buildVerifiedCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText;

    switch (_verificationStatus) {
      case 'verified':
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        icon = Icons.verified;
        statusText = 'Your CNIC is verified ✓';
        break;
      case 'rejected':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        icon = Icons.cancel;
        statusText = 'Verification rejected. Please re-upload.';
        break;
      case 'pending':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        icon = Icons.pending;
        statusText = 'Verification pending review';
        break;
      default:
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade700;
        icon = Icons.upload_file;
        statusText = 'Upload CNIC to get verified';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (_rejectionReason != null && _verificationStatus == 'rejected') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reason: $_rejectionReason',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              Text(
                'Why verification?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem(
            '1',
            'CNIC verification helps ensure trust and safety.',
          ),
          _buildInstructionItem(
            '2',
            'Verified customers can book chefs and use all features.',
          ),
          _buildInstructionItem(
            '3',
            'Upload a clear photo of your CNIC (front side).',
          ),
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
                Icon(Icons.warning_amber, color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fake or unclear documents will be rejected.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard() {
    final hasImage = _cnicUrl != null || _cnicImage != null || _cnicWebBytes != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.credit_card, color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'CNIC / ID Card',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            ' *',
                            style: TextStyle(color: Colors.red, fontSize: 16),
                          ),
                        ],
                      ),
                      Text(
                        'Required for identity verification',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Image Preview or Upload Button
          if (_cnicUploading)
            Container(
              height: 150,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Uploading...'),
                  ],
                ),
              ),
            )
          else if (hasImage)
            Column(
              children: [
                Container(
                  height: 150,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildImageWidget(),
                  ),
                ),
                // Action buttons below image
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Change Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        side: const BorderSide(color: Colors.deepPurple),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            InkWell(
              onTap: _pickImage,
              child: Container(
                height: 120,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 40,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to upload CNIC',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Camera or Gallery',
                        style: TextStyle(
                          color: Colors.grey.shade500,
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
    );
  }

  Widget _buildImageWidget() {
    if (_cnicWebBytes != null) {
      return Image.memory(
        _cnicWebBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else if (_cnicImage != null) {
      return Image.file(
        _cnicImage!,
        fit: BoxFit.cover,
        width: double.infinity,
      );
    } else if (_cnicUrl != null) {
      return SizedBox(
        width: double.infinity,
        height: 150,
        child: CachedChefImage(
          imageUrl: _cnicUrl!,
          height: 150,
          fit: BoxFit.cover,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPendingInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.hourglass_bottom,
              size: 40,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your documents are under review',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This usually takes 24-48 hours. We\'ll notify you once your verification is complete.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified,
              size: 48,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Verification Complete!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Your CNIC has been verified. You can now book chefs and use all features.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

