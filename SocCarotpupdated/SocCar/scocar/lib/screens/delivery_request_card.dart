import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart' show AppTokens;

// ─────────────────────────────────────────────────────────────────────────────
// DeliveryRequestCard — theme-aware delivery approval card
//
// FIX: Card background was hardcoded Color(0xFF141428) — invisible in light.
// Now resolves from AppTokens based on the current theme brightness.
// All internal text and border colors follow the same pattern.
// ─────────────────────────────────────────────────────────────────────────────

class DeliveryRequestCard extends StatefulWidget {
  final String  docId;
  final String  flat;
  final String  company;
  final String  status;
  final String? residentPhone;
  final VoidCallback onAllowEntry;
  final VoidCallback onDenyEntry;

  const DeliveryRequestCard({
    super.key,
    required this.docId,
    required this.flat,
    required this.company,
    required this.status,
    this.residentPhone,
    required this.onAllowEntry,
    required this.onDenyEntry,
  });

  @override
  State<DeliveryRequestCard> createState() => _DeliveryRequestCardState();
}

class _DeliveryRequestCardState extends State<DeliveryRequestCard> {
  // ── Countdown for PENDING requests (2-minute window) ──────────────────────
  static const int _timeoutSeconds = 120;

  late int    _remaining;
  Timer?      _timer;

  @override
  void initState() {
    super.initState();
    _remaining = _timeoutSeconds;
    if (widget.status == 'PENDING') _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _remaining--;
        if (_remaining <= 0) t.cancel();
      });
    });
  }

  double get _progress => _remaining / _timeoutSeconds;

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Theme-resolved surface colors ──────────────────────────────────────
    final Color cardBg     = isDark ? AppTokens.darkSurface  : AppTokens.lightSurface;
    final Color textPrimary= isDark ? Colors.white           : AppTokens.lightTextPrimary;
    final Color textSecond = isDark ? Colors.white54         : AppTokens.lightTextSecond;
    final Color divider    = isDark ? AppTokens.darkDivider  : AppTokens.lightDivider;

    // ── Status color ───────────────────────────────────────────────────────
    Color statusColor;
    IconData statusIcon;

    switch (widget.status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusIcon  = Icons.cancel_rounded;
        break;
      case 'COMPLETED':
        statusColor = Colors.blueAccent;
        statusIcon  = Icons.verified_rounded;
        break;
      case 'ON_HOLD':
        statusColor = Colors.orangeAccent;
        statusIcon  = Icons.pause_circle_rounded;
        break;
      default: // PENDING
        statusColor = isDark ? Colors.cyanAccent : AppTokens.lightAccent;
        statusIcon  = Icons.pending_rounded;
    }

    final bool isPending = widget.status == 'PENDING';
    final bool isUrgent  = isPending && _remaining < 30;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color       : cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(
          color: statusColor.withOpacity(isPending ? 0.5 : 0.25),
          width: isPending ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color     : isDark ? Colors.black26 : Colors.grey.shade200,
            blurRadius: 8,
            offset    : const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // ── Top row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                // Company chip
                _Chip(
                  label    : widget.company,
                  color    : statusColor,
                  isDark   : isDark,
                ),
                const SizedBox(width: 8),
                // Flat chip
                _Chip(
                  label    : 'Flat ${widget.flat}',
                  color    : isDark ? Colors.white54 : AppTokens.lightTextSecond,
                  isDark   : isDark,
                ),
                const Spacer(),
                // Status icon + label
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 4),
                Text(
                  widget.status,
                  style: TextStyle(
                    color     : statusColor,
                    fontSize  : 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),

          // ── Countdown bar (PENDING only) ───────────────────────────────
          if (isPending) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value     : _progress,
                        minHeight : 4,
                        backgroundColor: isDark ? Colors.white10 : AppTokens.lightDivider,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isUrgent ? Colors.redAccent : statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_remaining}s',
                    style: TextStyle(
                      color    : isUrgent ? Colors.redAccent : textSecond,
                      fontSize : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Action buttons — vary by status ───────────────────────────

          // PENDING: Allow + Deny side-by-side
          if (isPending) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                      onPressed: widget.onAllowEntry,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Allow',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                            color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: widget.onDenyEntry,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Deny',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),

          // APPROVED by resident: guard must now physically allow entry
          ] else if (widget.status == 'APPROVED') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.greenAccent.withOpacity(0.35)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          size: 14, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Resident approved — tap below to log entry & open gate.',
                          style: TextStyle(
                              color: isDark
                                  ? Colors.greenAccent
                                  : Colors.green.shade700,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      onPressed: widget.onAllowEntry,
                      icon: const Icon(Icons.door_sliding_rounded, size: 18),
                      label: const Text('ALLOW ENTRY & LOG',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5)),
                    ),
                  ),
                ],
              ),
            ),

          // ON_HOLD: allow guard to allow or deny
          ] else if (widget.status == 'ON_HOLD') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        elevation: 0,
                      ),
                      onPressed: widget.onAllowEntry,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Allow',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                            color: Colors.redAccent, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: widget.onDenyEntry,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Deny',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Divider between cards (subtle) ─────────────────────────────
          Divider(height: 1, color: divider),
        ],
      ),
    );
  }

  String _resolvedNote(String status) {
    switch (status) {
      case 'APPROVED'  : return 'Approved by resident.';
      case 'DENIED'    : return 'Denied by resident.';
      case 'COMPLETED' : return 'Entry logged & completed.';
      case 'TIMEOUT'   : return 'Request timed out.';
      case 'ON_HOLD'   : return 'On hold — awaiting resident.';
      default          : return status;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Chip — internal themed badge
// ─────────────────────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  final bool   isDark;

  const _Chip({
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color       : color.withOpacity(isDark ? 0.12 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color     : color,
          fontSize  : 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
