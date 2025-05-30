import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'firebase_service.dart';

class StorageService {
  // Singleton instance
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  StorageService._();
  
  final ImagePicker _imagePicker = ImagePicker();
  
  // Storage paths
  static const String _profileImagesPath = 'profile_images';
  static const String _chatImagesPath = 'chat_images';
  static const String _tempImagesPath = 'temp_images';
  
  // Image quality settings
  static const int _imageQuality = 85;
  static const int _maxImageWidth = 1920;
  static const int _maxImageHeight = 1080;
  static const int _thumbnailSize = 300;
  
  // Pick image from gallery
  Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _maxImageWidth.toDouble(),
        maxHeight: _maxImageHeight.toDouble(),
        imageQuality: _imageQuality,
      );
      
      if (image != null) {
        print('✅ Image picked from gallery: ${image.path}');
      }
      
      return image;
    } catch (e) {
      print('❌ Error picking image from gallery: $e');
      return null;
    }
  }
  
  // Pick image from camera
  Future<XFile?> pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxImageWidth.toDouble(),
        maxHeight: _maxImageHeight.toDouble(),
        imageQuality: _imageQuality,
      );
      
      if (image != null) {
        print('✅ Image captured from camera: ${image.path}');
      }
      
      return image;
    } catch (e) {
      print('❌ Error capturing image from camera: $e');
      return null;
    }
  }
  
  // Upload image file to Firebase Storage
  Future<String?> uploadImage({
    required XFile imageFile,
    required String uploadPath,
    String? fileName,
    Function(double)? onProgress,
  }) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }
      
      // Generate unique filename if not provided
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = path.extension(imageFile.path);
      final finalFileName = fileName ?? '${timestamp}_$currentUserId$extension';
      
      // Create storage reference
      final storageRef = FirebaseService.storage
          .ref()
          .child(uploadPath)
          .child(finalFileName);
      
      // Upload file
      late UploadTask uploadTask;
      
      if (kIsWeb) {
        // For web platform
        final bytes = await imageFile.readAsBytes();
        uploadTask = storageRef.putData(
          bytes,
          SettableMetadata(
            contentType: 'image/${extension.replaceAll('.', '')}',
            customMetadata: {
              'uploadedBy': currentUserId,
              'uploadedAt': timestamp.toString(),
            },
          ),
        );
      } else {
        // For mobile platforms
        uploadTask = storageRef.putFile(
          File(imageFile.path),
          SettableMetadata(
            contentType: 'image/${extension.replaceAll('.', '')}',
            customMetadata: {
              'uploadedBy': currentUserId,
              'uploadedAt': timestamp.toString(),
            },
          ),
        );
      }
      
      // Listen to upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
        print('📤 Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
      });
      
      // Wait for upload completion
      final TaskSnapshot snapshot = await uploadTask;
      
      // Get download URL
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      
      print('✅ Image uploaded successfully: $downloadUrl');
      return downloadUrl;
      
    } catch (e) {
      print('❌ Error uploading image: $e');
      return null;
    }
  }
  
  // Upload profile image
  Future<String?> uploadProfileImage({
    required XFile imageFile,
    Function(double)? onProgress,
  }) async {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return null;
    
    return await uploadImage(
      imageFile: imageFile,
      uploadPath: '$_profileImagesPath/$currentUserId',
      fileName: 'profile_$currentUserId.jpg',
      onProgress: onProgress,
    );
  }
  
  // Upload chat image
  Future<String?> uploadChatImage({
    required XFile imageFile,
    required String chatId,
    Function(double)? onProgress,
  }) async {
    final currentUserId = FirebaseService.currentUserId;
    if (currentUserId == null) return null;
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    return await uploadImage(
      imageFile: imageFile,
      uploadPath: '$_chatImagesPath/$chatId',
      fileName: 'chat_${timestamp}_$currentUserId.jpg',
      onProgress: onProgress,
    );
  }
  
  // Upload image from bytes (useful for web or processed images)
  Future<String?> uploadImageFromBytes({
    required Uint8List bytes,
    required String uploadPath,
    required String fileName,
    String? contentType,
    Function(double)? onProgress,
  }) async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }
      
      // Create storage reference
      final storageRef = FirebaseService.storage
          .ref()
          .child(uploadPath)
          .child(fileName);
      
      // Upload bytes
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(
          contentType: contentType ?? 'image/jpeg',
          customMetadata: {
            'uploadedBy': currentUserId,
            'uploadedAt': DateTime.now().millisecondsSinceEpoch.toString(),
          },
        ),
      );
      
      // Listen to upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });
      
      // Wait for upload completion
      final TaskSnapshot snapshot = await uploadTask;
      
      // Get download URL
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      
      print('✅ Image uploaded from bytes successfully: $downloadUrl');
      return downloadUrl;
      
    } catch (e) {
      print('❌ Error uploading image from bytes: $e');
      return null;
    }
  }
  
  // Delete image from storage
  Future<bool> deleteImage(String imageUrl) async {
    try {
      // Extract storage path from URL
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      
      // Find the file path in storage
      final storagePathIndex = pathSegments.indexOf('o') + 1;
      if (storagePathIndex >= pathSegments.length) {
        throw Exception('Invalid storage URL');
      }
      
      final storagePath = Uri.decodeComponent(pathSegments[storagePathIndex]);
      
      // Create reference and delete
      final storageRef = FirebaseService.storage.ref().child(storagePath);
      await storageRef.delete();
      
      print('✅ Image deleted successfully: $storagePath');
      return true;
      
    } catch (e) {
      print('❌ Error deleting image: $e');
      return false;
    }
  }
  
  // Get image metadata
  Future<FullMetadata?> getImageMetadata(String imageUrl) async {
    try {
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final storagePathIndex = pathSegments.indexOf('o') + 1;
      
      if (storagePathIndex >= pathSegments.length) {
        throw Exception('Invalid storage URL');
      }
      
      final storagePath = Uri.decodeComponent(pathSegments[storagePathIndex]);
      final storageRef = FirebaseService.storage.ref().child(storagePath);
      
      return await storageRef.getMetadata();
    } catch (e) {
      print('❌ Error getting image metadata: $e');
      return null;
    }
  }
  
  // Create thumbnail from image
  Future<Uint8List?> createThumbnail(XFile imageFile) async {
    try {
      // For a simple implementation, we'll just return the original bytes
      // In a production app, you might want to use image processing libraries
      // like image or flutter_image_compress to create actual thumbnails
      
      final bytes = await imageFile.readAsBytes();
      
      // You can implement image resizing logic here
      // For now, returning original bytes
      return bytes;
      
    } catch (e) {
      print('❌ Error creating thumbnail: $e');
      return null;
    }
  }
  
  // Compress image
  Future<XFile?> compressImage(XFile imageFile, {int quality = 85}) async {
    try {
      // This is a simplified version
      // In production, use flutter_image_compress or similar
      return imageFile;
    } catch (e) {
      print('❌ Error compressing image: $e');
      return null;
    }
  }
  
  // Clean up old images (for housekeeping)
  Future<void> cleanupOldImages({
    required String folderPath,
    required Duration maxAge,
  }) async {
    try {
      final storageRef = FirebaseService.storage.ref().child(folderPath);
      final ListResult result = await storageRef.listAll();
      
      final cutoffTime = DateTime.now().subtract(maxAge);
      
      for (final Reference item in result.items) {
        try {
          final FullMetadata metadata = await item.getMetadata();
          final uploadTime = metadata.timeCreated;
          
          if (uploadTime != null && uploadTime.isBefore(cutoffTime)) {
            await item.delete();
            print('🗑️ Deleted old image: ${item.fullPath}');
          }
        } catch (e) {
          print('❌ Error processing item ${item.fullPath}: $e');
        }
      }
      
      print('✅ Cleanup completed for folder: $folderPath');
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }
  
  // Get storage usage for current user
  Future<int> getUserStorageUsage() async {
    try {
      final currentUserId = FirebaseService.currentUserId;
      if (currentUserId == null) return 0;
      
      int totalSize = 0;
      
      // Check profile images
      final profileRef = FirebaseService.storage
          .ref()
          .child('$_profileImagesPath/$currentUserId');
      
      try {
        final profileResult = await profileRef.listAll();
        for (final item in profileResult.items) {
          final metadata = await item.getMetadata();
          totalSize += metadata.size ?? 0;
        }
      } catch (e) {
        // Folder might not exist
      }
      
      // Check chat images
      final chatRef = FirebaseService.storage.ref().child(_chatImagesPath);
      try {
        final chatResult = await chatRef.listAll();
        for (final folder in chatResult.prefixes) {
          final folderResult = await folder.listAll();
          for (final item in folderResult.items) {
            final metadata = await item.getMetadata();
            final uploadedBy = metadata.customMetadata?['uploadedBy'];
            if (uploadedBy == currentUserId) {
              totalSize += metadata.size ?? 0;
            }
          }
        }
      } catch (e) {
        // Folder might not exist
      }
      
      return totalSize;
    } catch (e) {
      print('❌ Error calculating storage usage: $e');
      return 0;
    }
  }
  
  // Format file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  // Show image picker dialog
  Future<XFile?> showImagePickerDialog() async {
    // This would typically show a dialog in the UI
    // For now, we'll just pick from gallery as default
    return await pickImageFromGallery();
  }
  
  // Batch upload multiple images
  Future<List<String>> uploadMultipleImages({
    required List<XFile> imageFiles,
    required String uploadPath,
    Function(int completed, int total)? onProgress,
  }) async {
    final List<String> uploadedUrls = [];
    
    for (int i = 0; i < imageFiles.length; i++) {
      final imageFile = imageFiles[i];
      
      final url = await uploadImage(
        imageFile: imageFile,
        uploadPath: uploadPath,
        onProgress: (progress) {
          // Individual file progress can be handled here if needed
        },
      );
      
      if (url != null) {
        uploadedUrls.add(url);
      }
      
      onProgress?.call(i + 1, imageFiles.length);
    }
    
    return uploadedUrls;
  }
  
  // Check if file exists in storage
  Future<bool> fileExists(String storagePath) async {
    try {
      final storageRef = FirebaseService.storage.ref().child(storagePath);
      await storageRef.getMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Get download URL for a storage path
  Future<String?> getDownloadUrl(String storagePath) async {
    try {
      final storageRef = FirebaseService.storage.ref().child(storagePath);
      return await storageRef.getDownloadURL();
    } catch (e) {
      print('❌ Error getting download URL: $e');
      return null;
    }
  }
}