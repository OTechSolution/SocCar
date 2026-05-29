// ─────────────────────────────────────────────────────────────────────────────
// AREA 1: DiscrepancyAlertOverlay
//
// Shows an amber full-screen overlay when the AI backend detects that the
// number plate matches a registered car, but the detected model does NOT match.
//
// DROP-IN: Import this file and call DiscrepancyAlertOverlay.show() anywhere
// in guard_dashboard.dart after receiving a 'discrepancy' status from /detect-vehicle.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Data returned by the /detect-vehicle FastAPI endpoint when status == 'discrepancy'
class VehicleDiscrepancy {
  final String plateNumber;
  final String registeredModel; // pulled from Firestore by backend
  final String detectedModel;  // what YOLO actually saw
  final String vehicleLogId;   // the /vehicleLogs doc to update with override result
  final String guardId;

  const VehicleDiscrepancy({
    required this.plateNumber,
    required this.registeredModel,
    required this.detectedModel,
    required this.vehicleLogId,
    required this.guardId,
  });

  factory VehicleDiscrepancy.fromJson(Map<String, dynamic> json) {
    return VehicleDiscrepancy(
      plateNumber: json['plateNumber'] ?? '',
      registeredModel: json['registeredModel'] ?? 'Unknown',
      detectedModel: json['detectedModel'] ?? 'Unknown',
      vehicleLogId: json['vehicleLogId'] ?? '',
      guardId: json['guardId'] ?? 'GUARD',
    );
  }
}

class DiscrepancyAlertOverlay extends StatefulWidget {
  final VehicleDiscrepancy discrepancy;
  final VoidCallback? onDismiss;

  const DiscrepancyAlertOverlay({
    super.key,
    required this.discrepancy,
    this.onDismiss,
  });

  /// Convenience: show as a full-screen dialog (blocks everything behind it)
  static Future<void> show(
    BuildContext context, {
    required VehicleDiscrepancy discrepancy,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.amber.withOpacity(0.18),
      builder: (_) => DiscrepancyAlertOverlay(discrepancy: discrepancy),
    );
  }

  @override
  State<DiscrepancyAlertOverlay> createState() =>
      _DiscrepancyAlertOverlayState();
}

class _DiscrepancyAlertOverlayState extends State<DiscrepancyAlertOverlay>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.85, end: 1.0).animate(_pulseController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Write override result to Firestore ──────────────────────────────────
  Future<void> _submitOverride(bool allowed) async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('vehicleLogs')
          .doc(widget.discrepancy.vehicleLogId)
          .update({
        'status': allowed ? 'override_allowed' : 'override_denied',
        'manual_override': true,
        'overrideGuardId': widget.discrepancy.guardId,
        'overrideAt': FieldValue.serverTimestamp(),
        'discrepancy': {
          'registeredModel': widget.discrepancy.registeredModel,
          'detectedModel': widget.discrepancy.detectedModel,
        },
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              allowed
                  ? '✅ Entry allowed by Guard ${widget.discrepancy.guardId} (manual override logged)'
                  : '🚫 Entry denied by Guard ${widget.discrepancy.guardId} (manual override logged)',
            ),
            backgroundColor: allowed ? Colors.green : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to log override: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _pulseAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1200),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amber, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withOpacity(0.35),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ─────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.amber, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'MODEL MISMATCH DETECTED',
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Plate: ${widget.discrepancy.plateNumber}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Side-by-side comparison ────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _ComparisonBox(
                        label: 'REGISTERED',
                        value: widget.discrepancy.registeredModel,
                        color: Colors.greenAccent,
                        icon: Icons.verified_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.compare_arrows_rounded,
                        color: Colors.white38, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ComparisonBox(
                        label: 'DETECTED',
                        value: widget.discrepancy.detectedModel,
                        color: Colors.redAccent,
                        icon: Icons.remove_red_eye_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Colors.amber, size: 14),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Plate registered but vehicle model does not match. Manual review required.',
                          style:
                              TextStyle(color: Colors.amber, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Override buttons ───────────────────────────────────
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.amber)
                    : Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.greenAccent,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              onPressed: () => _submitOverride(true),
                              icon: const Icon(Icons.door_sliding_rounded,
                                  size: 20),
                              label: const Text(
                                'ALLOW ENTRY  (Manual Override)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(
                                    color: Colors.redAccent, width: 1.5),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _submitOverride(false),
                              icon: const Icon(Icons.block_rounded, size: 20),
                              label: const Text(
                                'DENY ENTRY  (Manual Override)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 8),
                Text(
                  'Override will be logged with Guard ID: ${widget.discrepancy.guardId}',
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonBox extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;

  const _ComparisonBox({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8)),
          ]),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
