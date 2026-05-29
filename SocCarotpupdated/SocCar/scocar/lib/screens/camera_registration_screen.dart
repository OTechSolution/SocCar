// ─────────────────────────────────────────────────────────────────────────────
// CameraRegistrationScreen — fully theme-aware (dark + light)
//
// All previously hardcoded dark colours (0xFF0A0A1A, 0xFF141428, Colors.white*)
// have been replaced with Theme.of(context) / isDark-conditional values so the
// screen renders correctly in both dark and light mode.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CameraRegistrationScreen extends StatefulWidget {
  const CameraRegistrationScreen({super.key});

  @override
  State<CameraRegistrationScreen> createState() =>
      _CameraRegistrationScreenState();
}

class _CameraRegistrationScreenState extends State<CameraRegistrationScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController   = TextEditingController();
  int    _gateNo    = 1;
  String _direction = 'IN';
  bool   _isSaving  = false;

  // ── Validate RTSP / HTTP camera URL ───────────────────────────────────────
  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'IP address / RTSP URL required';
    }
    final v = value.trim().toLowerCase();
    if (v.startsWith('rtsp://') ||
        v.startsWith('http://') ||
        v.startsWith('https://') ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?').hasMatch(v)) {
      return null;
    }
    return 'Enter a valid RTSP URL or IP address (e.g. rtsp://admin:pass@192.168.1.108/stream1)';
  }

  // ── Save camera document to Firestore ─────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('cameras').add({
        'cameraName': _nameController.text.trim(),
        'ipAddress' : _ipController.text.trim(),
        'gateNo'    : _gateNo,
        'direction' : _direction,
        'status'    : 'active',
        'addedAt'   : FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content        : Text('✅ Camera registered successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('❌ Error saving camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final cs       = Theme.of(context).colorScheme;
    final scaffold = Theme.of(context).scaffoldBackgroundColor;
    final cardCol  = Theme.of(context).cardColor;
    final divCol   = Theme.of(context).dividerColor;

    return Scaffold(
      backgroundColor: scaffold,
      appBar: AppBar(
        title: Text(
          'Register IP Camera',
          style: TextStyle(
            color     : cs.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Uses theme AppBar colours — no hardcoded hex
        elevation : 0,
        iconTheme : IconThemeData(color: cs.onSurface),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [

            // ── Existing cameras list ────────────────────────────────────
            const _SectionHeader('Registered Cameras'),
            const SizedBox(height: 12),
            _CameraList(isDark: isDark, cardCol: cardCol, divCol: divCol),
            const SizedBox(height: 28),

            // ── Add new camera form ──────────────────────────────────────
            const _SectionHeader('Add New Camera'),
            const SizedBox(height: 12),

            _ThemedField(
              controller  : _nameController,
              label       : 'Camera Name',
              hint        : 'e.g. Main Gate Entry Cam',
              icon        : Icons.videocam_rounded,
              isDark      : isDark,
              validator   : (v) =>
                  (v == null || v.trim().isEmpty) ? 'Camera name required' : null,
            ),
            const SizedBox(height: 14),

            _ThemedField(
              controller  : _ipController,
              label       : 'RTSP / IP Address',
              hint        : 'rtsp://admin:pass@192.168.1.108:554/stream1',
              icon        : Icons.link_rounded,
              keyboardType: TextInputType.url,
              isDark      : isDark,
              validator   : _validateUrl,
            ),
            const SizedBox(height: 14),

            // ── Gate Number dropdown ─────────────────────────────────────
            _ThemedDropdown<int>(
              label    : 'Gate Number',
              icon     : Icons.door_front_door_rounded,
              value    : _gateNo,
              isDark   : isDark,
              items    : List.generate(
                6,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(
                    'Gate ${i + 1}',
                    style: TextStyle(color: isDark ? Colors.white : cs.onSurface),
                  ),
                ),
              ),
              onChanged: (v) => setState(() => _gateNo = v ?? 1),
            ),
            const SizedBox(height: 14),

            // ── IN / OUT direction toggle ────────────────────────────────
            Container(
              padding   : const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color       : isDark
                    ? Colors.white.withOpacity(0.04)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border      : Border.all(color: divCol),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.swap_horiz_rounded,
                        color: cs.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('Direction',
                        style: TextStyle(
                            color    : cs.onSurface.withOpacity(0.75),
                            fontSize : 13,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _DirectionToggle(
                        label   : 'ENTRY (IN)',
                        icon    : Icons.login_rounded,
                        selected: _direction == 'IN',
                        color   : Colors.greenAccent.shade400,
                        isDark  : isDark,
                        onTap   : () => setState(() => _direction = 'IN'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DirectionToggle(
                        label   : 'EXIT (OUT)',
                        icon    : Icons.logout_rounded,
                        selected: _direction == 'OUT',
                        color   : Colors.redAccent,
                        isDark  : isDark,
                        onTap   : () => setState(() => _direction = 'OUT'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Save button ──────────────────────────────────────────────
            SizedBox(
              width : double.infinity,
              height: 54,
              child : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _isSaving ? null : _save,
                icon : _isSaving
                    ? SizedBox(
                        width : 18,
                        height: 18,
                        child : CircularProgressIndicator(
                            color: cs.onPrimary, strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSaving ? 'Saving...' : 'REGISTER CAMERA',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionHeader — adapts to theme via context
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color     : Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
        fontWeight: FontWeight.bold,
        fontSize  : 14,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThemedField — text input that respects dark/light
// ─────────────────────────────────────────────────────────────────────────────
class _ThemedField extends StatelessWidget {
  final TextEditingController     controller;
  final String                    label;
  final String                    hint;
  final IconData                  icon;
  final bool                      isDark;
  final TextInputType?            keyboardType;
  final String? Function(String?)? validator;

  const _ThemedField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor  = isDark ? Colors.white          : cs.onSurface;
    final labelColor = isDark ? Colors.white54        : cs.onSurface.withOpacity(0.6);
    final hintColor  = isDark ? Colors.white24        : cs.onSurface.withOpacity(0.35);
    final fillColor  = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.03);
    final borderCol  = isDark ? Colors.white12        : cs.outline;

    return TextFormField(
      controller  : controller,
      keyboardType: keyboardType,
      style       : TextStyle(color: textColor),
      validator   : validator,
      decoration  : InputDecoration(
        labelText  : label,
        hintText   : hint,
        labelStyle : TextStyle(color: labelColor),
        hintStyle  : TextStyle(color: hintColor, fontSize: 12),
        prefixIcon : Icon(icon, color: cs.primary),
        filled     : true,
        fillColor  : fillColor,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide  : BorderSide(color: borderCol)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide  : BorderSide(color: borderCol)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide  : BorderSide(color: cs.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide  : const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide  : const BorderSide(color: Colors.redAccent, width: 1.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ThemedDropdown — dropdown that respects dark/light
// ─────────────────────────────────────────────────────────────────────────────
class _ThemedDropdown<T> extends StatelessWidget {
  final String                   label;
  final IconData                 icon;
  final T                        value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?)        onChanged;
  final bool                     isDark;

  const _ThemedDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final fillColor = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.03);
    final borderCol = isDark ? Colors.white12 : cs.outline;
    final textColor = isDark ? Colors.white   : cs.onSurface;
    final iconColor = isDark ? Colors.white38 : cs.onSurface.withOpacity(0.5);
    final dropBg    = isDark ? const Color(0xFF1C1C3A) : Colors.white;

    return Container(
      padding   : const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color       : fillColor,
        borderRadius: BorderRadius.circular(14),
        border      : Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value        : value,
                items        : items,
                onChanged    : onChanged,
                dropdownColor: dropBg,
                style        : TextStyle(color: textColor),
                icon         : Icon(Icons.arrow_drop_down_rounded, color: iconColor),
                isExpanded   : true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DirectionToggle — IN / OUT toggle button
// ─────────────────────────────────────────────────────────────────────────────
class _DirectionToggle extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final bool      selected;
  final Color     color;
  final bool      isDark;
  final VoidCallback onTap;

  const _DirectionToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final unselCol = isDark ? Colors.white38 : Colors.black38;
    final unselBd  = isDark ? Colors.white24 : Colors.black26;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration  : const Duration(milliseconds: 160),
        padding   : const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color       : selected ? color.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border      : Border.all(
            color: selected ? color : unselBd,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: selected ? color : unselCol, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color     : selected ? color : unselCol,
                    fontWeight: FontWeight.bold,
                    fontSize  : 12)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CameraList — live list of registered cameras, fully theme-aware
// ─────────────────────────────────────────────────────────────────────────────
class _CameraList extends StatelessWidget {
  final bool  isDark;
  final Color cardCol;
  final Color divCol;

  const _CameraList({
    required this.isDark,
    required this.cardCol,
    required this.divCol,
  });

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final titleStyle  = TextStyle(
        color: cs.onSurface, fontWeight: FontWeight.w600);
    final subStyle    = TextStyle(
        color: cs.onSurface.withOpacity(0.5), fontSize: 11);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cameras')
          .orderBy('addedAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No cameras registered yet.',
              style: TextStyle(
                  color: cs.onSurface.withOpacity(0.45), fontSize: 13),
            ),
          );
        }

        return Column(
          children: snap.data!.docs.map((doc) {
            final d        = doc.data() as Map<String, dynamic>;
            final isActive = d['status'] == 'active';
            final accentCol = isActive
                ? Colors.greenAccent.shade400
                : cs.onSurface.withOpacity(0.3);

            return Container(
              margin    : const EdgeInsets.only(bottom: 8),
              padding   : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color       : cardCol,
                borderRadius: BorderRadius.circular(14),
                border      : Border.all(
                  color: isActive
                      ? Colors.greenAccent.withOpacity(isDark ? 0.3 : 0.5)
                      : divCol,
                ),
              ),
              child: Row(children: [
                Icon(Icons.videocam_rounded, color: accentCol, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['cameraName'] ?? '—', style: titleStyle),
                      const SizedBox(height: 2),
                      Text(
                        'Gate ${d['gateNo']} • ${d['direction']} • ${d['ipAddress'] ?? ''}',
                        style: subStyle,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value      : isActive,
                  activeThumbColor: Colors.greenAccent.shade400,
                  onChanged  : (val) {
                    FirebaseFirestore.instance
                        .collection('cameras')
                        .doc(doc.id)
                        .update({'status': val ? 'active' : 'inactive'});
                  },
                ),
              ]),
            );
          }).toList(),
        );
      },
    );
  }
}
