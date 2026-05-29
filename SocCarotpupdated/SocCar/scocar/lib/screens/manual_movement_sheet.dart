// ============================================================================
// manual_movement_sheet.dart
// ============================================================================
// A dedicated bottom sheet for MANUAL vehicle movement logging.
//
// This is the backup option for when the ANPR camera cannot be used
// (power cut, camera offline, low-light, etc.).
//
// What it does:
//   • Guard selects ENTRY or EXIT
//   • Enters Flat Number (mandatory — log goes to that flat's history)
//   • Enters Vehicle Plate Number (mandatory)
//   • Enters Driver / Person Name (optional)
//   • Adds Notes (optional)
//   • On SUBMIT → writes directly to Firestore 'logs' collection with:
//       type        : 'ENTRY' | 'EXIT'
//       entryType   : 'General Movement'
//       source      : 'MANUAL'           ← distinguishes from ANPR logs
//       flatNumber  : e.g. 'A-402'
//       plateNumber : e.g. 'MH12AB1234'
//       driverName  : (optional)
//       notes       : (optional)
//       guardId     : logged-in guard
//       guardName   : fetched guard name
//       timestamp   : FieldValue.serverTimestamp()
//
// No approval flow — movement logs go directly to the logs collection
// (same as ANPR auto-logs) so residents can see them in Activity History.
//
// USAGE (from GuardDashboard):
//   ManualMovementSheet.show(
//     context,
//     guardId:   _guardId,
//     guardName: _fetchedGuardName,
//   );
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../main.dart' show AppTokens, themeNotifier;

// ── Direction enum ────────────────────────────────────────────────────────────
enum _MovDir { entry, exit }

extension _MovDirExt on _MovDir {
  String get logValue => this == _MovDir.entry ? 'ENTRY' : 'EXIT';
  String get label    => this == _MovDir.entry ? 'ENTRY' : 'EXIT';

  String get actionLabel =>
      this == _MovDir.entry ? 'LOG VEHICLE ENTRY' : 'LOG VEHICLE EXIT';

  IconData get icon =>
      this == _MovDir.entry ? Icons.login_rounded : Icons.logout_rounded;

  Color get color =>
      this == _MovDir.entry ? Colors.greenAccent : Colors.orangeAccent;
}

// ── Public API ────────────────────────────────────────────────────────────────
class ManualMovementSheet extends StatefulWidget {
  final String? guardId;
  final String  guardName;

  const ManualMovementSheet({
    super.key,
    this.guardId,
    required this.guardName,
  });

  static Future<void> show(
    BuildContext context, {
    String? guardId,
    String  guardName = 'Guard On Duty',
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context            : context,
      isScrollControlled : true,
      useSafeArea        : true,
      barrierColor       : isDark
          ? Colors.black.withOpacity(0.75)
          : Colors.black.withOpacity(0.45),
      backgroundColor    : Colors.transparent,
      builder            : (_) => ManualMovementSheet(
        guardId  : guardId,
        guardName: guardName,
      ),
    );
  }

  @override
  State<ManualMovementSheet> createState() => _ManualMovementSheetState();
}

class _ManualMovementSheetState extends State<ManualMovementSheet> {

  // ── Controllers ─────────────────────────────────────────────────────────────
  final _flatCtrl   = TextEditingController();
  final _plateCtrl  = TextEditingController();
  final _driverCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();

  // ── Focus nodes ─────────────────────────────────────────────────────────────
  final _flatFocus   = FocusNode();
  final _plateFocus  = FocusNode();
  final _driverFocus = FocusNode();
  final _notesFocus  = FocusNode();

  // ── State ────────────────────────────────────────────────────────────────────
  _MovDir _direction = _MovDir.entry;
  bool    _isSaving  = false;

