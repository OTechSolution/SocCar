import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/log_sort_service.dart';
import '../services/notification_service.dart';
import '../services/alert_sound_service.dart';
import 'add_vehicle_screen.dart';
import '../main.dart' show themeNotifier;

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  String? _flatId;
  bool _tokenSaved = false;

  // Feature 6: Track last seen doc count to detect new arrivals
  int _lastPendingCount = 0;

  // ── Beep alert state ──────────────────────────────────────────────────────
  final AlertSoundService _alertSound = AlertSoundService();
  // Tracks which approval doc IDs are already beeping (prevents double-start)
  final Set<String> _alertingDocIds = {};

  @override
  void dispose() {
    _alertSound.stopAlert();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final String? args =
        ModalRoute.of(context)?.settings.arguments as String?;
    if (args != null && args != _flatId) {
      setState(() => _flatId = args);
      if (!_tokenSaved) {
        _tokenSaved = true;
        NotificationService().saveResidentToken(args);
      }
    }
  }

  Future<void> _handleApproval({
    required String docId,
    required String company,
    required String guardId,
    required bool approved,
  }) async {
    final String newStatus = approved ? 'APPROVED' : 'DENIED';

    await FirebaseFirestore.instance
        .collection('approvals')
        .doc(docId)
        .update({
      'status': newStatus,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService().notifyGuardOfDecision(
      guardId: guardId,
      flatNumber: _flatId ?? 'UNKNOWN',
      company: company,
      approved: approved,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approved
            ? '✅ $company delivery approved — Guard has been notified.'
            : '🚫 $company delivery denied — Guard has been notified.'),
        backgroundColor: approved ? Colors.green : Colors.redAccent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Feature 1: Use theme colors
    final theme = Theme.of(context);
    final String activeFlat = _flatId ?? 'UNKNOWN';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'FLAT $activeFlat',
            style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold),
          ),
          backgroundColor: theme.appBarTheme.backgroundColor,
          centerTitle: true,
          elevation: 0,
          actions: [
            // Dark/Light mode toggle
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
                tooltip: mode == ThemeMode.dark ? 'Light Mode' : 'Dark Mode',
                onPressed: () {
                  themeNotifier.value = mode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.logout_rounded,
                color: theme.colorScheme.onSurface.withOpacity(0.55),
              ),
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/'),
            ),
          ],
          bottom: TabBar(
            indicatorColor: theme.colorScheme.primary,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.45),
            tabs: const [
              Tab(icon: Icon(Icons.directions_car), text: 'My Vehicles'),
              Tab(icon: Icon(Icons.gpp_good_rounded), text: 'Gate Approvals'),
              Tab(icon: Icon(Icons.shield_rounded), text: 'Guard On Duty'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Activity'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Vehicles
            Column(
              children: [
                _buildProfileCard(activeFlat),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('REGISTERED VEHICLES',
                          style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                              letterSpacing: 1)),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AddVehicleScreen(defaultFlat: activeFlat)),
                        ),
                        icon: const Icon(Icons.add,
                            size: 16, color: Colors.black),
                        label: const Text('ADD VEHICLE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildVehicleList(activeFlat)),
              ],
            ),

            // TAB 2: Gate Approvals with driver profile
            _buildApprovalsList(activeFlat),

            // TAB 3: Guard On Duty
            _buildGuardOnDutyTab(),
            _ActivityHistoryTab(flatNumber: _flatId ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(String flatId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('residents')
          .doc(flatId)
          .snapshots(),
      builder: (context, snapshot) {
        String ownerName = 'Resident Owner';
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          ownerName = data?['ownerName'] ?? 'Resident Owner';
        }
        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white.withOpacity(0.25),
              child: const Icon(Icons.person_rounded, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ownerName,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 3),
                  Text('Apartment: $flatId',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7), fontSize: 13)),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildVehicleList(String flatId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vehicles')
          .where('flatNumber', isEqualTo: flatId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
              child: Text('No vehicles registered.',
                  style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5))));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final v = doc.data() as Map<String, dynamic>;
            final String verStatus = v['verificationStatus'] ?? 'PENDING';

            // Dot color and label based on verification status
            Color dotColor;
            String dotLabel;
            IconData statusIcon;
            switch (verStatus) {
              case 'APPROVED':
                dotColor  = Colors.greenAccent;
                dotLabel  = 'Verified';
                statusIcon = Icons.verified_rounded;
                break;
              case 'DENIED':
                dotColor  = Colors.redAccent;
                dotLabel  = 'Denied';
                statusIcon = Icons.cancel_rounded;
                break;
              default: // PENDING
                dotColor  = Colors.redAccent;
                dotLabel  = 'Pending verification';
                statusIcon = Icons.radio_button_on_rounded;
            }

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dotColor.withOpacity(0.45),
                  width: verStatus == 'PENDING' ? 1.5 : 1.0,
                ),
              ),
              child: Row(children: [
                // Car icon circle
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: verStatus == 'APPROVED'
                        ? Colors.green.withOpacity(0.18)
                        : verStatus == 'DENIED'
                            ? Colors.redAccent.withOpacity(0.15)
                            : Colors.blueAccent.withOpacity(0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_car,
                    color: verStatus == 'APPROVED'
                        ? Colors.greenAccent
                        : verStatus == 'DENIED'
                            ? Colors.redAccent
                            : Colors.blueAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v['plateNumber'] ?? 'UNKNOWN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Owner: ${v['ownerName'] ?? 'Unknown'}',
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Verification status badge (dot + label)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(statusIcon, color: dotColor, size: 18),
                    const SizedBox(height: 3),
                    Text(
                      dotLabel,
                      style: TextStyle(
                        color: dotColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ]),
            );
          },
        );
      },
    );
  }

  // Feature 6 + 7: Approvals list with sound alert + profile cards
  Widget _buildApprovalsList(String flatId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('flatNumber', isEqualTo: flatId)
          .where('status', isEqualTo: 'PENDING')
          .snapshots(), // orderBy removed — sort client-side to avoid index requirement
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 56, color: Theme.of(context).dividerColor),
                const SizedBox(height: 12),
                Text('No pending gate requests.',
                    style:
                        TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6), fontSize: 14)),
                const SizedBox(height: 4),
                Text('Flat: $flatId',
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.4), fontSize: 12)),
              ],
            ),
          );
        }

        // Feature 6: PENDING-filtered, sorted client-side (no Firestore index needed)
        final docs = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final tsA = (a.data() as Map<String, dynamic>)['timestamp'];
            final tsB = (b.data() as Map<String, dynamic>)['timestamp'];
            DateTime? dtA = tsA is Timestamp ? tsA.toDate() : null;
            DateTime? dtB = tsB is Timestamp ? tsB.toDate() : null;
            if (dtA == null && dtB == null) return 0;
            if (dtA == null) return 1;
            if (dtB == null) return -1;
            return dtB.compareTo(dtA);
          });
        final int currentPending = docs.length;

        // 🔔 Beep + banner when new request arrives; stop when resolved
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (currentPending > _lastPendingCount) {
            _lastPendingCount = currentPending;
            // Start 60-second repeating beep alert
            _alertSound.startAlert();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.notifications_active_rounded,
                        color: Colors.white, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '🔔 Someone is at your gate! Respond within 60s.',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.deepOrange,
                duration: const Duration(seconds: 60),
                action: SnackBarAction(
                  label: 'VIEW',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          } else if (currentPending < _lastPendingCount || currentPending == 0) {
            _lastPendingCount = currentPending;
            // All requests resolved — stop beeping
            _alertSound.stopAlert();
          }
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc  = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildApprovalCard(
              docId  : doc.id,
              data   : data,
              flatId : flatId,
            );
          },
        );
      },
    );
  }

  // Feature 7: Enhanced profile card for resident
  Widget _buildApprovalCard({
    required String docId,
    required Map<String, dynamic> data,
    required String flatId,
  }) {
    final String company    = data['company']     ?? 'DELIVERY';
    final String status     = data['status']      ?? 'PENDING';
    // guardId: unified_entry_form writes 'guardId'; fall back to legacy keys
    final String guardId    = data['guardId']     ?? data['sentBy'] ?? data['guardName'] ?? 'GUARD';
    final String plate      = data['plateNumber'] ?? '—';
    final String entryType  = data['entryType']   ?? 'Delivery';
    // photoUrl: unified_entry_form writes the local file path here.
    // When Firebase Storage is wired up, this will be an https:// URL.
    final String photoUrl   = data['photoUrl'] ?? data['agentPhotoPath'] ?? '';
    final bool isNetworkPhoto = photoUrl.startsWith('http');
    final bool isLocalPhoto   = photoUrl.isNotEmpty && !isNetworkPhoto;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'APPROVED':
        statusColor = Colors.greenAccent;
        statusText  = 'APPROVED — Guard will allow entry';
        statusIcon  = Icons.check_circle_rounded;
        break;
      case 'DENIED':
        statusColor = Colors.redAccent;
        statusText  = 'DENIED — Delivery turned away';
        statusIcon  = Icons.cancel_rounded;
        break;
      case 'COMPLETED':
        statusColor = Colors.blueAccent;
        statusText  = 'COMPLETED — Delivery entered';
        statusIcon  = Icons.done_all_rounded;
        break;
      default:
        statusColor = Colors.orangeAccent;
        statusText  = 'Awaiting your decision';
        statusIcon  = Icons.notifications_active_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feature 7: Driver photo + identity header
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: Stack(
              children: [
                // ── Agent Photo Frame ────────────────────────────────────
                // 1. https:// URL → Image.network  (Firebase Storage / CDN)
                // 2. Local path   → Image.file     (same device, guard app)
                // 3. Empty        → placeholder icon
                SizedBox(
                  width: double.infinity,
                  height: 140,
                  child: isNetworkPhoto
                      ? Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, progress) =>
                              progress == null
                                  ? child
                                  : Container(
                                      color: const Color(0xFF0D2137),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                            color: Colors.cyanAccent,
                                            strokeWidth: 2),
                                      ),
                                    ),
                          errorBuilder: (_, __, ___) => _photoPlaceholder(),
                        )
                      : isLocalPhoto
                          ? Image.file(
                              File(photoUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _photoPlaceholder(),
                            )
                          : _photoPlaceholder(),
                ),
                // Gradient overlay for readability
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(context).cardColor.withOpacity(0.95),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 14,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Visitor / Company Name
                      Text(company,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black87)
                              ])),
                      const SizedBox(height: 3),
                      // Vehicle Plate Number
                      Row(children: [
                        const Icon(Icons.directions_car_rounded,
                            size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(plate,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontFamily: 'monospace')),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + company row
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(company,
                        style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  _infoChip(entryType, Colors.blueAccent),
                  const Spacer(),
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 5),
                  Text(status,
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ]),
                const SizedBox(height: 8),
                Text(statusText,
                    style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13)),

                // 60-second expiry countdown bar
                if (status == 'PENDING')
                  _ExpiryCountdown(
                    data    : data,
                    onExpired: () {
                      FirebaseFirestore.instance
                          .collection('approvals')
                          .doc(docId)
                          .update({'status': 'TIMEOUT'}).catchError((_) {});
                      _alertSound.stopAlert();
                    },
                  ),

                // Approve / Deny — only for PENDING
                if (status == 'PENDING') ...[
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        onPressed: () => _handleApproval(
                          docId: docId,
                          company: company,
                          guardId: guardId,
                          approved: true,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('APPROVE',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _handleApproval(
                          docId: docId,
                          company: company,
                          guardId: guardId,
                          approved: false,
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('DENY',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ─── TAB 3: Guard On Duty ─────────────────────────────────────────────────
  Widget _buildGuardOnDutyTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guards')
          .where('onDuty', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.cyanAccent));
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final guards = snapshot.hasData ? snapshot.data!.docs : <DocumentSnapshot>[];
        final onDutyGuards = guards
            .map((d) => d.data() as Map<String, dynamic>)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Status header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF0D2137), Color(0xFF0A3D62)]
                      : [
                          Theme.of(context).colorScheme.primary.withOpacity(0.12),
                          Theme.of(context).colorScheme.primary.withOpacity(0.06),
                        ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: onDutyGuards.isEmpty
                      ? Colors.redAccent.withOpacity(0.4)
                      : Colors.greenAccent.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: onDutyGuards.isEmpty
                          ? Colors.redAccent.withOpacity(0.15)
                          : Colors.greenAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      onDutyGuards.isEmpty
                          ? Icons.no_accounts_rounded
                          : Icons.shield_rounded,
                      color: onDutyGuards.isEmpty
                          ? Colors.redAccent
                          : Colors.greenAccent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          onDutyGuards.isEmpty
                              ? 'No Guard On Duty'
                              : 'Gate is Secured',
                          style: TextStyle(
                            color: onDutyGuards.isEmpty
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          onDutyGuards.isEmpty
                              ? 'No guard is currently logged in to the system.'
                              : '${onDutyGuards.length} guard${onDutyGuards.length > 1 ? "s are" : " is"} actively on duty.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.65),
                              fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (onDutyGuards.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.person_off_rounded,
                        size: 64,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.15),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your gate is currently unmonitored.',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                            fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text(
                'GUARDS CURRENTLY ON DUTY',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              ...onDutyGuards.map((guard) => _buildGuardCard(guard)),
            ],
          ],
        );
      },
    );
  }

  Widget _buildGuardCard(Map<String, dynamic> guard) {
    final String name    = guard['guardName'] ?? guard['guardId'] ?? 'Guard';
    final String id      = guard['guardId']   ?? '—';
    final Timestamp? ts  = guard['dutyStart'] as Timestamp?;
    final DateTime? start = ts?.toDate();
    final String since   = start != null
        ? '${start.hour.toString().padLeft(2, "0")}:${start.minute.toString().padLeft(2, "0")}'
        : 'Unknown time';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.blueAccent.withOpacity(0.2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.blueAccent.shade700,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).cardColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  'ID: $id',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                      fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.greenAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 7, color: Colors.greenAccent),
                          SizedBox(width: 5),
                          Text('ACTIVE',
                              style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Since $since',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4),
                          fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_user_rounded,
              color: Colors.greenAccent, size: 22),
        ],
      ),
    );
  }

  /// Fallback widget shown when the agent photo is absent or fails to load.
  Widget _photoPlaceholder() {
    return Container(
      height: 140,
      width: double.infinity,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0D2137)
          : const Color(0xFFDDE8F0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_rounded,
              size: 52,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.2)),
          const SizedBox(height: 6),
          Text('No photo available',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.3),
                  fontSize: 11)),
        ],
      ),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActivityHistoryTab
