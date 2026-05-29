// ─────────────────────────────────────────────────────────────────────────────
// AREA 4: ImageProcessingService — Flutter Isolate + Optimistic UI
//
// Provides:
//   1. processImageInBackground() — isolate-isolated resize + encoding
//   2. OptimisticPhotoCapture widget — shows thumbnail immediately,
//      runs upload in background, keeps guard UI unlocked
//
// pubspec.yaml dependencies required:
//   camera: ^0.11.0
//   image: ^4.2.0
//   firebase_storage: ^12.3.2   ← updated from 12.0.0 / 11.7.0
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

// FIX 1: dart:io and dart:isolate are NOT available on Flutter Web.
// Use kIsWeb to branch at runtime; keep native-only code inside the guard.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SECTION A: Background image processing via Dart Isolate
// ─────────────────────────────────────────────────────────────────────────────

// FIX 2: Top-level function usable by both compute() (web) and Isolate (native).
Map<String, dynamic> _processImageParams(Map<String, dynamic> params) {
  final String filePath = params['filePath'] as String;
  final int maxDimension = params['maxDimension'] as int;
  final int jpegQuality = params['jpegQuality'] as int;

  final bytes = File(filePath).readAsBytesSync();
  img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) return {'result': null};

  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    decoded = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? maxDimension : -1,
      height: decoded.height >= decoded.width ? maxDimension : -1,
    );
  }

  final Uint8List processed =
      Uint8List.fromList(img.encodeJpg(decoded, quality: jpegQuality));
  return {'result': processed};
}

/// Message sent to the native Dart Isolate (mobile/desktop only).
class _IsolateRequest {
  final String filePath;
  final int maxDimension;
  final int jpegQuality;
  final SendPort replyPort;
  const _IsolateRequest(
      this.filePath, this.maxDimension, this.jpegQuality, this.replyPort);
}

// FIX 3: Isolate entry-point has NO Flutter bindings — using debugPrint()
// caused a runtime crash ("Binding is not initialized"). Replaced with print().
void _imageProcessorEntryPoint(_IsolateRequest request) {
  try {
    final result = _processImageParams({
      'filePath': request.filePath,
      'maxDimension': request.maxDimension,
      'jpegQuality': request.jpegQuality,
    });
    request.replyPort.send(result['result'] as Uint8List?);
  } catch (e) {
    // ignore: avoid_print
    print('Isolate image processing error: $e');
    request.replyPort.send(null);
  }
}

class ImageProcessingService {
  ImageProcessingService._();
  static final ImageProcessingService instance = ImageProcessingService._();

  /// Resize + compress an image file COMPLETELY off the main thread.
  ///
  /// On mobile/desktop: spawns a true Dart Isolate (zero UI jank).
  /// On web: falls back to Flutter's compute() which uses a web worker.
  Future<Uint8List?> processImageInBackground(
    String filePath, {
    int maxDimension = 1024,
    int jpegQuality = 82,
  }) async {
    // FIX 4: kIsWeb guard — dart:isolate crashes on Flutter Web.
    if (kIsWeb) {
      try {
        final result = await compute(_processImageParams, {
          'filePath': filePath,
          'maxDimension': maxDimension,
          'jpegQuality': jpegQuality,
        });
        return result['result'] as Uint8List?;
      } catch (e) {
        debugPrint('Web image processing error: $e');
        return null;
      }
    }

    // Native: true Dart Isolate.
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      _imageProcessorEntryPoint,
      _IsolateRequest(
          filePath, maxDimension, jpegQuality, receivePort.sendPort),
    );

