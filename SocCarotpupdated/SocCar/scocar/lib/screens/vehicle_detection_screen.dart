import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show AppTokens, themeNotifier;

// ─────────────────────────────────────────────────────────────────────────────
// VehicleDetectionScreen — ANPR Auto-Log
//
// FLOW:
//   1. Guard taps camera icon in AppBar → this screen opens
//   2. Live viewfinder shows rear camera feed
//   3. Guard taps the FAB (scan button) to capture a frame
//   4. Frame is sent to the FastAPI backend (POST /api/ocr/detect-vehicle)
//   5. Backend returns { status, vehicle_number: [{number, confidence}] }
//   6. Screen queries Firestore 'vehicles' collection for a matching plate
//   7a. MATCH FOUND → determines ENTRY or EXIT from current logs →
//       writes a log document → shows green success overlay
//   7b. NO MATCH    → shows "unregistered vehicle" warning overlay
//   8. Guard can scan again or go back
//
// All movement logs written here use the same field schema as
// UnifiedEntryForm so the resident _ActivityHistoryTab renders them correctly.
// ─────────────────────────────────────────────────────────────────────────────

// ── Internal result model ─────────────────────────────────────────────────────
enum _ScanStatus { idle, scanning, matched, unregistered, error }

class _ScanResult {
  final String      plateNumber;
  final double      confidence;
  final String?     flatNumber;
  final String?     ownerName;
  final String      movementType; // 'ENTRY' or 'EXIT'
  final String?     logDocId;     // written Firestore doc

  const _ScanResult({
    required this.plateNumber,
    required this.confidence,
    this.flatNumber,
    this.ownerName,
    required this.movementType,
    this.logDocId,
  });
}

class VehicleDetectionScreen extends StatefulWidget {
  final String? guardId;
  const VehicleDetectionScreen({super.key, this.guardId});

  @override
  State<VehicleDetectionScreen> createState() => _VehicleDetectionScreenState();
}

