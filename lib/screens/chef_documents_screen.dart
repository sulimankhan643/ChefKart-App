import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_storage_service.dart';

/// Chef Documents Screen - Upload and manage verification documents
class ChefDocumentsScreen extends StatefulWidget {
  final VoidCallback? onSave;

  const ChefDocumentsScreen({super.key, this.onSave});

  @override
  State<ChefDocumentsScreen> createState() => _ChefDocumentsScreenState();
}

class _ChefDocumentsScreenState extends State<ChefDocumentsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isUploading = false;

  // Document state
  String? _cnicUrl;
  String? _certificateUrl;
  File? _cnicImage;
  File? _certificateImage;
  Uint8List? _cnicWebBytes;
  Uint8List? _certificateWebBytes;

  // Verification status
  String _verificationStatus = 'not_submitted';
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
        String? cnicUrl = data['cnicUrl']?.toString();
        String? certificateUrl = data['certificateUrl']?.toString();
        String status = data['verificationStatus'] ?? 'not_submitted';

        // If no CNIC uploaded but status is pending, reset to not_submitted
        if ((cnicUrl == null || cnicUrl.isEmpty) && status == 'pending') {
          status = 'not_submitted';
          // Also update in Firestore
          await _firestore.collection('users').doc(uid).update({
            'verificationStatus': 'not_submitted',
          });
        }

        // Try to get accessible (signed) URLs for stored images
        // This fixes "failed to load image" when public URL doesn't work
        if (cnicUrl != null && cnicUrl.isNotEmpty) {
          try {
            final accessibleUrl = await SupabaseStorageService.getAccessibleUrl(cnicUrl);
            if (accessibleUrl != null) {
              cnicUrl = accessibleUrl;
            }
          } catch (e) {
            debugPrint('Error getting accessible CNIC URL: $e');
          }
        }

        if (certificateUrl != null && certificateUrl.isNotEmpty) {
          try {
            final accessibleUrl = await SupabaseStorageService.getAccessibleUrl(certificateUrl);
            if (accessibleUrl != null) {
              certificateUrl = accessibleUrl;
            }
          } catch (e) {
            debugPrint('Error getting accessible certificate URL: $e');
          }
        }

        setState(() {
          _cnicUrl = cnicUrl;
          _certificateUrl = certificateUrl;
          _verificationStatus = status;
          _rejectionReason = data['rejectionReason'];
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

  Future<void> _showImageSourceDialog(String documentType) async {
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
                documentType == 'cnic' ? 'Upload CNIC Photo' : 'Upload Certificate',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    _selectImage(ImageSource.camera, documentType);
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
                  _selectImage(ImageSource.gallery, documentType);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectImage(ImageSource source, String documentType) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1500,
        maxHeight: 1500,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (pickedFile == null) return;

      setState(() => _isUploading = true);

      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        _showSnack('Please login first', isError: true);
        setState(() => _isUploading = false);
        return;
      }

      String? downloadUrl;

      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        if (documentType == 'cnic') {
          _cnicWebBytes = bytes;
          downloadUrl = await SupabaseStorageService.uploadCNIC(
            bytes: bytes,
            userId: uid,
          );
        } else {
          _certificateWebBytes = bytes;
          downloadUrl = await SupabaseStorageService.uploadCertificate(
            bytes: bytes,
            userId: uid,
          );
        }
      } else {
        final file = File(pickedFile.path);
        if (documentType == 'cnic') {
          _cnicImage = file;
          downloadUrl = await SupabaseStorageService.uploadCNIC(
            file: file,
            userId: uid,
          );
        } else {
          _certificateImage = file;
          downloadUrl = await SupabaseStorageService.uploadCertificate(
            file: file,
            userId: uid,
          );
        }
      }

      if (downloadUrl != null) {
        // Save to Firestore
        Map<String, dynamic> updateData = {
          documentType == 'cnic' ? 'cnicUrl' : 'certificateUrl': downloadUrl,
          'verificationStatus': 'pending',
          'verificationSubmittedAt': FieldValue.serverTimestamp(),
        };

        await _firestore.collection('users').doc(uid).update(updateData);

        setState(() {
          if (documentType == 'cnic') {
            _cnicUrl = downloadUrl;
          } else {
            _certificateUrl = downloadUrl;
          }
          _verificationStatus = 'pending';
          _isUploading = false;
        });

        _showSnack('${documentType == 'cnic' ? 'CNIC' : 'Certificate'} uploaded successfully!');
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      debugPrint('Error uploading $documentType: $e');
      setState(() {
        _isUploading = false;
        if (documentType == 'cnic') {
          _cnicImage = null;
          _cnicWebBytes = null;
        } else {
          _certificateImage = null;
          _certificateWebBytes = null;
        }
      });
      _showSnack('Upload failed: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Verification Documents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Card
                  _buildStatusCard(),

                  const SizedBox(height: 24),

                  // Show upload sections based on status
                  if (_verificationStatus != 'verified') ...[
                    // Instructions Card
                    _buildInstructionsCard(),

                    const SizedBox(height: 24),
                  ],

                  // CNIC Upload Section
                  _buildCnicSection(),

                  const SizedBox(height: 20),

                  // Certificate Upload Section
                  _buildCertificateSection(),

                  // Show verified message
                  if (_verificationStatus == 'verified')
                    _buildVerifiedCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    String statusSubtext;

    switch (_verificationStatus) {
      case 'verified':
        statusColor = const Color(0xFF27AE60);
        statusIcon = Icons.verified;
        statusText = 'Verified';
        statusSubtext = 'Your documents have been approved';
        break;
      case 'rejected':
        statusColor = const Color(0xFFE74C3C);
        statusIcon = Icons.cancel;
        statusText = 'Rejected';
        statusSubtext = 'Please re-upload your documents';
        break;
      case 'pending':
        statusColor = const Color(0xFFFF6B35);
        statusIcon = Icons.schedule;
        statusText = 'Under Review';
        statusSubtext = 'Usually takes 24-48 hours';
        break;
      default:
        statusColor = const Color(0xFF95A5A6);
        statusIcon = Icons.upload_file;
        statusText = 'Not Submitted';
        statusSubtext = 'Upload your CNIC to get verified';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusSubtext,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (_rejectionReason != null && _verificationStatus == 'rejected') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _rejectionReason!,
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFFFF6B35),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Instructions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3436),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInstructionItem('1', 'Upload a clear photo of your original CNIC (front side only).'),
          _buildInstructionItem('2', 'Make sure all text and photo on the CNIC is clearly visible.'),
          _buildInstructionItem('3', 'Avoid glare, shadows, or blurry images.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE74C3C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE74C3C),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Random or fake documents will be rejected.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFFF6B35),
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
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CNIC Section - Same logic as customer side
  Widget _buildCnicSection() {
    final hasUploadedImage = _cnicUrl != null;
    final hasLocalImage = _cnicImage != null || _cnicWebBytes != null;
    final hasAnyImage = hasUploadedImage || hasLocalImage;
    final isVerified = _verificationStatus == 'verified';
    final isPending = _verificationStatus == 'pending';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row - Fixed overflow
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.credit_card,
                  color: Color(0xFFFF6B35),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'CNIC / ID Card',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2D3436),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Text(
                          ' *',
                          style: TextStyle(color: Colors.red, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Required for identity verification',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Status badge - Below header to prevent overflow
          if (hasUploadedImage && (isPending || isVerified)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPending
                    ? const Color(0xFFFF6B35).withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPending ? Icons.schedule : Icons.verified,
                    size: 16,
                    color: isPending ? const Color(0xFFFF6B35) : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPending ? 'Under Review' : 'Verified',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isPending ? const Color(0xFFFF6B35) : Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Image Section
          if (_isUploading)
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B35),
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Uploading...',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (hasAnyImage) ...[
            // Show Image Preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildCnicImage(),
            ),
            const SizedBox(height: 16),
            // Change button - always visible below image
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showImageSourceDialog('cnic'),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Change Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ] else ...[
            // Upload button - only show if not verified
            if (!isVerified)
              GestureDetector(
                onTap: () => _showImageSourceDialog('cnic'),
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 32,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tap to Upload CNIC',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Camera or Gallery',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCnicImage() {
    if (_cnicWebBytes != null) {
      return Image.memory(
        _cnicWebBytes!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget('cnic');
        },
      );
    } else if (_cnicImage != null) {
      return Image.file(
        _cnicImage!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget('cnic');
        },
      );
    } else if (_cnicUrl != null && _cnicUrl!.isNotEmpty) {
      // Validate URL before loading
      final uri = Uri.tryParse(_cnicUrl!);
      if (uri == null || !uri.hasScheme) {
        debugPrint('Invalid CNIC URL: $_cnicUrl');
        return _buildImageErrorWidget('cnic');
      }
      return CachedNetworkImage(
        imageUrl: _cnicUrl!,
        cacheKey: _cnicUrl!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) {
          debugPrint('Error loading CNIC image: $error, URL: $url');
          return _buildImageErrorWidget('cnic');
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildImageErrorWidget(String documentType) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            'Failed to load image',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // Clear cached image and reload from Firestore
                  if (documentType == 'cnic' && _cnicUrl != null) {
                    CachedNetworkImage.evictFromCache(_cnicUrl!);
                  } else if (documentType == 'certificate' && _certificateUrl != null) {
                    CachedNetworkImage.evictFromCache(_certificateUrl!);
                  }
                  _loadDocuments();
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B35),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showImageSourceDialog(documentType),
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Re-upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B35),
                  side: const BorderSide(color: Color(0xFFFF6B35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Certificate Section - Same structure as CNIC
  Widget _buildCertificateSection() {
    final hasUploadedImage = _certificateUrl != null;
    final hasLocalImage = _certificateImage != null || _certificateWebBytes != null;
    final hasAnyImage = hasUploadedImage || hasLocalImage;
    final isVerified = _verificationStatus == 'verified';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFFF6B35),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cooking Certificate',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3436),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Optional - helps build trust',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Image Section
          if (hasAnyImage) ...[
            // Show Image Preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildCertificateImage(),
            ),
            const SizedBox(height: 16),
            // Change button - always visible below image
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showImageSourceDialog('certificate'),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Change Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B35),
                    side: const BorderSide(color: Color(0xFFFF6B35)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ] else ...[
            // Upload button - only show if not verified
            if (!isVerified)
              GestureDetector(
                onTap: () => _showImageSourceDialog('certificate'),
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          size: 32,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tap to Upload Certificate',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D3436),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Camera or Gallery',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCertificateImage() {
    if (_certificateWebBytes != null) {
      return Image.memory(
        _certificateWebBytes!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget('certificate');
        },
      );
    } else if (_certificateImage != null) {
      return Image.file(
        _certificateImage!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget('certificate');
        },
      );
    } else if (_certificateUrl != null && _certificateUrl!.isNotEmpty) {
      // Validate URL before loading
      final uri = Uri.tryParse(_certificateUrl!);
      if (uri == null || !uri.hasScheme) {
        debugPrint('Invalid Certificate URL: $_certificateUrl');
        return _buildImageErrorWidget('certificate');
      }
      return CachedNetworkImage(
        imageUrl: _certificateUrl!,
        cacheKey: _certificateUrl!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey.shade200,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (context, url, error) {
          debugPrint('Error loading Certificate image: $error, URL: $url');
          return _buildImageErrorWidget('certificate');
        },
      );
    }
    return const SizedBox.shrink();
  }


  Widget _buildVerifiedCard() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
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
            'Your documents have been verified. You now have full access to all chef features.',
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
