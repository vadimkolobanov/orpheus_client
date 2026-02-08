import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

/// Result of APK download operation
class ApkDownloadResult {
  final bool success;
  final String? filePath;
  final String? error;

  ApkDownloadResult.success(this.filePath)
      : success = true,
        error = null;

  ApkDownloadResult.error(this.error)
      : success = false,
        filePath = null;
}

/// Service for downloading APK files with progress tracking
class ApkDownloadService {
  static const Duration _downloadTimeout = Duration(minutes: 5);

  /// Check if the device supports in-app APK installation
  static Future<bool> canInstallApkInApp() async {
    try {
      // Check Android version (must be Android 5.0+ / API 21+)
      if (!Platform.isAndroid) {
        return false;
      }

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Android 5.0 (API 21) and above
      if (androidInfo.version.sdkInt < 21) {
        return false;
      }

      // For Android 8+ (API 26+), check if we can request install packages
      if (androidInfo.version.sdkInt >= 26) {
        // This permission is automatically granted if declared in manifest
        // but we should still check
        return true;
      }

      return true;
    } catch (e) {
      print('APK_DOWNLOAD: Error checking device capability: $e');
      return false;
    }
  }

  /// Check and request necessary permissions for downloading APK
  static Future<bool> requestPermissions() async {
    try {
      // For Android 13+ (API 33+), we need notification permission for download progress
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        if (androidInfo.version.sdkInt >= 33) {
          final notificationStatus = await Permission.notification.status;
          if (!notificationStatus.isGranted) {
            final result = await Permission.notification.request();
            if (!result.isGranted) {
              print('APK_DOWNLOAD: Notification permission denied (optional)');
            }
          }
        }
      }

      return true;
    } catch (e) {
      print('APK_DOWNLOAD: Error requesting permissions: $e');
      return false;
    }
  }

  /// Download APK file with progress callback
  ///
  /// Returns [ApkDownloadResult] with file path on success or error message on failure
  ///
  /// [url] - URL to download APK from
  /// [onProgress] - callback for download progress (0.0 to 1.0)
  static Future<ApkDownloadResult> downloadApk(
    String url, {
    required Function(double progress) onProgress,
  }) async {
    try {
      print('APK_DOWNLOAD: Starting download from $url');

      // Check if we can install APK
      final canInstall = await canInstallApkInApp();
      if (!canInstall) {
        return ApkDownloadResult.error('Device does not support in-app APK installation');
      }

      // Request permissions
      final permissionsGranted = await requestPermissions();
      if (!permissionsGranted) {
        return ApkDownloadResult.error('Required permissions not granted');
      }

      // Get cache directory
      final cacheDir = await getTemporaryDirectory();
      final updatesDir = Directory('${cacheDir.path}/updates');

      // Create updates directory if it doesn't exist
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      // Generate file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${updatesDir.path}/orpheus_update_$timestamp.apk';

      print('APK_DOWNLOAD: Saving to $filePath');

      // Download with Dio (supports progress tracking)
      final dio = Dio(BaseOptions(
        connectTimeout: _downloadTimeout,
        receiveTimeout: _downloadTimeout,
        sendTimeout: _downloadTimeout,
      ));

      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            onProgress(progress);
            print('APK_DOWNLOAD: Progress ${(progress * 100).toStringAsFixed(1)}%');
          }
        },
        options: Options(
          headers: {
            'User-Agent': 'Orpheus/1.1.2 (Android)',
          },
        ),
      );

      // Verify file was downloaded
      final file = File(filePath);
      if (!await file.exists()) {
        return ApkDownloadResult.error('Downloaded file not found');
      }

      final fileSize = await file.length();
      print('APK_DOWNLOAD: Download complete. File size: ${fileSize} bytes');

      if (fileSize < 1024 * 1024) {
        // Less than 1 MB - probably error page or corrupted
        return ApkDownloadResult.error('Downloaded file is too small (possible error)');
      }

      return ApkDownloadResult.success(filePath);
    } on DioException catch (e) {
      print('APK_DOWNLOAD: Dio error: ${e.message}');
      if (e.type == DioExceptionType.connectionTimeout) {
        return ApkDownloadResult.error('Download timeout - connection too slow');
      } else if (e.type == DioExceptionType.receiveTimeout) {
        return ApkDownloadResult.error('Download timeout - server not responding');
      } else if (e.type == DioExceptionType.cancel) {
        return ApkDownloadResult.error('Download cancelled');
      } else {
        return ApkDownloadResult.error('Network error: ${e.message}');
      }
    } catch (e, stackTrace) {
      print('APK_DOWNLOAD: Unexpected error: $e');
      print('APK_DOWNLOAD: Stack trace: $stackTrace');
      return ApkDownloadResult.error('Download failed: $e');
    }
  }

  /// Install APK file (opens system installer)
  ///
  /// Returns true if installer was opened successfully, false otherwise
  static Future<bool> installApk(String filePath) async {
    try {
      print('APK_DOWNLOAD: Installing APK from $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        print('APK_DOWNLOAD: APK file not found at $filePath');
        return false;
      }

      // Use open_filex to open APK file
      // This will trigger Android system installer
      final openFilex = await compute(_openApkInIsolate, filePath);
      return openFilex;
    } catch (e, stackTrace) {
      print('APK_DOWNLOAD: Error installing APK: $e');
      print('APK_DOWNLOAD: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Helper function to open APK in isolate
  static Future<bool> _openApkInIsolate(String filePath) async {
    try {
      // We'll use open_filex package
      // Import it dynamically to avoid issues if package is not available
      final openFilex = await _tryOpenFile(filePath);
      return openFilex;
    } catch (e) {
      print('APK_DOWNLOAD: Error in isolate: $e');
      return false;
    }
  }

  /// Try to open file using open_filex package
  static Future<bool> _tryOpenFile(String filePath) async {
    try {
      print('APK_DOWNLOAD: Opening APK file: $filePath');

      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      print('APK_DOWNLOAD: OpenFilex result: ${result.type} - ${result.message}');

      // ResultType.done means installer was opened successfully
      return result.type == ResultType.done;
    } catch (e) {
      print('APK_DOWNLOAD: Error opening file: $e');
      return false;
    }
  }

  /// Clean up old downloaded APK files
  static Future<void> cleanupOldApks() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final updatesDir = Directory('${cacheDir.path}/updates');

      if (!await updatesDir.exists()) {
        return;
      }

      final files = await updatesDir.list().toList();
      for (final file in files) {
        if (file is File && file.path.endsWith('.apk')) {
          try {
            await file.delete();
            print('APK_DOWNLOAD: Cleaned up ${file.path}');
          } catch (e) {
            print('APK_DOWNLOAD: Error deleting ${file.path}: $e');
          }
        }
      }
    } catch (e) {
      print('APK_DOWNLOAD: Error cleaning up old APKs: $e');
    }
  }
}