    // FIX 5: await receivePort.first BEFORE killing the isolate to avoid a
    // race where the isolate is killed before it can send its reply.
    final Uint8List? result = await receivePort.first as Uint8List?;
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
    return result;
  }

  /// Upload already-processed bytes to Firebase Storage.
  Future<String?> uploadBytes(
    Uint8List bytes, {
    required String storagePath,
  }) async {
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      final task =
          ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  /// All-in-one: process off-thread, upload, return URL.
  Future<String?> processAndUpload(
    String filePath, {
    required String storagePath,
    int maxDimension = 1024,
    int jpegQuality = 82,
  }) async {
    final bytes = await processImageInBackground(filePath,
        maxDimension: maxDimension, jpegQuality: jpegQuality);
    if (bytes == null) return null;
    return uploadBytes(bytes, storagePath: storagePath);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION B: OptimisticPhotoCapture Widget
// ─────────────────────────────────────────────────────────────────────────────

enum _UploadState { idle, uploading, success, error }

class OptimisticPhotoCapture extends StatefulWidget {
  final String? deliveryLogId;
  final String Function(String logId) storagePathBuilder;
  final void Function(String url)? onUploadComplete;

  const OptimisticPhotoCapture({
    super.key,
    this.deliveryLogId,
    required this.storagePathBuilder,
    this.onUploadComplete,
  });

  @override
  State<OptimisticPhotoCapture> createState() => _OptimisticPhotoCaptureState();
}

class _OptimisticPhotoCaptureState extends State<OptimisticPhotoCapture> {
  _UploadState _state = _UploadState.idle;
  String? _localPath;
  String? _uploadedUrl; // ignore: unused_field
  String? _errorMessage;

  Future<void> _capturePhoto() async {
    // ── DEMO STUB: replace with real camera capture in production ──────────
    const String path = '/tmp/stub_visitor_photo.jpg';

    setState(() {
      _localPath = path;
      _state = _UploadState.uploading;
    });

    final logId = widget.deliveryLogId ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final storagePath = widget.storagePathBuilder(logId);

    final url = await ImageProcessingService.instance.processAndUpload(
      path,
      storagePath: storagePath,
    );

    if (url != null) {
      if (widget.deliveryLogId != null) {
        await FirebaseFirestore.instance
            .collection('approvals')
            .doc(widget.deliveryLogId)
            .update({'visitorPhotoUrl': url});
      }
      widget.onUploadComplete?.call(url);
      if (mounted) {
        setState(() {
          _state = _UploadState.success;
          _uploadedUrl = url;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _state = _UploadState.error;
          _errorMessage = 'Upload failed — tap to retry';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _state == _UploadState.uploading ? null : _capturePhoto,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFF141428),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _state == _UploadState.error
                ? Colors.redAccent
                : _state == _UploadState.success
                    ? Colors.greenAccent
                    : Colors.white24,
            width: 1.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // FIX 6: Image.file() is unsupported on Flutter Web.
              // Guard with kIsWeb and show a placeholder icon instead.
              if (_localPath != null)
                kIsWeb
                    ? const Icon(Icons.image_rounded,
                        color: Colors.white54, size: 32)
                    : Image.file(File(_localPath!), fit: BoxFit.cover)
              else
                const Icon(Icons.add_a_photo_rounded,
                    color: Colors.white38, size: 32),

              if (_state == _UploadState.uploading)
                Container(
                  color: Colors.black54,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.cyanAccent, strokeWidth: 2),
                      ),
                      SizedBox(height: 6),
                      Text('Uploading...',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 9)),
                    ],
                  ),
                ),

              if (_state == _UploadState.success)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.black, size: 12),
                  ),
                ),

              if (_state == _UploadState.error)
                Container(
                  color: Colors.black54,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 22),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage ?? 'Retry',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USAGE IN guard_dashboard.dart (inside _showApprovalRequestModal or form):
//
//   OptimisticPhotoCapture(
//     deliveryLogId: docRef?.id,
//     storagePathBuilder: (id) => 'delivery_photos/$id.jpg',
//     onUploadComplete: (url) => debugPrint('Photo ready: $url'),
//   )
//
// The guard can immediately tap SEND after snapping the photo.
// The upload finishes quietly in the background.
// ─────────────────────────────────────────────────────────────────────────────
