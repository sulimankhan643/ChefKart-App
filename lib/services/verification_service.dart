import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service class for handling CNIC verification
class VerificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Supabase bucket for verification documents
  static const String _bucketName = 'verification-documents';

  /// Get current user's verification status
  static Future<Map<String, dynamic>> getVerificationStatus() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        return {'status': 'not_logged_in'};
      }

      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        return {'status': 'not_submitted'};
      }

      final data = doc.data()!;
      return {
        'status': data['verification_status'] ?? 'not_submitted',
        'document_url': data['verification_document_url'],
        'submitted_at': data['verification_submitted_at'],
        'rejection_reason': data['verification_rejection_reason'],
      };
    } catch (e) {
      debugPrint('Error getting verification status: $e');
      return {'status': 'error', 'error': e.toString()};
    }
  }

  /// Upload CNIC image and update verification status
  static Future<Map<String, dynamic>> submitVerification({
    required File imageFile,
  }) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        return {'success': false, 'error': 'User not logged in'};
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'cnic_${uid}_$timestamp.jpg';

      debugPrint('VerificationService: Uploading CNIC image...');
      debugPrint('VerificationService: File path: ${imageFile.path}');
      debugPrint('VerificationService: File name: $fileName');

      // Read file bytes
      final fileBytes = await imageFile.readAsBytes();
      debugPrint('VerificationService: File size: ${fileBytes.length} bytes');

      if (fileBytes.isEmpty) {
        return {'success': false, 'error': 'Image file is empty'};
      }

      // Upload to Supabase Storage
      bool uploadedToMainBucket = false;
      try {
        await _supabase.storage
            .from(_bucketName)
            .uploadBinary(
              fileName,
              fileBytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        uploadedToMainBucket = true;
      } catch (e) {
        debugPrint('VerificationService: Error uploading to $_bucketName: $e');

        // If bucket doesn't exist or network error, check if it's a connection issue first
        if (e.toString().contains('SocketException') || e.toString().contains('Network is unreachable')) {
           return {'success': false, 'error': 'Network error. Please check your internet connection.'};
        }

        // Try using the default 'images' bucket as fallback
        debugPrint('VerificationService: Trying fallback "images" bucket');
        try {
          await _supabase.storage
              .from('images') // Fallback bucket
              .uploadBinary(
                'verification/$fileName',
                fileBytes,
                fileOptions: const FileOptions(
                  upsert: true,
                  contentType: 'image/jpeg',
                ),
              );
        } catch (fallbackError) {
           debugPrint('VerificationService: Fallback upload failed: $fallbackError');
           return {'success': false, 'error': 'Upload failed. Please check internet connection.'};
        }
      }

      // Get public URL
      String publicUrl;
      try {
        if (uploadedToMainBucket) {
          publicUrl = _supabase.storage.from(_bucketName).getPublicUrl(fileName);
        } else {
          publicUrl = _supabase.storage.from('images').getPublicUrl('verification/$fileName');
        }
      } catch (e) {
        debugPrint('VerificationService: Error getting public URL: $e');
        return {'success': false, 'error': 'Failed to get image URL after upload.'};
      }

      debugPrint('VerificationService: Public URL: $publicUrl');

      // Update Firestore with verification data
      await _firestore.collection('users').doc(uid).update({
        'verification_status': 'pending',
        'verification_document_url': publicUrl,
        'verification_submitted_at': FieldValue.serverTimestamp(),
        'verification_rejection_reason': null,
      });

      debugPrint('VerificationService: Firestore updated successfully');

      return {
        'success': true,
        'document_url': publicUrl,
        'status': 'pending',
      };
    } catch (e) {
      debugPrint('VerificationService: Error submitting verification: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if user can submit verification (not already pending)
  static Future<bool> canSubmitVerification() async {
    final status = await getVerificationStatus();
    final verificationStatus = status['status'];
    return verificationStatus != 'pending' && verificationStatus != 'approved';
  }

  /// Check if user's CNIC is verified (for blocking orders/bookings)
  static Future<bool> isUserVerified() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return false;

      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      // Check both field names for compatibility
      final status = data['verificationStatus'] ?? data['verification_status'] ?? 'not_submitted';
      return status == 'verified' || status == 'approved';
    } catch (e) {
      debugPrint('Error checking verification status: $e');
      return false;
    }
  }

  /// Check if user has CNIC uploaded (pending or verified)
  static Future<Map<String, dynamic>> getFullVerificationStatus() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        return {'isVerified': false, 'status': 'not_logged_in', 'hasCnic': false};
      }

      final doc = await _firestore.collection('users').doc(uid).get();
      if (!doc.exists) {
        return {'isVerified': false, 'status': 'not_submitted', 'hasCnic': false};
      }

      final data = doc.data()!;
      // Check both field names for compatibility
      final status = data['verificationStatus'] ?? data['verification_status'] ?? 'not_submitted';
      final cnicUrl = data['cnicUrl'] ?? data['verification_document_url'];
      final hasCnic = cnicUrl != null && cnicUrl.toString().isNotEmpty;
      final isVerified = status == 'verified' || status == 'approved';

      return {
        'isVerified': isVerified,
        'status': status,
        'hasCnic': hasCnic,
        'cnicUrl': cnicUrl,
      };
    } catch (e) {
      debugPrint('Error getting full verification status: $e');
      return {'isVerified': false, 'status': 'error', 'hasCnic': false};
    }
  }

  /// Stream verification status changes
  static Stream<Map<String, dynamic>> streamVerificationStatus() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return Stream.value({'status': 'not_logged_in'});
    }

    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return {'status': 'not_submitted'};
      }

      final data = snapshot.data()!;
      return {
        'status': data['verification_status'] ?? 'not_submitted',
        'document_url': data['verification_document_url'],
        'submitted_at': data['verification_submitted_at'],
        'rejection_reason': data['verification_rejection_reason'],
      };
    });
  }
}
