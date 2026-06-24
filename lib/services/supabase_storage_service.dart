import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service class for handling image uploads to Supabase Storage
class SupabaseStorageService {
  static final SupabaseClient _client = Supabase.instance.client;

  // Bucket name in Supabase
  static const String _bucketName = 'images';

  /// Test Supabase connection and bucket access
  static Future<bool> testConnection() async {
    try {
      debugPrint('Supabase: Testing connection...');

      // Try to list buckets
      final buckets = await _client.storage.listBuckets();
      debugPrint('Supabase: Available buckets: ${buckets.map((b) => b.name).toList()}');

      // Check if our bucket exists
      final hasImagesBucket = buckets.any((b) => b.name == _bucketName);
      debugPrint('Supabase: Has "$_bucketName" bucket: $hasImagesBucket');

      if (hasImagesBucket) {
        // Try to list files in bucket
        final files = await _client.storage.from(_bucketName).list();
        debugPrint('Supabase: Files in bucket: ${files.length}');
      }

      return hasImagesBucket;
    } catch (e) {
      debugPrint('Supabase connection test failed: $e');
      return false;
    }
  }

  /// Simple image upload from File (mobile)
  static Future<String?> uploadImage({
    required File file,
    required String fileName,
  }) async {
    try {
      debugPrint('Supabase: Starting file upload - fileName: $fileName');
      debugPrint('Supabase: File path: ${file.path}');
      debugPrint('Supabase: File exists: ${await file.exists()}');
      final fileSize = await file.length();
      debugPrint('Supabase: File size: $fileSize bytes');

      if (fileSize == 0) {
        debugPrint('Supabase: ERROR - File is empty');
        return null;
      }

      // Read file bytes for upload
      final fileBytes = await file.readAsBytes();
      debugPrint('Supabase: Read ${fileBytes.length} bytes from file');

      final response = await _client.storage
          .from(_bucketName)
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      debugPrint('Supabase: Upload response: $response');

      final publicUrl = _client.storage.from(_bucketName).getPublicUrl(fileName);
      debugPrint('Supabase: Public URL: $publicUrl');

      if (publicUrl.isEmpty) {
        debugPrint('Supabase: ERROR - Public URL is empty');
        return null;
      }

      return publicUrl;
    } on StorageException catch (e) {
      debugPrint('Supabase StorageException: ${e.message}');
      debugPrint('Supabase StorageException statusCode: ${e.statusCode}');
      debugPrint('Supabase StorageException error: ${e.error}');

      // Provide helpful error messages
      if (e.statusCode == '404' || e.message.contains('not found')) {
        debugPrint('ERROR: Bucket "$_bucketName" does not exist. Please create it in Supabase Dashboard > Storage');
      } else if (e.statusCode == '403' || e.message.contains('denied') || e.message.contains('policy')) {
        debugPrint('ERROR: Permission denied. Add INSERT policy for bucket in Supabase Dashboard > Storage > Policies');
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint('Supabase upload error: $e');
      debugPrint('Supabase upload stackTrace: $stackTrace');
      return null;
    }
  }

  /// Upload image from bytes (for web)
  static Future<String?> uploadImageBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      debugPrint('Supabase: Starting bytes upload - fileName: $fileName');
      debugPrint('Supabase: Bytes size: ${bytes.length}');

      final response = await _client.storage
          .from(_bucketName)
          .uploadBinary(fileName, bytes, fileOptions: const FileOptions(upsert: true));

      debugPrint('Supabase: Upload response: $response');

      final publicUrl = _client.storage.from(_bucketName).getPublicUrl(fileName);
      debugPrint('Supabase: Public URL: $publicUrl');

      if (publicUrl.isEmpty) {
        debugPrint('Supabase: ERROR - Public URL is empty');
        return null;
      }

      return publicUrl;
    } on StorageException catch (e) {
      debugPrint('Supabase StorageException: ${e.message}');
      debugPrint('Supabase StorageException statusCode: ${e.statusCode}');
      debugPrint('Supabase StorageException error: ${e.error}');
      return null;
    } catch (e, stackTrace) {
      debugPrint('Supabase upload error: $e');
      debugPrint('Supabase upload stackTrace: $stackTrace');
      return null;
    }
  }

  /// Upload CNIC document
  static Future<String?> uploadCNIC({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'chef_documents/cnic_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    debugPrint('Supabase: uploadCNIC called - userId: $userId, hasFile: ${file != null}, hasBytes: ${bytes != null}');

    try {
      if (kIsWeb && bytes != null) {
        return await uploadImageBytes(bytes: bytes, fileName: fileName);
      } else if (file != null) {
        return await uploadImage(file: file, fileName: fileName);
      }
      debugPrint('Supabase: uploadCNIC - No file or bytes provided');
      return null;
    } catch (e) {
      debugPrint('Supabase: uploadCNIC error: $e');
      return null;
    }
  }

  /// Upload certificate document
  static Future<String?> uploadCertificate({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'chef_documents/certificate_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    debugPrint('Supabase: uploadCertificate called - userId: $userId, hasFile: ${file != null}, hasBytes: ${bytes != null}');

    try {
      if (kIsWeb && bytes != null) {
        return await uploadImageBytes(bytes: bytes, fileName: fileName);
      } else if (file != null) {
        return await uploadImage(file: file, fileName: fileName);
      }
      debugPrint('Supabase: uploadCertificate - No file or bytes provided');
      return null;
    } catch (e) {
      debugPrint('Supabase: uploadCertificate error: $e');
      return null;
    }
  }

  /// Upload chef profile image
  static Future<String?> uploadChefProfileImage({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'chef_profiles/chef_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    if (kIsWeb && bytes != null) {
      return uploadImageBytes(bytes: bytes, fileName: fileName);
    } else if (file != null) {
      return uploadImage(file: file, fileName: fileName);
    }
    return null;
  }

  /// Upload customer profile image
  static Future<String?> uploadCustomerProfileImage({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'customer_profiles/customer_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    if (kIsWeb && bytes != null) {
      return uploadImageBytes(bytes: bytes, fileName: fileName);
    } else if (file != null) {
      return uploadImage(file: file, fileName: fileName);
    }
    return null;
  }

  /// Upload food item image
  static Future<String?> uploadFoodImage({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'food_items/food_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

    if (kIsWeb && bytes != null) {
      return uploadImageBytes(bytes: bytes, fileName: fileName);
    } else if (file != null) {
      return uploadImage(file: file, fileName: fileName);
    }
    return null;
  }

  /// Upload commission payment proof
  /// Used when chef submits EasyPaisa payment screenshot
  static Future<String?> uploadCommissionProof({
    File? file,
    Uint8List? bytes,
    required String userId,
  }) async {
    final fileName = 'commission_proofs/proof_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    debugPrint('Supabase: uploadCommissionProof called - userId: $userId, hasFile: ${file != null}, hasBytes: ${bytes != null}');

    try {
      if (kIsWeb && bytes != null) {
        return await uploadImageBytes(bytes: bytes, fileName: fileName);
      } else if (file != null) {
        return await uploadImage(file: file, fileName: fileName);
      }
      debugPrint('Supabase: uploadCommissionProof - No file or bytes provided');
      return null;
    } catch (e) {
      debugPrint('Supabase: uploadCommissionProof error: $e');
      return null;
    }
  }

  /// Delete a file from storage
  static Future<bool> deleteFile(String filePath) async {
    try {
      await _client.storage.from(_bucketName).remove([filePath]);
      return true;
    } catch (e) {
      debugPrint('Supabase delete error: $e');
      return false;
    }
  }

  /// Get an accessible URL for a stored file.
  /// If the public URL doesn't work, tries to create a signed URL.
  /// [storedUrl] is the URL previously stored in Firestore.
  static Future<String?> getAccessibleUrl(String storedUrl) async {
    try {
      // Extract file path from the stored URL
      final filePath = _extractFilePath(storedUrl);
      if (filePath == null) {
        debugPrint('Supabase: Could not extract file path from URL: $storedUrl');
        return storedUrl; // Return original, let the caller handle the error
      }

      // Try to create a signed URL (works for both public and private buckets)
      try {
        final signedUrl = await _client.storage
            .from(_bucketName)
            .createSignedUrl(filePath, 60 * 60 * 24 * 7); // 7 days
        debugPrint('Supabase: Generated signed URL for: $filePath');
        return signedUrl;
      } catch (e) {
        debugPrint('Supabase: Signed URL failed, returning public URL: $e');
        // Fall back to public URL
        return _client.storage.from(_bucketName).getPublicUrl(filePath);
      }
    } catch (e) {
      debugPrint('Supabase: getAccessibleUrl error: $e');
      return storedUrl;
    }
  }

  /// Extract file path from a Supabase storage public URL
  static String? _extractFilePath(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      // Supabase public URL format: /storage/v1/object/public/{bucket}/{filePath}
      // or /storage/v1/object/sign/{bucket}/{filePath}
      final bucketIndex = pathSegments.indexOf(_bucketName);
      if (bucketIndex >= 0 && bucketIndex < pathSegments.length - 1) {
        return pathSegments.sublist(bucketIndex + 1).join('/');
      }
      return null;
    } catch (e) {
      debugPrint('Supabase: Error extracting file path: $e');
      return null;
    }
  }
}

