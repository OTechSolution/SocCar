import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

// ---------------------------------------------------------------------------
// Entry type enum
// ---------------------------------------------------------------------------

enum EntryType { delivery, visitor, generalMovement }

extension EntryTypeExtension on EntryType {
  String get label {
    switch (this) {
      case EntryType.delivery:
        return 'DELIVERY';
      case EntryType.visitor:
        return 'VISITOR';
      case EntryType.generalMovement:
        return 'MOVEMENT';
    }
  }

  String get displayName {
    switch (this) {
      case EntryType.delivery:
        return 'Delivery';
      case EntryType.visitor:
        return 'Visitor';
      case EntryType.generalMovement:
        return 'General Movement';
    }
  }

  IconData get icon {
    switch (this) {
      case EntryType.delivery:
        return Icons.local_shipping_rounded;
      case EntryType.visitor:
        return Icons.person_rounded;
      case EntryType.generalMovement:
        return Icons.swap_vert_rounded;
    }
  }
}

// ---------------------------------------------------------------------------
// Public API — call UnifiedEntryForm.show(context, guardId: ...)
// ---------------------------------------------------------------------------

class UnifiedEntryForm extends StatefulWidget {
  final String? guardId;

  const UnifiedEntryForm({super.key, this.guardId});

  /// Show the form as a full-screen-height bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? guardId,
    EntryType initialType = EntryType.delivery,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UnifiedEntryForm(guardId: guardId),
    );
  }

  @override
  State<UnifiedEntryForm> createState() => _UnifiedEntryFormState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class _UnifiedEntryFormState extends State<UnifiedEntryForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Focus nodes
  final _nameFocus = FocusNode();
  final _plateFocus = FocusNode();
  final _notesFocus = FocusNode();

  // State
  EntryType _entryType = EntryType.delivery;
  bool _isScanning = false;
  bool _isSubmitting = false;
  File? _scannedImage;

  // Animation controller for the submit button
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Auto-focus name field once sheet is open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_nameFocus);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _plateCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _plateFocus.dispose();
    _notesFocus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── OCR / Scan ─────────────────────────────────────────────────────────────

  // ── Request camera permission then open camera directly ─────────────────
  Future<bool> _requestCameraPermission() async {
    // Check current status first
    PermissionStatus status = await Permission.camera.status;

    if (status.isGranted) return true;

    if (status.isDenied) {
      // Ask for permission
      status = await Permission.camera.request();
      return status.isGranted;
    }

    if (status.isPermanentlyDenied) {
      // Permission was permanently denied — send user to app settings
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF141428),
            title: const Text('Camera Permission Required',
                style: TextStyle(color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.bold)),
            content: const Text(
              'Camera permission was denied. Please enable it in app settings '
              'to scan number plates.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings(); // Opens Android/iOS app settings
                },
                child: const Text('Open Settings',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
      return false;
    }

    return false;
  }

  Future<void> _scanNumberPlate() async {
    final hasPermission = await _requestCameraPermission();
    if (!hasPermission) {
      if (mounted) {
        _showSnack('Camera permission required to scan plates.',
            Colors.orange.shade700);
      }
      return;
    }

    setState(() => _isScanning = true);

    try {
      // Launch the live ANPR viewfinder
      final String? plate = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _LivePlateScannerScreen(
            extractPlate: _extractNumberPlate,
          ),
        ),
      );

      if (!mounted) return;

      if (plate != null && plate.isNotEmpty) {
        setState(() => _plateCtrl.text = plate);
        _showSnack('\u2705 Plate scanned: $plate', Colors.green.shade700);
        FocusScope.of(context).requestFocus(_notesFocus);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Scanner error: ${e.toString()}', Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Regex patterns for Indian number plates.
  ///   Standard  : MH12AB1234
  ///   BH series : 22BH1234AB
  ///   Old 2-col  : MH12 1234
  String? _extractNumberPlate(String raw) {
    final text = raw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

    final patterns = [
      // Standard 4-letter suffix: MH12AB1234
      RegExp(r'[A-Z]{2}\d{2}[A-Z]{1,3}\d{4}'),
      // BH series: 22BH1234AB
      RegExp(r'\d{2}BH\d{4}[A-Z]{1,2}'),
      // Old 2-column: MH121234 (state + 2 digits + 4 digits)
      RegExp(r'[A-Z]{2}\d{2}\d{4}'),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(text);
      if (m != null) return m.group(0);
    }
    return null;
  }

  // ─── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submitEntry() async {
    // Close keyboard
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type': 'ENTRY',
        'entryType': _entryType.displayName,     // "Delivery" / "Visitor" / "General Movement"
        'company': _nameCtrl.text.trim(),
        'plateNumber': _plateCtrl.text.trim().toUpperCase(),
        'notes': _notesCtrl.text.trim(),
        'guardId': widget.guardId ?? 'GUARD',
        'scannedImagePath': _scannedImage?.path,  // for optional image storage in logs
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_entryType.displayName} entry logged successfully.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          margin:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnack('Submission failed: $e', Colors.red.shade700);
        setState(() => _isSubmitting = false);
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  InputDecoration _inputDec({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF3A3A5C), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF4A4A7A), size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF13132A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:
            const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      errorStyle:
          const TextStyle(color: Colors.redAccent, fontSize: 11),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF7A7AAA),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Dismiss keyboard on tap outside
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0A0A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: Color(0xFF1E1E3A), width: 1),
          ),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Handle bar ────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A4A),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Header ────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_circle_outline_rounded,
                          color: Colors.cyanAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NEW ENTRY LOG',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          'Fill details or scan number plate',
                          style: TextStyle(
                            color: Color(0xFF5A5A8A),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                const Divider(color: Color(0xFF1A1A3A), height: 1),
                const SizedBox(height: 20),

                // ── 1. Entry Type Selector ────────────────────────────────
                _label('ENTRY TYPE'),
                _EntryTypeSelector(
                  selected: _entryType,
                  onChanged: (t) => setState(() => _entryType = t),
                ),

                const SizedBox(height: 22),

                // ── 2. Company / Visitor Name ─────────────────────────────
                _label('COMPANY / VISITOR NAME *'),
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_plateFocus),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 15),
                  decoration: _inputDec(
                    hint: 'Enter company or visitor name',
                    icon: Icons.badge_rounded,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),

                const SizedBox(height: 18),

                // ── 3. Vehicle Number Plate (manual) ──────────────────────
                _label('VEHICLE NUMBER PLATE'),
                TextFormField(
                  controller: _plateCtrl,
                  focusNode: _plateFocus,
                  textInputAction: TextInputAction.next,
                  onEditingComplete: () =>
                      FocusScope.of(context).requestFocus(_notesFocus),
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.5,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    // Auto-uppercase every character
                    TextInputFormatter.withFunction(
                      (old, newVal) => newVal.copyWith(
                        text: newVal.text.toUpperCase(),
                      ),
                    ),
                  ],
                  decoration: _inputDec(
                    hint: 'e.g. MH12AB1234',
                    icon: Icons.directions_car_rounded,
                    suffixIcon: _plateCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded,
                                color: Color(0xFF4A4A7A), size: 18),
                            onPressed: () =>
                                setState(() => _plateCtrl.clear()),
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 14),

                // ── 4. OR Divider ─────────────────────────────────────────
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E3A))),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.18),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: Color(0xFF1E1E3A))),
                  ],
                ),

                const SizedBox(height: 14),

                // ── 5. Scan Number Plate Button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      side: BorderSide(
                        color: _isScanning
                            ? Colors.cyanAccent.withOpacity(0.4)
                            : Colors.cyanAccent,
                        width: 1.5,
                      ),
                      backgroundColor:
                          Colors.cyanAccent.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _isScanning ? null : _scanNumberPlate,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.cyanAccent,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.document_scanner_rounded,
                            size: 20,
                          ),
                    label: Text(
                      _isScanning ? 'SCANNING...' : 'SCAN NUMBER PLATE',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),

                // Scanned image preview (small thumbnail)
                if (_scannedImage != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _scannedImage!,
                          width: 60,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Image captured — will be stored in logs.',
                          style: TextStyle(
                              color: Color(0xFF5A5A8A), fontSize: 11),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            setState(() => _scannedImage = null),
                        child: const Icon(Icons.close_rounded,
                            color: Color(0xFF4A4A6A), size: 16),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 20),

                // ── 6. Notes ──────────────────────────────────────────────
                _label('NOTES (OPTIONAL)'),
                TextFormField(
                  controller: _notesCtrl,
                  focusNode: _notesFocus,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () => FocusScope.of(context).unfocus(),
                  style: const TextStyle(
                      color: Color(0xFFAAAAAA), fontSize: 14),
                  decoration: _inputDec(
                    hint: 'Any additional remarks...',
                    icon: Icons.notes_rounded,
                  ),
                ),

                const SizedBox(height: 28),

                // ── 7. Submit Button ──────────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitting
                            ? Colors.cyanAccent.withOpacity(0.6)
                            : Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: _isSubmitting ? 0 : 6,
                        shadowColor:
                            Colors.cyanAccent.withOpacity(0.4),
                      ),
                      onPressed: _isSubmitting ? null : _submitEntry,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.black54,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded,
                              size: 22),
                      label: Text(
                        _isSubmitting
                            ? 'LOGGING ENTRY...'
                            : 'SUBMIT ENTRY',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry Type Segmented Selector
// ---------------------------------------------------------------------------

class _EntryTypeSelector extends StatelessWidget {
  final EntryType selected;
  final ValueChanged<EntryType> onChanged;

  const _EntryTypeSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: EntryType.values.asMap().entries.map((entry) {
        final idx = entry.key;
        final type = entry.value;
        final isSelected = type == selected;
        final isLast = idx == EntryType.values.length - 1;

        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: EdgeInsets.only(right: isLast ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B4D8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : const Color(0xFF13132A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : const Color(0xFF2A2A4A),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    type.icon,
                    color: isSelected
                        ? Colors.black
                        : const Color(0xFF4A4A7A),
                    size: 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    type.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.black
                          : const Color(0xFF4A4A7A),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _LivePlateScannerScreen
//
// Full-screen live camera viewfinder that continuously scans for number plates.
// Tapping CAPTURE freezes the frame, runs OCR, and returns the plate string
// back to the caller (unified_entry_form) via Navigator.pop(plateString).
//
// Uses the `camera` package for live preview and `google_mlkit_text_recognition`
// for OCR — same packages already in pubspec.yaml.
// ─────────────────────────────────────────────────────────────────────────────
class _LivePlateScannerScreen extends StatefulWidget {
  final String? Function(String) extractPlate;

  const _LivePlateScannerScreen({required this.extractPlate});

  @override
  State<_LivePlateScannerScreen> createState() =>
      _LivePlateScannerScreenState();
}

class _LivePlateScannerScreenState extends State<_LivePlateScannerScreen> {
  CameraController? _ctrl;
  bool _initialising = true;
  bool _processing   = false;
  String _hint       = 'Point camera at number plate';
  String _detected   = '';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() { _initialising = false; _hint = 'No camera found on device.'; });
        return;
      }
      // Pick rear camera
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _ctrl = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      await _ctrl!.initialize();
    } catch (e) {
      setState(() { _hint = 'Camera error: $e'; });
    } finally {
      if (mounted) setState(() => _initialising = false);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  // Capture current frame → run OCR → show result
  Future<void> _capture() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _processing) return;
    setState(() { _processing = true; _hint = 'Scanning plate…'; });

    try {
      final XFile file = await _ctrl!.takePicture();
      final inputImage = InputImage.fromFilePath(file.path);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result     = await recognizer.processImage(inputImage);
      await recognizer.close();

      final plate = widget.extractPlate(result.text);

      if (plate != null && plate.isNotEmpty) {
        setState(() {
          _detected = plate;
          _hint     = '✅ Plate detected — tap USE to confirm';
        });
      } else {
        // Show raw OCR as fallback so guard can confirm/edit
        final raw = result.text
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();
        setState(() {
          _detected = raw;
          _hint     = raw.isEmpty
              ? '⚠️ Nothing detected — try again'
              : '⚠️ Check text — tap USE or RETRY';
        });
      }
    } catch (e) {
      setState(() { _hint = 'Error: $e'; });
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Number Plate',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _initialising
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.cyanAccent),
                  SizedBox(height: 16),
                  Text('Starting camera…',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : _ctrl == null || !_ctrl!.value.isInitialized
              ? Center(
                  child: Text(_hint,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center))
              : Stack(
                  children: [
                    // ── Live camera preview ──────────────────────────────
                    Positioned.fill(child: CameraPreview(_ctrl!)),

                    // ── Aiming overlay ───────────────────────────────────
                    Positioned.fill(
                      child: CustomPaint(painter: _PlateScanOverlay()),
                    ),

                    // ── Status hint ──────────────────────────────────────
                    Positioned(
                      top  : 20,
                      left : 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color       : Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _hint,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    // ── Detected plate display ───────────────────────────
                    if (_detected.isNotEmpty)
                      Positioned(
                        bottom: 160,
                        left  : 24,
                        right : 24,
                        child : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color       : Colors.cyanAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(14),
                            border      : Border.all(
                                color: Colors.cyanAccent, width: 1.5),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.directions_car_rounded,
                                  color: Colors.cyanAccent, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                _detected,
                                style: const TextStyle(
                                  color       : Colors.cyanAccent,
                                  fontSize    : 22,
                                  fontWeight  : FontWeight.bold,
                                  letterSpacing: 3,
                                  fontFamily  : 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // ── Bottom action row ────────────────────────────────
                    Positioned(
                      bottom: 40,
                      left  : 24,
                      right : 24,
                      child : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [

                          // RETRY — clear and scan again
                          if (_detected.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () =>
                                  setState(() { _detected = ''; _hint = 'Point camera at number plate'; }),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon : const Icon(Icons.refresh_rounded),
                              label: const Text('RETRY',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),

                          // CAPTURE / USE button
                          ElevatedButton.icon(
                            onPressed: _processing
                                ? null
                                : (_detected.isNotEmpty
                                    ? () => Navigator.pop(context, _detected)
                                    : _capture),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _detected.isNotEmpty
                                  ? Colors.green.shade600
                                  : Colors.cyanAccent,
                              foregroundColor: _detected.isNotEmpty
                                  ? Colors.white
                                  : Colors.black,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              elevation: 6,
                            ),
                            icon: _processing
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.black, strokeWidth: 2))
                                : Icon(
                                    _detected.isNotEmpty
                                        ? Icons.check_circle_rounded
                                        : Icons.camera_rounded,
                                    size: 22,
                                  ),
                            label: Text(
                              _processing
                                  ? 'Scanning…'
                                  : (_detected.isNotEmpty ? 'USE THIS' : 'CAPTURE'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Aiming overlay painter ────────────────────────────────────────────────────
class _PlateScanOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withOpacity(0.45);
    final RRect plateRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.48),
        width : size.width * 0.82,
        height: size.height * 0.12,
      ),
      const Radius.circular(10),
    );

    // Dim everything outside the plate zone
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(plateRect),
      ),
      dimPaint,
    );

    // Cyan border around plate zone
    canvas.drawRRect(
      plateRect,
      Paint()
        ..color       = Colors.cyanAccent
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Corner accent marks
    final accentPaint = Paint()
      ..color       = Colors.cyanAccent
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap   = StrokeCap.round;

    final rect   = plateRect.outerRect;
    const double c = 18.0;

    // Top-left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(c, 0), accentPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, c), accentPaint);
    // Top-right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-c, 0), accentPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, c), accentPaint);
    // Bottom-left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(c, 0), accentPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -c), accentPaint);
    // Bottom-right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-c, 0), accentPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -c), accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