class _VehicleDetectionScreenState extends State<VehicleDetectionScreen>
    with SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cam;
  bool _camReady = false;

  // ── Scan state ────────────────────────────────────────────────────────────
  _ScanStatus  _status  = _ScanStatus.idle;
  _ScanResult? _result;
  String       _errorMsg = '';

  // ── Scanner frame animation ────────────────────────────────────────────────
  late AnimationController _frameAnim;
  late Animation<double>   _framePulse;

  // ── Backend config ────────────────────────────────────────────────────────
  // ⚠️ Replace with your Mac/PC's local Wi-Fi IP before running on device.
  static const String _backendIp   = '192.168.1.35';
  static const String _backendPort = '8000';
  static const String _endpoint    =
      'http://$_backendIp:$_backendPort/api/ocr/detect-vehicle';

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _frameAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _framePulse = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _frameAnim, curve: Curves.easeInOut));
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) { setState(() => _camReady = false); return; }
      _cam = CameraController(cams[0], ResolutionPreset.high, enableAudio: false);
      await _cam!.initialize();
      if (mounted) setState(() => _camReady = true);
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _camReady = false);
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _frameAnim.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core pipeline — capture → OCR → Firestore lookup → log
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runScanPipeline() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    if (_status == _ScanStatus.scanning) return;

    setState(() { _status = _ScanStatus.scanning; _result = null; _errorMsg = ''; });

    try {
      // ── Step 1: Capture frame ──────────────────────────────────────────
      final XFile frame = await _cam!.takePicture();

      // ── Step 2: Send to backend OCR ────────────────────────────────────
      final req = http.MultipartRequest('POST', Uri.parse(_endpoint));
      req.files.add(await http.MultipartFile.fromPath('file', frame.path));
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      final body     = await streamed.stream.bytesToString();

      if (streamed.statusCode != 200) {
        throw Exception('Backend returned ${streamed.statusCode}');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      // ── Step 3: Parse detected plates ─────────────────────────────────
      if (json['status'] != 'success' ||
          json['vehicle_number'] == null ||
          (json['vehicle_number'] as List).isEmpty) {
        setState(() { _status = _ScanStatus.error; _errorMsg = 'No plate detected. Try again.'; });
        return;
      }

      final best       = (json['vehicle_number'] as List).first as Map<String, dynamic>;
      final plate      = (best['number'] as String).toUpperCase().replaceAll(' ', '');
      final confidence = (best['confidence'] as num).toDouble();

      // ── Step 4: Firestore lookup ───────────────────────────────────────
      final vehicleSnap = await FirebaseFirestore.instance
          .collection('vehicles')
          .where('plateNumber', isEqualTo: plate)
          .limit(1)
          .get();

      if (vehicleSnap.docs.isEmpty) {
        // Unregistered vehicle
        setState(() {
          _status = _ScanStatus.unregistered;
          _result = _ScanResult(
            plateNumber : plate,
            confidence  : confidence,
            movementType: 'UNKNOWN',
          );
        });
        return;
      }

      final vData    = vehicleSnap.docs.first.data();
      final flatNum  = (vData['flatNumber'] ?? vData['flat_number'] ?? '').toString().toUpperCase();
      final owner    = (vData['ownerName']  ?? vData['owner_name']  ?? 'Resident').toString();

      // ── Step 5: Determine ENTRY or EXIT from latest log for this plate ──
      final latestLog = await FirebaseFirestore.instance
          .collection('logs')
          .where('plateNumber', isEqualTo: plate)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      String movementType = 'ENTRY'; // default — first appearance is always ENTRY
      if (latestLog.docs.isNotEmpty) {
        final lastType =
            (latestLog.docs.first.data()['type'] ?? 'EXIT').toString().toUpperCase();
        // If the last log was ENTRY → now it's EXIT, and vice-versa
        movementType = (lastType == 'ENTRY') ? 'EXIT' : 'ENTRY';
      }

      // ── Step 6: Write log document ─────────────────────────────────────
      final logRef = await FirebaseFirestore.instance.collection('logs').add({
        // Fields consumed by resident _ActivityHistoryTab
        'type'          : movementType,
        'entryType'     : movementType,           // badge colour/icon resolver
        'flatNumber'    : flatNum,
        'company'       : owner,                  // shown in card title row
        'plateNumber'   : plate,
        'guardId'       : widget.guardId ?? 'ANPR',
        'notes'         : 'Auto-logged by ANPR camera',
        // Legacy aliases for backward-compat with older readers
        'movement_type' : movementType,
        'visitor_name'  : owner,
        'vehicle_number': plate,
        'flat_number'   : flatNum,
        // Metadata
        'confidence'    : confidence,
        'source'        : 'ANPR_CAMERA',
        'timestamp'     : FieldValue.serverTimestamp(),
      });

      setState(() {
        _status = _ScanStatus.matched;
        _result = _ScanResult(
          plateNumber : plate,
          confidence  : confidence,
          flatNumber  : flatNum,
          ownerName   : owner,
          movementType: movementType,
          logDocId    : logRef.id,
        );
      });

    } on TimeoutException {
      setState(() { _status = _ScanStatus.error; _errorMsg = 'Backend timeout — is the server running?'; });
    } on SocketException {
      setState(() { _status = _ScanStatus.error; _errorMsg = 'Cannot reach backend at $_backendIp:$_backendPort'; });
    } catch (e) {
      setState(() { _status = _ScanStatus.error; _errorMsg = e.toString(); });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reset
  // ─────────────────────────────────────────────────────────────────────────

  void _reset() => setState(() {
    _status   = _ScanStatus.idle;
    _result   = null;
    _errorMsg = '';
  });

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(isDark),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ────────────────────────────────────────────────
          _buildCameraLayer(),

          // ── Scan frame overlay ─────────────────────────────────────────
          if (_status == _ScanStatus.idle || _status == _ScanStatus.scanning)
            _buildScanFrame(),

          // ── Scanning shimmer ───────────────────────────────────────────
          if (_status == _ScanStatus.scanning)
            _buildScanningShimmer(),

          // ── Result overlay ─────────────────────────────────────────────
          if (_status != _ScanStatus.idle && _status != _ScanStatus.scanning)
            _buildResultOverlay(isDark),

          // ── Bottom controls ────────────────────────────────────────────
          if (_status == _ScanStatus.idle || _status == _ScanStatus.scanning)
            Positioned(
              left: 0, right: 0, bottom: 40,
              child: _buildControls(),
            ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation      : 0,
      title: const Text(
        'ANPR VEHICLE SCAN',
        style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
      ),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // Theme toggle
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, mode, __) => IconButton(
            icon: Icon(
              mode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              color: Colors.white70,
            ),
            onPressed: () => themeNotifier.value =
                mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
          ),
        ),
      ],
    );
  }

  // ── Camera layer ──────────────────────────────────────────────────────────

  Widget _buildCameraLayer() {
    if (!_camReady || _cam == null) {
      return Container(
        color: const Color(0xFF0A0A12),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 64),
              const SizedBox(height: 16),
              Text(
                _camReady == false && _cam == null
                    ? 'Initialising camera...'
                    : 'Camera unavailable',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
              if (_cam == null) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: AppTokens.cyanAction, strokeWidth: 2),
              ],
            ],
          ),
        ),
      );
    }
    return SizedBox.expand(child: CameraPreview(_cam!));
  }

  // ── Scan frame ────────────────────────────────────────────────────────────
  // A rounded rectangle cut-out that shows the guard where to aim the camera.

  Widget _buildScanFrame() {
    return Center(
      child: AnimatedBuilder(
        animation: _framePulse,
        builder: (_, __) => Transform.scale(
          scale: _framePulse.value,
          child: Container(
            width : 280,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _status == _ScanStatus.scanning
                    ? AppTokens.cyanAction
                    : Colors.white54,
                width: 2.5,
              ),
            ),
            child: Stack(children: [
              // Corner accents
              ..._corners(
                  _status == _ScanStatus.scanning ? AppTokens.cyanAction : Colors.white),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _corners(Color c) {
    const double s = 20, t = 3.5;
    return [
      _corner(top: 0,    left: 0,    child: _L(c, s, t, true,  true)),
      _corner(top: 0,    right: 0,   child: _L(c, s, t, true,  false)),
      _corner(bottom: 0, left: 0,    child: _L(c, s, t, false, true)),
      _corner(bottom: 0, right: 0,   child: _L(c, s, t, false, false)),
    ];
  }

  Widget _corner({double? top, double? bottom, double? left, double? right, required Widget child}) =>
      Positioned(top: top, bottom: bottom, left: left, right: right, child: child);

  Widget _L(Color c, double s, double t, bool isTop, bool isLeft) {
    return SizedBox(width: s, height: s, child: CustomPaint(
      painter: _CornerPainter(c, t, isTop, isLeft)));
  }

  // ── Scanning shimmer ──────────────────────────────────────────────────────

  Widget _buildScanningShimmer() {
    return Center(
      child: SizedBox(
        width: 280, height: 120,
        child: LayoutBuilder(builder: (_, box) {
          return AnimatedBuilder(
            animation: _frameAnim,
            builder: (_, __) {
              final y = box.maxHeight * _frameAnim.value;
              return Stack(children: [
                Positioned(
                  left: 0, right: 0,
                  top : y.clamp(0, box.maxHeight - 2),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        AppTokens.cyanAction.withOpacity(0.8),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ]);
            },
          );
        }),
      ),
    );
  }

  // ── Bottom scan button ─────────────────────────────────────────────────────

  Widget _buildControls() {
    final isScanning = _status == _ScanStatus.scanning;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hint text
        Text(
          isScanning
              ? 'Analysing frame...'
              : 'Point camera at the number plate\nthen tap SCAN',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        // Scan FAB
        GestureDetector(
          onTap: isScanning ? null : _runScanPipeline,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width : 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isScanning
                  ? AppTokens.cyanAction.withOpacity(0.3)
                  : AppTokens.cyanAction,
              boxShadow: isScanning ? null : [
                BoxShadow(
                  color    : AppTokens.cyanAction.withOpacity(0.45),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: isScanning
                ? const Center(
                    child: SizedBox(width: 28, height: 28,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3)))
                : const Icon(Icons.document_scanner_rounded,
                    color: Colors.black, size: 34),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          isScanning ? 'SCANNING...' : 'SCAN',
          style: TextStyle(
            color     : isScanning ? Colors.white38 : Colors.white,
            fontSize  : 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  // ── Result overlay ─────────────────────────────────────────────────────────

  Widget _buildResultOverlay(bool isDark) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Container(
        key  : ValueKey(_status),
        color: Colors.black.withOpacity(0.82),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: _resultCard(isDark),
          ),
        ),
      ),
    );
  }

  Widget _resultCard(bool isDark) {
    switch (_status) {
      case _ScanStatus.matched:
        return _matchedCard(isDark);
      case _ScanStatus.unregistered:
        return _unregisteredCard(isDark);
      case _ScanStatus.error:
        return _errorCard(isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── MATCHED card ──────────────────────────────────────────────────────────

  Widget _matchedCard(bool isDark) {
    final r         = _result!;
    final isEntry   = r.movementType == 'ENTRY';
    final accent    = isEntry ? Colors.greenAccent : Colors.orangeAccent;
    final icon      = isEntry ? Icons.login_rounded : Icons.logout_rounded;
    final typeLabel = isEntry ? 'ENTRY LOGGED' : 'EXIT LOGGED';

    return Container(
      decoration: BoxDecoration(
        color       : isDark ? const Color(0xFF0E1E14) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border      : Border.all(color: accent.withOpacity(0.4), width: 1.5),
        boxShadow   : [BoxShadow(color: accent.withOpacity(0.2), blurRadius: 32)],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon glow
          Container(
            width : 80, height: 80,
            decoration: BoxDecoration(
              shape    : BoxShape.circle,
              color    : accent.withOpacity(0.12),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 24, spreadRadius: 4)],
            ),
            child: Icon(icon, color: accent, size: 40),
          ),
          const SizedBox(height: 20),

          // Type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color       : accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border      : Border.all(color: accent.withOpacity(0.4)),
            ),
            child: Text(typeLabel,
                style: TextStyle(color: accent, fontWeight: FontWeight.bold,
                    fontSize: 12, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 20),

          // Plate number — prominent
          Text(
            r.plateNumber,
            style: const TextStyle(
              color     : Colors.white,
              fontSize  : 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),

          // Confidence bar
          _ConfidenceBar(value: r.confidence),
          const SizedBox(height: 20),

          // Info rows
          _infoRow(Icons.apartment_rounded, 'Flat', r.flatNumber ?? '—', accent),
          const SizedBox(height: 8),
          _infoRow(Icons.person_rounded, 'Owner', r.ownerName ?? '—', accent),
          const SizedBox(height: 24),

          // Action buttons
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                onPressed: _reset,
                icon : const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('SCAN NEXT',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                icon : const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('BACK',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── UNREGISTERED card ─────────────────────────────────────────────────────

  Widget _unregisteredCard(bool isDark) {
    final r = _result!;
    return Container(
      decoration: BoxDecoration(
        color       : isDark ? const Color(0xFF1E1200) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border      : Border.all(color: Colors.orange.withOpacity(0.5), width: 1.5),
        boxShadow   : [BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 32)],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width : 80, height: 80,
            decoration: BoxDecoration(
              shape    : BoxShape.circle,
              color    : Colors.orange.withOpacity(0.12),
              boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.25), blurRadius: 24)],
            ),
            child: const Icon(Icons.no_crash_rounded, color: Colors.orangeAccent, size: 40),
          ),
          const SizedBox(height: 20),
          const Text('Unregistered Vehicle',
              style: TextStyle(color: Colors.orangeAccent,
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(r.plateNumber,
              style: const TextStyle(color: Colors.white, fontSize: 26,
                  fontWeight: FontWeight.bold, letterSpacing: 4, fontFamily: 'monospace')),
          const SizedBox(height: 6),
          _ConfidenceBar(value: r.confidence),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: const Text(
              'This plate is not in the registered vehicles list.\n'
              'Ask the guard to use the Entry Form to process this visitor manually.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              onPressed: _reset,
              icon : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('SCAN AGAIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            )),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(context),
              icon : const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('BACK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            )),
          ]),
        ],
      ),
    );
  }

  // ── ERROR card ────────────────────────────────────────────────────────────

  Widget _errorCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color       : isDark ? const Color(0xFF1E0A0A) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border      : Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56),
          const SizedBox(height: 16),
          const Text('Scan Failed',
              style: TextStyle(color: Colors.redAccent,
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(_errorMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            onPressed: _reset,
            icon : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('TRY AGAIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          )),
        ],
      ),
    );
  }

  // ── Info row helper ───────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String value, Color accent) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: accent, size: 16),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.8)),
        Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ConfidenceBar — visual OCR confidence indicator
// ─────────────────────────────────────────────────────────────────────────────
class _ConfidenceBar extends StatelessWidget {
  final double value; // 0.0 – 1.0
  const _ConfidenceBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final pct   = (value * 100).toStringAsFixed(1);
    final color = value >= 0.85
        ? Colors.greenAccent
        : value >= 0.60
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('OCR Confidence',
              style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.5)),
          Text('$pct%', style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value          : value.clamp(0.0, 1.0),
            backgroundColor: Colors.white10,
            valueColor     : AlwaysStoppedAnimation(color),
            minHeight      : 5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CornerPainter — draws an L-shaped corner accent on the scan frame
// ─────────────────────────────────────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color  color;
  final double thickness;
  final bool   isTop;
  final bool   isLeft;
  const _CornerPainter(this.color, this.thickness, this.isTop, this.isLeft);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = thickness
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final double x = isLeft ? 0 : size.width;
    final double y = isTop  ? 0 : size.height;
    final double dx = isLeft ?  size.width  : -size.width;
    final double dy = isTop  ?  size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.thickness != thickness;
}