  @override
  void dispose() {
    _flatCtrl.dispose();
    _plateCtrl.dispose();
    _driverCtrl.dispose();
    _notesCtrl.dispose();
    _flatFocus.dispose();
    _plateFocus.dispose();
    _driverFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  // ── Submit ────────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final flat  = _flatCtrl.text.trim().toUpperCase();
    final plate = _plateCtrl.text.trim().toUpperCase();

    if (flat.isEmpty) {
      _toast('Flat number is required.', Colors.orange);
      return;
    }
    if (plate.isEmpty) {
      _toast('Vehicle plate number is required.', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('logs').add({
        'type'       : _direction.logValue,      // 'ENTRY' or 'EXIT'
        'entryType'  : 'General Movement',
        'source'     : 'MANUAL',                 // distinguishes from ANPR
        'flatNumber' : flat,
        'plateNumber': plate,
        'driverName' : _driverCtrl.text.trim(),
        'company'    : _driverCtrl.text.trim().isNotEmpty
            ? _driverCtrl.text.trim()
            : plate,                             // fallback so logs list shows plate
        'notes'      : _notesCtrl.text.trim(),
        'guardId'    : widget.guardId ?? 'GUARD',
        'guardName'  : widget.guardName,
        'timestamp'  : FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);

      // Confirmation snack
      final msg = _direction == _MovDir.entry
          ? '✅ Vehicle ENTRY logged — Flat $flat · $plate'
          : '✅ Vehicle EXIT logged — Flat $flat · $plate';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: _direction.color == Colors.greenAccent
            ? Colors.green.shade700
            : Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (mounted) {
        _toast('Failed to log movement: $e', Colors.redAccent);
        setState(() => _isSaving = false);
      }
    }
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content        : Text(msg,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: bg,
        behavior       : SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color sheetBg   = isDark ? const Color(0xFF0A0A1A) : Colors.white;
    final Color handle    = isDark ? const Color(0xFF2A2A4A) : Colors.grey.shade300;
    final Color titleCol  = isDark ? Colors.white             : const Color(0xFF1A1F36);
    final Color subCol    = isDark ? const Color(0xFF5A5A8A)  : Colors.grey.shade500;
    final Color divider   = isDark ? const Color(0xFF1A1A3A)  : Colors.grey.shade200;
    final Color accentCol = _direction.color;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color       : sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: accentCol.withOpacity(0.4), width: 1.5),
          ),
        ),
        padding: EdgeInsets.only(
          left  : 20,
          right : 20,
          top   : 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize      : MainAxisSize.min,
            children: [

              // ── Handle bar ──────────────────────────────────────────────
              Center(
                child: Container(
                  width : 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: handle, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // ── Header ──────────────────────────────────────────────────
              Row(children: [
                // Icon box — colour follows direction
                AnimatedContainer(
                  duration   : const Duration(milliseconds: 220),
                  width      : 40, height: 40,
                  decoration : BoxDecoration(
                    color       : accentCol.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.swap_vert_rounded,
                    color: accentCol, size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MANUAL MOVEMENT LOG',
                        style: TextStyle(
                          color        : titleCol,
                          fontSize     : 16,
                          fontWeight   : FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        'Backup entry — use when camera is unavailable',
                        style: TextStyle(color: subCol, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),

                // Theme toggle (small)
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (_, mode, __) => GestureDetector(
                    onTap: () => themeNotifier.value =
                        mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
                    child: Container(
                      padding   : const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color       : isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        mode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        size : 16,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),
              Divider(color: divider, height: 1),
              const SizedBox(height: 20),

              // ── BACKUP notice banner ────────────────────────────────────
              Container(
                width  : double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color       : Colors.orangeAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.orangeAccent.withOpacity(0.35)),
                ),
                child: Row(children: [
                  const Icon(Icons.power_off_rounded,
                      color: Colors.orangeAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Camera offline or unavailable? Log vehicle movements '
                      'manually here. All logs are stored in the flat\'s Activity History.',
                      style: TextStyle(
                        color    : isDark ? Colors.orangeAccent.withOpacity(0.85) : Colors.orange.shade800,
                        fontSize : 11.5,
                        height   : 1.45,
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 22),

              // ── DIRECTION TOGGLE ────────────────────────────────────────
              _sectionLabel('MOVEMENT DIRECTION', isDark),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _DirectionChip(
                  dir     : _MovDir.entry,
                  selected: _direction == _MovDir.entry,
                  isDark  : isDark,
                  onTap   : () => setState(() => _direction = _MovDir.entry),
                )),
                const SizedBox(width: 10),
                Expanded(child: _DirectionChip(
                  dir     : _MovDir.exit,
                  selected: _direction == _MovDir.exit,
                  isDark  : isDark,
                  onTap   : () => setState(() => _direction = _MovDir.exit),
                )),
              ]),

              const SizedBox(height: 20),

              // ── FLAT NUMBER (mandatory) ────────────────────────────────
              _sectionLabel('RESIDENT FLAT NUMBER *', isDark),
              const SizedBox(height: 8),
              _buildField(
                controller : _flatCtrl,
                focusNode  : _flatFocus,
                hint       : 'e.g. A-402',
                icon       : Icons.apartment_rounded,
                action     : TextInputAction.next,
                onNext     : () => FocusScope.of(context).requestFocus(_plateFocus),
                isDark     : isDark,
                accent     : accentCol,
                capitalize : TextCapitalization.characters,
                formatters : [
                  TextInputFormatter.withFunction(
                    (_, v) => v.copyWith(text: v.text.toUpperCase()),
                  ),
                ],
                textStyle: TextStyle(
                  color        : isDark ? accentCol : const Color(0xFF1565C0),
                  fontWeight   : FontWeight.bold,
                  fontSize     : 16,
                  letterSpacing: 1.5,
                ),
              ),

              const SizedBox(height: 16),

              // ── VEHICLE PLATE (mandatory) ──────────────────────────────
              _sectionLabel('VEHICLE NUMBER PLATE *', isDark),
              const SizedBox(height: 8),
              _buildField(
                controller : _plateCtrl,
                focusNode  : _plateFocus,
                hint       : 'e.g. MH12AB1234',
                icon       : Icons.directions_car_rounded,
                action     : TextInputAction.next,
                onNext     : () => FocusScope.of(context).requestFocus(_driverFocus),
                isDark     : isDark,
                accent     : accentCol,
                capitalize : TextCapitalization.characters,
                formatters : [
                  TextInputFormatter.withFunction(
                    (_, v) => v.copyWith(text: v.text.toUpperCase()),
                  ),
                ],
                textStyle: TextStyle(
                  color        : isDark ? AppTokens.cyanAction : const Color(0xFF0277BD),
                  fontWeight   : FontWeight.bold,
                  fontSize     : 16,
                  letterSpacing: 2.5,
                  fontFamily   : 'monospace',
                ),
              ),

              const SizedBox(height: 16),

              // ── DRIVER NAME (optional) ─────────────────────────────────
              _sectionLabel('DRIVER / PERSON NAME (OPTIONAL)', isDark),
              const SizedBox(height: 8),
              _buildField(
                controller: _driverCtrl,
                focusNode : _driverFocus,
                hint      : 'e.g. Ramesh Kumar',
                icon      : Icons.person_outline_rounded,
                action    : TextInputAction.next,
                onNext    : () => FocusScope.of(context).requestFocus(_notesFocus),
                isDark    : isDark,
                accent    : accentCol,
              ),

              const SizedBox(height: 16),

              // ── NOTES (optional) ───────────────────────────────────────
              _sectionLabel('NOTES (OPTIONAL)', isDark),
              const SizedBox(height: 8),
              _buildField(
                controller: _notesCtrl,
                focusNode : _notesFocus,
                hint      : 'e.g. Regular vendor, no issues...',
                icon      : Icons.notes_rounded,
                action    : TextInputAction.done,
                onNext    : () => FocusScope.of(context).unfocus(),
                isDark    : isDark,
                accent    : accentCol,
                maxLines  : 2,
              ),

              const SizedBox(height: 28),

              // ── SUBMIT BUTTON ──────────────────────────────────────────
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                child: SizedBox(
                  width : double.infinity,
                  height: 58,
                  child : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentCol,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: accentCol.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation  : 6,
                      shadowColor: accentCol.withOpacity(0.4),
                    ),
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox(
                            width : 20, height: 20,
                            child : CircularProgressIndicator(
                                color: Colors.black, strokeWidth: 2.5))
                        : Icon(_direction.icon, size: 22, color: Colors.black),
                    label: Text(
                      _isSaving ? 'SAVING...' : _direction.actionLabel,
                      style: const TextStyle(
                        fontWeight   : FontWeight.w900,
                        fontSize     : 15,
                        letterSpacing: 0.9,
                        color        : Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section label ───────────────────────────────────────────────────────────
  Widget _sectionLabel(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      color        : isDark ? const Color(0xFF7A7AAA) : Colors.grey.shade500,
      fontSize     : 10,
      fontWeight   : FontWeight.w800,
      letterSpacing: 0.8,
    ),
  );

  // ── Generic field builder ───────────────────────────────────────────────────
  Widget _buildField({
    required TextEditingController controller,
    required FocusNode             focusNode,
    required String                hint,
    required IconData              icon,
    required TextInputAction       action,
    required VoidCallback          onNext,
    required bool                  isDark,
    required Color                 accent,
    TextCapitalization             capitalize = TextCapitalization.words,
    List<TextInputFormatter>       formatters = const [],
    TextStyle?                     textStyle,
    int                            maxLines   = 1,
  }) {
    final Color fill   = isDark ? const Color(0xFF13132A) : const Color(0xFFF5F7FF);
    final Color border = isDark ? const Color(0xFF2A2A4A) : const Color(0xFFCDD3E8);
    final Color hint_  = isDark ? const Color(0xFF3A3A5C) : Colors.grey.shade400;
    final Color txt    = isDark ? Colors.white             : const Color(0xFF1A1F36);

    return TextField(
      controller        : controller,
      focusNode         : focusNode,
      enabled           : !_isSaving,
      textInputAction   : action,
      onSubmitted       : (_) => onNext(),
      textCapitalization: capitalize,
      inputFormatters   : formatters,
      maxLines          : maxLines,
      style             : textStyle ?? TextStyle(color: txt, fontSize: 15),
      decoration: InputDecoration(
        hintText  : hint,
        hintStyle : TextStyle(color: hint_, fontSize: 14),
        prefixIcon: Icon(icon, color: accent, size: 20),
        filled    : true,
        fillColor : fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide  : BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide  : BorderSide(color: border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide  : BorderSide(color: accent, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide  : BorderSide(color: border.withOpacity(0.4)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

// ── Direction chip ──────────────────────────────────────────────────────────
class _DirectionChip extends StatelessWidget {
  final _MovDir      dir;
  final bool         selected;
  final bool         isDark;
  final VoidCallback onTap;

  const _DirectionChip({
    required this.dir,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color accent    = dir.color;
    final Color idleFill  = isDark ? const Color(0xFF13132A) : Colors.grey.shade100;
    final Color idleBorder= isDark ? const Color(0xFF2A2A4A) : Colors.grey.shade300;
    final Color idleText  = isDark ? Colors.white38           : Colors.grey.shade500;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve   : Curves.easeOut,
        padding : const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color       : selected ? accent : idleFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.transparent : idleBorder,
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color     : accent.withOpacity(0.32),
                  blurRadius: 12,
                  offset    : const Offset(0, 4))]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              dir.icon,
              size : 22,
              color: selected ? Colors.black : idleText,
            ),
            const SizedBox(width: 8),
            Text(
              dir.label,
              style: TextStyle(
                color        : selected ? Colors.black : idleText,
                fontWeight   : FontWeight.w900,
                fontSize     : 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
