import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter/services.dart';

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
      if (!Platform.isAndroid) return false;

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt < 21) return false;

      // For Android 8+ (API 26+), must have REQUEST_INSTALL_PACKAGES permission
      if (androidInfo.version.sdkInt >= 26) {
        var status = await Permission.requestInstallPackages.status;
        print('APK_DOWNLOAD: Install packages permission status: $status');
        if (!status.isGranted) {
          status = await Permission.requestInstallPackages.request();
          print('APK_DOWNLOAD: Install packages permission after request: $status');
          if (!status.isGranted) {
            return false;
          }
        }
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

      // Use app documents directory (more reliable than temp/cache)
      final docsDir = await getApplicationDocumentsDirectory();
      final updatesDir = Directory('${docsDir.path}/updates');

      // Create updates directory if it doesn't exist
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      // Clean old APKs before downloading new one
      try {
        final existing = await updatesDir.list().toList();
        for (final f in existing) {
          if (f is File && f.path.endsWith('.apk')) {
            await f.delete();
          }
        }
      } catch (_) {}

      // Generate file path
      final filePath = '${updatesDir.path}/orpheus_update.apk';

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
          }
        },
        deleteOnError: true,
      );

      // Verify file was downloaded
      final file = File(filePath);
      final exists = await file.exists();
      print('APK_DOWNLOAD: File exists: $exists at $filePath');
      if (!exists) {
        // List directory to debug
        final dirContents = await updatesDir.list().toList();
        print('APK_DOWNLOAD: Directory contents: ${dirContents.map((f) => f.path).toList()}');
        return ApkDownloadResult.error('Downloaded file not found at $filePath');
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

      final fileSize = await file.length();
      print('APK_DOWNLOAD: APK file size: $fileSize bytes');

      // Try Android Intent directly via platform channel first
      if (Platform.isAndroid) {
        try {
          final installed = await _installViaIntent(filePath);
          if (installed) return true;
          print('APK_DOWNLOAD: Intent install returned false, trying OpenFilex');
        } catch (e) {
          print('APK_DOWNLOAD: Intent install failed: $e, trying OpenFilex');
        }
      }

      // Fallback to OpenFilex
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      print('APK_DOWNLOAD: OpenFilex result: type=${result.type}, message=${result.message}');
      return result.type == ResultType.done;
    } catch (e, stackTrace) {
      print('APK_DOWNLOAD: Error installing APK: $e');
      print('APK_DOWNLOAD: Stack trace: $stackTrace');
      return false;
    }
  }

  static const _channel = MethodChannel('com.orpheus.apk_installer');

  /// Install APK via Android Intent (more reliable than OpenFilex)
  static Future<bool> _installViaIntent(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      print('APK_DOWNLOAD: Intent install result: $result');
      return result ?? false;
    } on MissingPluginException {
      print('APK_DOWNLOAD: Native install channel not available');
      return false;
    }
  }

  /// Clean up old downloaded APK files
  static Future<void> cleanupOldApks() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final updatesDir = Directory('${docsDir.path}/updates');

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
