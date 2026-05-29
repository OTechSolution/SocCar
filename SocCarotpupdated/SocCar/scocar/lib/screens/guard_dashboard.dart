import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_sort_service.dart';
import '../services/notification_service.dart';
import '../main.dart' show AppTokens, themeNotifier;

import 'delivery_request_card.dart';
import 'unified_entry_form.dart';
import 'active_visitors_tab.dart';
import 'vehicle_detection_screen.dart';
import 'manual_movement_sheet.dart';   // ← Manual movement backup option

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  String? _guardId;
  bool    _tokenSaved         = false;
  String  _fetchedGuardName   = 'Guard On Duty';

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> _fetchGuardProfile(String guardId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('guards')
          .doc(guardId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        setState(() {
          _fetchedGuardName =
              data['guardName'] ?? data['name'] ?? 'Guard On Duty';
        });
      }
    } catch (e) {
      debugPrint('Guard profile fetch error: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && _guardId == null) {
      setState(() => _guardId = args);
      _fetchGuardProfile(args);
    }
    if (_guardId != null && !_tokenSaved) {
      _tokenSaved = true;
      NotificationService().saveGuardToken(_guardId!);
    }
  }

  // ── Delivery request actions ───────────────────────────────────────────────

  Future<void> _allowDeliveryEntry(String docId, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status'     : 'COMPLETED',
      'completedAt': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance.collection('logs').add({
      'type'        : 'ENTRY',
      'entryType'   : 'Delivery',
      'company'     : 'DELIVERY',
      'flatNumber'  : flatNumber,
      'plateNumber' : '— DELIVERY —',
      'guardId'     : _guardId ?? 'GUARD',
      'guardName'   : _fetchedGuardName,
      'vehicleModel': 'Unknown',
      'driverName'  : 'Delivery Agent',
      'driverPic'   : 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300',
      'otpCode'     : null,
      'timestamp'   : FieldValue.serverTimestamp(),
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('✅ Delivery to $flatNumber — Entry logged & gate cleared.'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _denyEntry(String docId, String flatNumber) async {
    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({'status': 'DENIED'});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚫 Delivery to $flatNumber — Turned away.'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Reusable sub-widgets ───────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 24, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withOpacity(0.7) ??
              Colors.white70,
          fontSize  : 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ── Live stats banner ──────────────────────────────────────────────────────

  Widget _buildLiveStats() {
    return Container(
      margin : const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color       : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border      : Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn('On Duty',         _fetchedGuardName, Colors.greenAccent),
          Container(width: 1, height: 40, color: Theme.of(context).dividerColor),
          _statColumn('Terminal Status', 'SECURE',          Colors.cyanAccent),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, Color highlight) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(label,
            style: TextStyle(
                color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.6) ??
                    Colors.white38,
                fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: isDark ? highlight : highlight.withOpacity(0.85),
                fontWeight: FontWeight.bold,
                fontSize  : 15)),
      ],
    );
  }

  // ── Vehicle movement section — ANPR camera + Manual backup ────────────────
  // Both options live side-by-side so guards always have a fallback.
  // ANPR: automatic plate reading via VehicleDetectionScreen.
  // Manual: hand-typed log via ManualMovementSheet (for power/camera outages).

  Widget _buildVehicleMovementSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Card colours
    final anprBg  = isDark ? const Color(0xFF0D1F2D) : const Color(0xFFE8F4FD);
    final anprBd  = isDark ? const Color(0xFF1A3A50) : const Color(0xFFB3D9F5);
    final anprTit = isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1);
    final anprSub = isDark ? const Color(0xFF4A90AA) : const Color(0xFF5B9CBD);

    final manBg   = isDark ? const Color(0xFF1A1200) : const Color(0xFFFFFBE6);
    final manBd   = isDark ? const Color(0xFF3A2E00) : const Color(0xFFFFE082);
    final manTit  = isDark ? Colors.orangeAccent      : const Color(0xFFE65100);
    final manSub  = isDark ? const Color(0xFF8A7040)  : const Color(0xFF8D6E63);
    final arrowCol= isDark ? Colors.white24           : Colors.grey.shade400;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [

          // ── ANPR Card (left / primary) ─────────────────────────────────
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => VehicleDetectionScreen(guardId: _guardId)),
              ),
              child: Container(
                padding    : const EdgeInsets.all(16),
                decoration : BoxDecoration(
                  color       : anprBg,
                  borderRadius: BorderRadius.circular(18),
                  border      : Border.all(color: anprBd, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width : 44, height: 44,
                          decoration: BoxDecoration(
                            color       : AppTokens.cyanAction.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.videocam_rounded,
                            color: AppTokens.cyanAction, size: 24,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color       : AppTokens.cyanAction.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: AppTokens.cyanAction.withOpacity(0.3)),
                          ),
                          child: const Text('AUTO',
                              style: TextStyle(
                                  color      : AppTokens.cyanAction,
                                  fontSize   : 9,
                                  fontWeight : FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('ANPR\nCAMERA',
                        style: TextStyle(
                          color        : anprTit,
                          fontWeight   : FontWeight.bold,
                          fontSize     : 13,
                          letterSpacing: 0.6,
                          height       : 1.3,
                        )),
                    const SizedBox(height: 5),
                    Text(
                      'Scan plate — entry/exit logged automatically.',
                      style: TextStyle(color: anprSub, fontSize: 10.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── Manual Movement Card (right / backup) ─────────────────────
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: () => ManualMovementSheet.show(
                context,
                guardId  : _guardId,
                guardName: _fetchedGuardName,
              ),
              child: Container(
                padding    : const EdgeInsets.all(16),
                decoration : BoxDecoration(
                  color       : manBg,
                  borderRadius: BorderRadius.circular(18),
                  border      : Border.all(color: manBd, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width : 44, height: 44,
                          decoration: BoxDecoration(
                            color       : Colors.orangeAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: Colors.orangeAccent, size: 24,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color       : Colors.orangeAccent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orangeAccent.withOpacity(0.35)),
                          ),
                          child: const Text('BACKUP',
                              style: TextStyle(
                                  color      : Colors.orangeAccent,
                                  fontSize   : 9,
                                  fontWeight : FontWeight.bold,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('MANUAL\nENTRY',
                        style: TextStyle(
                          color        : manTit,
                          fontWeight   : FontWeight.bold,
                          fontSize     : 13,
                          letterSpacing: 0.6,
                          height       : 1.3,
                        )),
                    const SizedBox(height: 5),
                    Text(
                      'Type flat.',
                      style: TextStyle(color: manSub, fontSize: 10.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ANPR card (full-width, kept for the FAB and backward compat) ────────────
  Widget _buildAnprCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg  = isDark ? const Color(0xFF0D1F2D) : const Color(0xFFE8F4FD);
    final border  = isDark ? const Color(0xFF1A3A50)  : const Color(0xFFB3D9F5);
    final titleCol= isDark ? const Color(0xFF7DD3FC)  : const Color(0xFF0369A1);
    final subCol  = isDark ? const Color(0xFF4A90AA)  : const Color(0xFF5B9CBD);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VehicleDetectionScreen(guardId: _guardId)),
        ),
        child: Container(
          width  : double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color       : cardBg,
            borderRadius: BorderRadius.circular(20),
            border      : Border.all(color: border, width: 1.5),
          ),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color       : AppTokens.cyanAction.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.videocam_rounded,
                  color: AppTokens.cyanAction, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ANPR AUTO-LOG',
                      style: TextStyle(
                          color        : titleCol,
                          fontWeight   : FontWeight.bold,
                          fontSize     : 14,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 4),
                  Text(
                    'Point camera at a number plate — vehicle ENTRY/EXIT logged automatically.',
                    style: TextStyle(color: subCol, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_ios_rounded,
                color: isDark ? Colors.white24 : const Color(0xFFB3D9F5),
                size : 16),
          ]),
        ),
      ),
    );
  }

  // ── Main entry button (Delivery / Visitor) ────────────────────────────────

  Widget _buildUnifiedEntryButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width : double.infinity,
        height: 58,
        child : ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyanAccent,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation  : 6,
            shadowColor: Colors.cyanAccent.withOpacity(0.35),
          ),
          onPressed: () => UnifiedEntryForm.show(context, guardId: _guardId),
          icon : const Icon(Icons.add_circle_rounded, color: Colors.black, size: 22),
          label: const Text(
            'DELIVERY / VISITOR ENTRY',
            style: TextStyle(
              fontWeight  : FontWeight.w900,
              letterSpacing: 1.1,
              fontSize    : 14,
            ),
          ),
        ),
      ),
    );
  }

  // ── Recent logs stream ─────────────────────────────────────────────────────

  Widget _buildLogsStream() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(6)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Text(
              'No recent logs recorded.',
              style: TextStyle(
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withOpacity(0.6)),
            ),
          );
        }

        final sortedDocs = LogSortService.sort(
          snapshot.data!.docs.toList(),
          direction: SortDirection.desc,
        );

        return ListView.builder(
          shrinkWrap: true,
          physics   : const NeverScrollableScrollPhysics(),
          itemCount : sortedDocs.length,
          itemBuilder: (context, index) {
            final log      = sortedDocs[index].data() as Map<String, dynamic>;
            final String type      = log['type']      ?? 'ENTRY';
            final String entryType = log['entryType'] ?? '';
            final bool   isAnpr    = log['source']    == 'ANPR_CAMERA';

            final String subtitle = [
              if (isAnpr) '📷 ANPR',
              if (entryType.isNotEmpty && !isAnpr) entryType,
              if (log['driverName'] != null)
                log['driverName'] as String,
              if ((log['plateNumber'] ?? '').isNotEmpty &&
                  log['plateNumber'] != '— DELIVERY —')
                log['plateNumber'] as String,
            ].join(' · ');

            final Color typeColor = type == 'ENTRY'
                ? Colors.greenAccent
                : Colors.orangeAccent;

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Container(
                width : 36,
                height: 36,
                decoration: BoxDecoration(
                  color       : typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  type == 'ENTRY'
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  color: typeColor,
                  size : 18,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      log['company'] ?? log['flatNumber'] ?? '—',
                      style: TextStyle(
                          color     : Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize  : 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (isAnpr)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color       : AppTokens.cyanAction.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border      : Border.all(
                            color: AppTokens.cyanAction.withOpacity(0.3)),
                      ),
                      child: const Text('ANPR',
                          style: TextStyle(
                              color    : AppTokens.cyanAction,
                              fontSize : 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                    ),
                ],
              ),
              subtitle: subtitle.isNotEmpty
                  ? Text(
                      subtitle,
                      style: TextStyle(
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withOpacity(0.7),
                          fontSize: 12),
                    )
                  : null,
              trailing: Text(
                'Just now',
                style: TextStyle(
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withOpacity(0.4),
                    fontSize: 11),
              ),
            );
          },
        );
      },
    );
  }

  // ── Live delivery requests ─────────────────────────────────────────────────

  Widget _buildLiveDeliveryRequests() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('status',
              whereIn: ['PENDING', 'APPROVED', 'DENIED', 'TIMEOUT', 'ON_HOLD'])
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(color: Colors.cyanAccent)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color       : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border      : Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Center(
                child: Text(
                  'No active delivery requests.',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics   : const NeverScrollableScrollPhysics(),
          itemCount : snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc  = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return DeliveryRequestCard(
              docId        : doc.id,
              flat         : data['flatNumber'] ?? '?',
              company      : data['company']    ?? 'DELIVERY',
              status       : data['status']     ?? 'PENDING',
              residentPhone: data['residentPhone'],
              onAllowEntry : () =>
                  _allowDeliveryEntry(doc.id, data['flatNumber'] ?? ''),
              onDenyEntry  : () =>
                  _denyEntry(doc.id, data['flatNumber'] ?? ''),
            );
          },
        );
      },
    );
  }

  // ── Vehicle Verification Badge (AppBar icon with red dot) ─────────────────

  /// Streams pending-verification vehicles and wraps the car icon with a red
  /// notification badge showing the count.
  Widget _buildVehicleVerificationBadge(Color iconColor) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vehicles')
          .where('verificationStatus', isEqualTo: 'PENDING')
          .snapshots(),
      builder: (context, snapshot) {
        final int pendingCount =
            snapshot.hasData ? snapshot.data!.docs.length : 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: Icon(Icons.directions_car_rounded, color: iconColor),
              tooltip: 'Verify New Vehicles',
              onPressed: () => _showVehicleVerificationSheet(context),
            ),
            if (pendingCount > 0)
              Positioned(
                right: 6,
                top  : 6,
                child: IgnorePointer(
                  child: Container(
                    width : 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        pendingCount > 9 ? '9+' : '$pendingCount',
                        style: const TextStyle(
                          color     : Colors.white,
                          fontSize  : 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Bottom sheet listing all vehicles with verificationStatus == 'PENDING'.
  /// Guard sees plate, owner, flat and can ACCEPT or DENY each one.
  void _showVehicleVerificationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize    : 0.4,
          maxChildSize    : 0.92,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color       : Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin : const EdgeInsets.only(top: 12, bottom: 8),
                    width  : 40,
                    height : 4,
                    decoration: BoxDecoration(
                      color       : Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color       : Colors.redAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.directions_car_rounded,
                              color: Colors.redAccent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VEHICLE VERIFICATION',
                                style: TextStyle(
                                  fontWeight  : FontWeight.bold,
                                  fontSize    : 15,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              Text(
                                'Match plate on car, then Accept or Deny',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('vehicles')
                          .where('verificationStatus', isEqualTo: 'PENDING')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.cyanAccent));
                        }
                        if (!snapshot.hasData ||
                            snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.verified_rounded,
                                    size: 52,
                                    color: Colors.greenAccent.withOpacity(0.6)),
                                const SizedBox(height: 12),
                                const Text('All vehicles verified!',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 15)),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data!.docs;
                        return ListView.builder(
                          controller: scrollController,
                          padding   : const EdgeInsets.all(16),
                          itemCount : docs.length,
                          itemBuilder: (context, index) {
                            final doc  = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final String plate = data['plateNumber'] ?? '—';
                            final String owner = data['ownerName']   ?? '—';
                            final String flat  = data['flatNumber']  ?? '—';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.3),
                                    width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Plate + pending badge
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.black87,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.white24),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.directions_car_rounded,
                                                color : Colors.cyanAccent,
                                                size  : 14),
                                            const SizedBox(width: 6),
                                            Text(
                                              plate,
                                              style: const TextStyle(
                                                color     : Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize  : 14,
                                                fontFamily: 'monospace',
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.redAccent
                                                  .withOpacity(0.4)),
                                        ),
                                        child: const Text(
                                          'PENDING',
                                          style: TextStyle(
                                            color     : Colors.redAccent,
                                            fontSize  : 10,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  // Owner + flat info
                                  Row(children: [
                                    Icon(Icons.person_outline_rounded,
                                        size : 14,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 5),
                                    Text(owner,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color)),
                                    const SizedBox(width: 16),
                                    Icon(Icons.apartment_rounded,
                                        size : 14,
                                        color: Colors.grey.shade500),
                                    const SizedBox(width: 5),
                                    Text('Flat $flat',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.color)),
                                  ]),
                                  const SizedBox(height: 14),
                                  // Accept / Deny buttons
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          await doc.reference.update({
                                            'verificationStatus': 'DENIED',
                                            'verifiedBy'        : _guardId,
                                            'verifiedAt'        :
                                                FieldValue.serverTimestamp(),
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content: Text(
                                                  '🚫 $plate — vehicle denied.'),
                                              backgroundColor: Colors.red.shade700,
                                            ));
                                          }
                                        },
                                        icon : const Icon(Icons.close_rounded,
                                            size: 16),
                                        label: const Text('DENY'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                          side: BorderSide(
                                              color: Colors.redAccent
                                                  .withOpacity(0.5)),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () async {
                                          await doc.reference.update({
                                            'verificationStatus': 'APPROVED',
                                            'verifiedBy'        : _guardId,
                                            'verifiedAt'        :
                                                FieldValue.serverTimestamp(),
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                              content: Text(
                                                  '✅ $plate — vehicle approved!'),
                                              backgroundColor:
                                                  Colors.green.shade700,
                                            ));
                                          }
                                        },
                                        icon : const Icon(
                                            Icons.check_rounded,
                                            size: 16),
                                        label: const Text('ACCEPT'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Resolve AppBar colours from theme so light mode works correctly.
    final appBarBg      = Theme.of(context).appBarTheme.backgroundColor
                          ?? Theme.of(context).colorScheme.surface;
    final onAppBar      = Theme.of(context).appBarTheme.foregroundColor
                          ?? Theme.of(context).colorScheme.onSurface;
    final iconColor     = onAppBar.withOpacity(0.85);
    final iconColorSoft = onAppBar.withOpacity(0.55);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: appBarBg,
          foregroundColor: Colors.white,
          centerTitle    : true,
          elevation      : 0,
          title: Text(
            _guardId != null ? 'Guard: $_guardId' : 'Guard Control Terminal',
            style: TextStyle(fontWeight: FontWeight.bold, color: onAppBar),
          ),
          actions: [
            // ── 0. Vehicle Verification (new vehicle badge) ─────────────
            _buildVehicleVerificationBadge(iconColor),

            // ── 1. ANPR Camera ──────────────────────────────────────────
            IconButton(
              icon   : Icon(Icons.videocam_rounded, color: iconColor),
              tooltip: 'ANPR Vehicle Scan',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VehicleDetectionScreen(guardId: _guardId),
                ),
              ),
            ),

            // ── 2. Camera Registration ──────────────────────────────────
            IconButton(
              icon   : Icon(Icons.settings_input_component_rounded,
                  color: iconColor),
              tooltip: 'Manage Cameras',
              onPressed: () => Navigator.pushNamed(context, '/cameras'),
            ),

            // ── 3. Theme Toggle ─────────────────────────────────────────
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: iconColor,
                ),
                tooltip: mode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
                onPressed: () => themeNotifier.value =
                    mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
              ),
            ),

            // ── 4. Logout ───────────────────────────────────────────────
            IconButton(
              icon     : Icon(Icons.logout_rounded, color: iconColorSoft),
              tooltip  : 'Logout',
              onPressed: () {
                if (_guardId != null) {
                  FirebaseFirestore.instance
                      .collection('guards')
                      .where('guardId', isEqualTo: _guardId)
                      .get()
                      .then((snap) {
                    for (final doc in snap.docs) {
                      doc.reference.update({
                        'onDuty' : false,
                        'dutyEnd': FieldValue.serverTimestamp(),
                      });
                    }
                  }).catchError((_) {});
                }
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor      : Theme.of(context).colorScheme.primary,
            labelColor          : Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
            tabs: const [
              Tab(icon: Icon(Icons.dashboard_rounded),  text: 'Control'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'Inside'),
            ],
          ),
        ),

        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ── ANPR FAB (left) ────────────────────────────────────────
              FloatingActionButton(
                heroTag        : 'anpr_fab',
                onPressed      : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VehicleDetectionScreen(guardId: _guardId),
                  ),
                ),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0E4163)
                    : const Color(0xFF0277BD),
                foregroundColor: Colors.white,
                elevation      : 6,
                tooltip        : 'ANPR Vehicle Scan',
                child          : const Icon(Icons.videocam_rounded, size: 26),
              ),

              // ── Manual Movement FAB (centre) ───────────────────────────
              FloatingActionButton(
                heroTag        : 'manual_fab',
                onPressed      : () => ManualMovementSheet.show(
                  context,
                  guardId  : _guardId,
                  guardName: _fetchedGuardName,
                ),
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2D1A00)
                    : const Color(0xFFE65100),
                foregroundColor: Colors.white,
                elevation      : 6,
                tooltip        : 'Manual Movement Log',
                child          : const Icon(Icons.edit_note_rounded, size: 26),
              ),

              // ── Entry form FAB (right) ─────────────────────────────────
              FloatingActionButton.extended(
                heroTag        : 'entry_fab',
                onPressed      : () =>
                    UnifiedEntryForm.show(context, guardId: _guardId),
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                icon           : const Icon(Icons.add_rounded),
                label          : const Text(
                  'NEW ENTRY',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
                elevation: 8,
              ),
            ],
          ),
        ),

        body: TabBarView(
          children: [
            // ── Control Tab ──────────────────────────────────────────────
            ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                // Status banner
                _buildLiveStats(),

                // ── Gate Entry section ───────────────────────────────────
                _sectionHeader('Gate Entry'),
                _buildUnifiedEntryButton(),           // Delivery / Visitor
                const SizedBox(height: 12),

                // ── ANPR + Manual Movement section ───────────────────────
                _sectionHeader('Vehicle Movement Log'),
                _buildVehicleMovementSection(),

                // ── Delivery requests ────────────────────────────────────
                _sectionHeader('Live Delivery Requests'),
                _buildLiveDeliveryRequests(),

                // ── Recent logs ──────────────────────────────────────────
                _sectionHeader('Recent Gate Logs'),
                _buildLogsStream(),

                const SizedBox(height: 32),
              ],
            ),

            // ── Inside Tab ───────────────────────────────────────────────
            const ActiveVisitorsTab(),
          ],
        ),
      ),
    );
  }
}