//
// Queries Firestore `logs` collection filtered by flatNumber.
// Displays chronological log entries with type badges (ENTRY / EXIT / DELIVERY).
// Fully theme-aware — works in both dark and light mode.
// ─────────────────────────────────────────────────────────────────────────────
class _ActivityHistoryTab extends StatelessWidget {
  final String flatNumber;
  const _ActivityHistoryTab({required this.flatNumber});

  // Colour and icon per log type
  static Color _typeColor(String type) {
    switch (type.toUpperCase()) {
      case 'ENTRY'   : return Colors.greenAccent;
      case 'EXIT'    : return Colors.redAccent;
      case 'DELIVERY': return Colors.orangeAccent;
      default        : return Colors.blueAccent;
    }
  }

  static IconData _typeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'ENTRY'   : return Icons.login_rounded;
      case 'EXIT'    : return Icons.logout_rounded;
      case 'DELIVERY': return Icons.local_shipping_rounded;
      default        : return Icons.swap_vert_rounded;
    }
  }

  static String _formatTimestamp(dynamic ts) {
    if (ts == null) return '—';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return '—';
    }

    // ── Exact date + 12-hour time with AM/PM ──────────────────────────────
    // Format: "23 May 2025  02:47 PM"
    const List<String> months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final String day   = dt.day.toString().padLeft(2, '0');
    final String month = months[dt.month];
    final String year  = dt.year.toString();

    final int    hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final String minute = dt.minute.toString().padLeft(2, '0');
    final String period = dt.hour < 12 ? 'AM' : 'PM';

    return '$day $month $year  ${hour12.toString().padLeft(2, '0')}:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFF4F6F9);
    final cardColor   = isDark ? const Color(0xFF141428) : Colors.white;
    final titleColor  = isDark ? Colors.white            : const Color(0xFF111827);
    final subColor    = isDark ? Colors.white54          : const Color(0xFF6B7280);
    final borderColor = isDark ? const Color(0xFF2E3160) : const Color(0xFFE2E8F0);
    final emptyColor  = isDark ? Colors.white24          : const Color(0xFFCBD5E1);

    if (flatNumber.isEmpty) {
      return Center(
        child: Text('Flat number not available.',
            style: TextStyle(color: emptyColor)),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .where('flatNumber', isEqualTo: flatNumber)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)));
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 40),
                const SizedBox(height: 12),
                Text('Failed to load activity.\nCheck Firestore index.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subColor, fontSize: 13)),
              ],
            ),
          );
        }

        // Apply LogSortService.sort — Dart equivalent of JS sortFirebaseLogs(logs, 'desc')
        // Handles Timestamp, string, int formats. Newest first.
        final rawDocs = snapshot.data?.docs ?? [];
        final docs = LogSortService.sort(rawDocs, direction: SortDirection.desc);

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_toggle_off_rounded,
                    color: emptyColor, size: 56),
                const SizedBox(height: 16),
                Text('No activity yet for Flat $flatNumber',
                    style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Movement, delivery and visitor logs\nwill appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subColor, fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding         : const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount       : docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder     : (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;

            // ── Field resolution ──────────────────────────────────────
            // 'type' is the canonical ENTRY/EXIT field written by
            // _writeMovementLog. Fall back to 'entryType' for older docs
            // or approved-delivery logs that use displayName strings.
            final String type =
                (data['type'] ?? data['entryType'] ?? 'MOVEMENT')
                    .toString()
                    .toUpperCase();

            // Visitor / company name — prefer 'company', fall back to
            // 'visitor_name' written by legacy guard-app versions.
            final String company =
                (data['company'] ?? data['visitor_name'] ?? '—').toString();

            // Vehicle plate — prefer canonical 'plateNumber'.
            final String plate =
                (data['plateNumber'] ?? data['vehicle_number'] ?? '—')
                    .toString()
                    .toUpperCase();

            // Guard who logged the event.
            final String guard = (data['guardId'] ?? '—').toString();

            // Optional free-text notes.
            final String notes = (data['notes'] ?? '').toString().trim();

            // Timestamp — read from Firestore 'timestamp' field and
            // formatted via the built-in _formatTimestamp() method so
            // the output matches the class-level human-readable contract
            // Format: "23 May 2025  02:47 PM" — exact date and 12-hour time.
            final dynamic ts     = data['timestamp'];
            final String  formattedTime = _formatTimestamp(ts);

            // Design tokens.
            final Color    accent = _typeColor(type);
            final IconData icon   = _typeIcon(type);

            return Container(
              decoration: BoxDecoration(
                color       : cardColor,
                borderRadius: BorderRadius.circular(16),
                border      : Border.all(
                    color: accent.withOpacity(0.25), width: 1.0),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Left icon column ─────────────────────────────
                    Container(
                      width : 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color       : accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(13),
                        border      : Border.all(
                            color: accent.withOpacity(0.35), width: 1),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),

                    // ── Content column ───────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // ── Title row: ENTRY/EXIT badge + name ──────
                          Row(
                            children: [
                              // ENTRY / EXIT / DELIVERY badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accent.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: accent.withOpacity(0.4),
                                      width: 0.8),
                                ),
                                child: Text(
                                  type,
                                  style: TextStyle(
                                    color        : accent,
                                    fontSize     : 10,
                                    fontWeight   : FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Visitor / company name
                              Expanded(
                                child: Text(
                                  company,
                                  style: TextStyle(
                                    color     : titleColor,
                                    fontSize  : 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // ── Meta row: plate + timestamp ─────────────
                          Wrap(
                            spacing           : 12,
                            runSpacing        : 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Vehicle plate (only when present)
                              if (plate != '—')
                                Row(mainAxisSize: MainAxisSize.min,
                                    children: [
                                  Icon(Icons.directions_car_rounded,
                                      size: 12, color: subColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    plate,
                                    style: TextStyle(
                                        color     : subColor,
                                        fontSize  : 12,
                                        fontFamily: 'monospace'),
                                  ),
                                ]),
                              // Timestamp — formatted by _formatTimestamp
                              Row(mainAxisSize: MainAxisSize.min,
                                  children: [
                                Icon(Icons.access_time_rounded,
                                    size: 12, color: subColor),
                                const SizedBox(width: 3),
                                Text(
                                  formattedTime,
                                  style: TextStyle(
                                      color: subColor, fontSize: 11),
                                ),
                              ]),
                            ],
                          ),

                          // ── Guard row ───────────────────────────────
                          if (guard != '—') ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.shield_outlined,
                                  size: 12, color: subColor),
                              const SizedBox(width: 3),
                              Text(
                                'Guard: $guard',
                                style: TextStyle(
                                    color: subColor, fontSize: 11),
                              ),
                            ]),
                          ],

                          // ── Notes row (only when non-empty) ─────────
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.notes_rounded,
                                    size: 12, color: subColor),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    notes,
                                    style: TextStyle(
                                        color    : subColor,
                                        fontSize : 11,
                                        fontStyle: FontStyle.italic),
                                    maxLines : 2,
                                    overflow : TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ExpiryCountdown
//
// Shows a red countdown bar + "XX seconds remaining" text on each PENDING
// approval card. When it reaches zero it calls onExpired() which marks
// the Firestore document as TIMEOUT and stops the beep alert.
// ─────────────────────────────────────────────────────────────────────────────
class _ExpiryCountdown extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback          onExpired;

  const _ExpiryCountdown({required this.data, required this.onExpired});

  @override
  State<_ExpiryCountdown> createState() => _ExpiryCountdownState();
}

class _ExpiryCountdownState extends State<_ExpiryCountdown> {
  static const int _totalSeconds = 60;
  int    _secondsLeft = _totalSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _calculateSecondsLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, _totalSeconds);
      });
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        widget.onExpired();
      }
    });
  }

  void _calculateSecondsLeft() {
    final dynamic exp = widget.data['expiresAt'];
    if (exp is Timestamp) {
      final secs = exp.toDate().difference(DateTime.now()).inSeconds;
      _secondsLeft = secs.clamp(0, _totalSeconds);
    } else {
      // No expiresAt field — start fresh 60s countdown
      _secondsLeft = _totalSeconds;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double fraction = _secondsLeft / _totalSeconds;
    final Color barColor = fraction > 0.5
        ? Colors.greenAccent
        : fraction > 0.25
            ? Colors.orangeAccent
            : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value          : fraction,
              backgroundColor: barColor.withOpacity(0.15),
              color          : barColor,
              minHeight      : 6,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.timer_rounded, size: 12, color: barColor),
              const SizedBox(width: 4),
              Text(
                _secondsLeft > 0
                    ? '$_secondsLeft seconds to respond'
                    : 'Request expired',
                style: TextStyle(
                  color    : barColor,
                  fontSize : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
