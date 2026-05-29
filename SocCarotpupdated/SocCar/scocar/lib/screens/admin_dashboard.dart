import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show themeNotifier, AppTokens;

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard
//
// Three tabs:
//   0 — Guards        : view / add / edit / delete guard records
//   1 — Residents     : view / add / edit / delete resident records
//   2 — Entry Logs    : read-only list of all movement/delivery logs
//
// Firestore collections used:
//   • guards      — fields: guardId, guardName, accessCode, onDuty, dutyStart
//   • residents   — doc ID = flat number; fields: ownerName, accessCode
//   • logs        — read-only view (all activity)
// ─────────────────────────────────────────────────────────────────────────────

// Admin accent colour (amber-gold — matches login screen)
const Color _kAdminAccent  = Color(0xFFFFB300);
const Color _kAdminAccentDk= Color(0xFFFFCA28);

// ─────────────────────────────────────────────────────────────────────────────
// AdminDashboard — checks Firestore planStatus before showing the dashboard.
//
// planStatus flow:
//   (not set)              → trial not yet started  → shows PlansScreen
//   'trial'                → within 7 days          → full access
//   'active'               → paid & verified        → full access
//   'pending_verification' → UTR submitted, not yet verified → waiting banner
//   'expired' / anything else → trial over          → sends to PlansScreen
//
// The args map passed via Navigator must contain:
//   { 'societyId': '...', 'societyName': '...' }
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool   _checking = true;
  String _planStatus = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPlanStatus();
  }

  Future<void> _checkPlanStatus() async {
    final args      = ModalRoute.of(context)?.settings.arguments as Map?;
    final societyId = args?['societyId'] as String? ?? '';


    final adminId = args?['adminId'] as String? ?? '';
    final accessCode = args?['accessCode'] as String? ?? '';

    if (societyId.isEmpty) {
      if (mounted) Navigator.pushReplacementNamed(context, '/plans', arguments: args);
      return;
    }

    // Require admin credentials to enter dashboard
    if (adminId.isEmpty || accessCode.isEmpty) {
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/admin_login',
          arguments: {'societyId': societyId, 'societyName': args?['societyName']},
        );
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('societies')
          .doc(societyId)
          .get();

      if (!doc.exists) {
        // Brand-new society — start free trial
        final trialEnd = DateTime.now().add(const Duration(days: 7));
        await FirebaseFirestore.instance
            .collection('societies')
            .doc(societyId)
            .set({
          'planStatus'  : 'trial',
          'trialStartAt': FieldValue.serverTimestamp(),
          'trialEndsAt' : Timestamp.fromDate(trialEnd),
          'societyName' : args?['societyName'] ?? societyId,
        }, SetOptions(merge: true));
        if (mounted) setState(() { _planStatus = 'trial'; _checking = false; });
        return;
      }

      final data   = doc.data() as Map<String, dynamic>;
      final status = data['planStatus'] as String? ?? '';

      final storedAdminId    = (data['adminId']    as String? ?? '').trim();
      final storedAccessCode = (data['accessCode'] as String? ?? '').trim();

      if (storedAdminId != adminId.trim() ||
          storedAccessCode != accessCode.trim()) {
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/admin_login',
            arguments: {
              'societyId'  : societyId,
              'societyName': args?['societyName'],
            },
          );
        }
        return;
      }

      // Check trial expiry
      if (status == 'trial') {
        final trialEndsAt = data['trialEndsAt'] as Timestamp?;
        if (trialEndsAt != null &&
            trialEndsAt.toDate().isBefore(DateTime.now())) {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/plans', arguments: args);
          }
          return;
        }
      }

      // 'active' or 'trial' (not expired) → allow in
      // 'pending_verification'            → show waiting banner
      // anything else                     → send to plans
      if (status == 'active' || status == 'trial') {
        if (mounted) setState(() { _planStatus = status; _checking = false; });
      } else if (status == 'pending_verification') {
        if (mounted) setState(() {
          _planStatus = 'pending_verification';
          _checking   = false;
        });
      } else {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/plans', arguments: args);
        }
      }
    } catch (e) {
      // On Firestore error allow access — don't lock out legitimate admins
      if (mounted) setState(() { _planStatus = 'active'; _checking = false; });
    }
  } // end _checkPlanStatus

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final args        = ModalRoute.of(context)?.settings.arguments as Map?;
    final societyName = args?['societyName'] as String? ?? 'Admin Panel';
    final societyId   = args?['societyId']   as String? ?? '';

    // ── Loading while checking Firestore ─────────────────────────────────
    if (_checking) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF080B18) : const Color(0xFFF4F6F9),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: _kAdminAccent),
              const SizedBox(height: 18),
              Text('Verifying subscription…',
                  style: TextStyle(
                      color  : isDark ? Colors.white54 : Colors.grey.shade600,
                      fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // ── Payment pending — UTR submitted, waiting for manual verification ──
    if (_planStatus == 'pending_verification') {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF080B18) : const Color(0xFFF4F6F9),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width : 90, height: 90,
                  decoration: BoxDecoration(
                    color : const Color(0xFFFFB300).withOpacity(0.12),
                    shape : BoxShape.circle,
                    border: Border.all(color: _kAdminAccent.withOpacity(0.4), width: 2),
                  ),
                  child: const Icon(Icons.access_time_rounded,
                      color: _kAdminAccent, size: 44),
                ),
                const SizedBox(height: 28),
                Text('Payment Under Verification',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color     : isDark ? Colors.white : const Color(0xFF111827),
                        fontSize  : 22,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                Text(
                  'Your UTR has been received. We\'re verifying your payment — '
                      'this usually takes 2–10 minutes during business hours.\n\n'
                      'Once verified, your Annual Plan activates automatically. '
                      'Please check back shortly.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color  : isDark ? Colors.white54 : Colors.grey.shade600,
                      fontSize: 13,
                      height : 1.65),
                ),
                const SizedBox(height: 32),
                // Retry button — re-checks Firestore
                SizedBox(
                  width : double.infinity,
                  height: 52,
                  child : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kAdminAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      setState(() => _checking = true);
                      _checkPlanStatus();
                    },
                    icon : const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('Check Again',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                  child: Text('Logout',
                      style: TextStyle(
                          color  : isDark ? Colors.white38 : Colors.grey.shade500,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Trial banner (shown at top of dashboard during trial) ─────────────
    Widget? trialBanner;
    if (_planStatus == 'trial') {
      trialBanner = _TrialBanner(
        societyId  : societyId,
        societyName: societyName,
        isDark     : isDark,
      );
    }

    // ── Full dashboard ────────────────────────────────────────────────────
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: isDark
              ? const Color(0xFF0A0A1A)
              : const Color(0xFF1A237E),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding    : const EdgeInsets.all(6),
                decoration : BoxDecoration(
                  color       : _kAdminAccent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded,
                    color: _kAdminAccent, size: 18),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ADMIN PANEL',
                        style: TextStyle(
                            color        : Colors.white,
                            fontWeight   : FontWeight.w900,
                            letterSpacing: 1.0,
                            fontSize     : 13)),
                    if (societyName != 'Admin Panel')
                      Text(
                        societyName,
                        style: TextStyle(
                            color     : _kAdminAccent.withOpacity(0.8),
                            fontSize  : 10,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          centerTitle: true,
          elevation  : 0,
          actions    : [
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, __) => IconButton(
                icon: Icon(
                  mode == ThemeMode.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  color: Colors.white60,
                ),
                onPressed: () {
                  themeNotifier.value = mode == ThemeMode.dark
                      ? ThemeMode.light
                      : ThemeMode.dark;
                },
              ),
            ),
            IconButton(
              icon     : const Icon(Icons.logout_rounded, color: Colors.white70),
              tooltip  : 'Logout',
              onPressed: () => Navigator.pushReplacementNamed(context, '/'),
            ),
          ],
          bottom: const TabBar(
            indicatorColor      : _kAdminAccent,
            labelColor          : _kAdminAccent,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: Icon(Icons.shield_rounded,  size: 20), text: 'Guards'),
              Tab(icon: Icon(Icons.home_rounded,    size: 20), text: 'Residents'),
              Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'Entry Logs'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (trialBanner != null) trialBanner,
            const Expanded(
              child: TabBarView(
                children: [
                  _GuardsTab(),
                  _ResidentsTab(),
                  _LogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
} // end _AdminDashboardState

// ─────────────────────────────────────────────────────────────────────────────
// _TrialBanner — shown at top of dashboard during 7-day trial
// ─────────────────────────────────────────────────────────────────────────────
class _TrialBanner extends StatelessWidget {
  final String societyId;
  final String societyName;
  final bool   isDark;
  const _TrialBanner({
    required this.societyId,
    required this.societyName,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('societies')
          .doc(societyId)
          .snapshots(),
      builder: (context, snap) {
        int daysLeft = 7;
        if (snap.hasData && snap.data!.exists) {
          final data     = snap.data!.data() as Map<String, dynamic>;
          final endsAt   = data['trialEndsAt'] as Timestamp?;
          if (endsAt != null) {
            daysLeft = endsAt.toDate().difference(DateTime.now()).inDays.clamp(0, 7);
          }
        }

        return GestureDetector(
          onTap: () => Navigator.pushNamed(
            context,
            '/plans',
            arguments: {'societyId': societyId, 'societyName': societyName},
          ),
          child: Container(
            width  : double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color  : daysLeft <= 2
                ? Colors.redAccent.withOpacity(0.9)
                : const Color(0xFFFFB300).withOpacity(0.9),
            child: Row(
              children: [
                Icon(
                  daysLeft <= 2
                      ? Icons.warning_amber_rounded
                      : Icons.access_time_rounded,
                  color: Colors.black,
                  size : 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    daysLeft > 0
                        ? 'Free trial — $daysLeft day${daysLeft == 1 ? "" : "s"} remaining. Tap to upgrade.'
                        : 'Trial expired — tap to activate your Annual Plan.',
                    style: const TextStyle(
                        color     : Colors.black,
                        fontSize  : 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.black54, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 0 — GUARDS
// ─────────────────────────────────────────────────────────────────────────────
class _GuardsTab extends StatelessWidget {
  const _GuardsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guards')
          .orderBy('guardName')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }
        final docs = snap.data?.docs ?? [];

        return Column(children: [
          // ── Summary bar ───────────────────────────────────────────────
          _SummaryBar(
            items: [
              _SummaryItem('TOTAL',   '${docs.length}',                     _kAdminAccent),
              _SummaryItem('ON DUTY', '${docs.where((d) => (d.data() as Map)['onDuty'] == true).length}', Colors.greenAccent),
              _SummaryItem('OFF',     '${docs.where((d) => (d.data() as Map)['onDuty'] != true).length}', Colors.grey),
            ],
          ),

          // ── Add button ────────────────────────────────────────────────
          _AddButton(
            label  : 'ADD NEW GUARD',
            onTap  : () => _GuardFormSheet.show(context),
          ),

          // ── List ──────────────────────────────────────────────────────
          Expanded(
            child: docs.isEmpty
                ? const _EmptyState(
                icon   : Icons.shield_outlined,
                message: 'No guards registered yet.',
                sub    : 'Tap ADD NEW GUARD to create the first one.')
                : ListView.builder(
              padding    : const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount  : docs.length,
              itemBuilder: (ctx, i) {
                final doc  = docs[i];
                final data = doc.data() as Map<String, dynamic>;
                return _GuardCard(docId: doc.id, data: data);
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ── Guard card ──────────────────────────────────────────────────────────────
class _GuardCard extends StatelessWidget {
  final String             docId;
  final Map<String, dynamic> data;
  const _GuardCard({required this.docId, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bool duty = data['onDuty'] == true;
    final String name = data['guardName']  as String? ?? '—';
    final String id   = data['guardId']    as String? ?? '—';
    final String code = data['accessCode'] as String? ?? '—';

    return _AdminCard(
      accentColor: duty ? Colors.greenAccent : Colors.white30,
      child: Row(children: [

        // Avatar
        Stack(children: [
          CircleAvatar(
            radius         : 26,
            backgroundColor: _kAdminAccent.withOpacity(0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'G',
              style: const TextStyle(
                  color: _kAdminAccent, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (duty)
            Positioned(
              bottom: 0, right: 0,
              child : Container(
                width : 10, height: 10,
                decoration: BoxDecoration(
                  color : Colors.greenAccent,
                  shape : BoxShape.circle,
                  border: Border.all(
                      color: isDark ? const Color(0xFF141428) : Colors.white,
                      width: 1.5),
                ),
              ),
            ),
        ]),

        const SizedBox(width: 14),

        // Info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      color     : isDark ? Colors.white : const Color(0xFF1A1F36),
                      fontWeight: FontWeight.bold,
                      fontSize  : 15),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              _InfoRow(icon: Icons.badge_rounded,
                  label: 'ID',    value: id,   color: _kAdminAccent),
              _InfoRow(icon: Icons.lock_rounded,
                  label: 'CODE',  value: code, color: Colors.white54,
                  isCode: true),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color       : duty
                      ? Colors.greenAccent.withOpacity(0.12)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  duty ? '● ON DUTY' : '○ OFF DUTY',
                  style: TextStyle(
                      color     : duty
                          ? Colors.greenAccent
                          : Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                      fontSize  : 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
        ),

        // Action buttons
        Column(children: [
          _ActionIconBtn(
            icon    : Icons.edit_rounded,
            color   : _kAdminAccent,
            tooltip : 'Edit',
            onTap   : () => _GuardFormSheet.show(context,
                docId: docId, existing: data),
          ),
          const SizedBox(height: 6),
          _ActionIconBtn(
            icon    : Icons.delete_rounded,
            color   : Colors.redAccent,
            tooltip : 'Delete',
            onTap   : () => _confirmDelete(
              context,
              message: 'Delete guard "$name"? This cannot be undone.',
              onConfirm: () => FirebaseFirestore.instance
                  .collection('guards')
                  .doc(docId)
                  .delete(),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Guard add/edit form sheet ────────────────────────────────────────────────
class _GuardFormSheet extends StatefulWidget {
  final String?             docId;
  final Map<String, dynamic>? existing;
  const _GuardFormSheet({this.docId, this.existing});

  static Future<void> show(
      BuildContext context, {
        String?             docId,
        Map<String, dynamic>? existing,
      }) {
    return showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      useSafeArea       : true,
      backgroundColor   : Colors.transparent,
      builder           : (_) =>
          _GuardFormSheet(docId: docId, existing: existing),
    );
  }

  @override
  State<_GuardFormSheet> createState() => _GuardFormSheetState();
}

class _GuardFormSheetState extends State<_GuardFormSheet> {
  final _nameCtrl = TextEditingController();
  final _idCtrl   = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool  _saving   = false;
  bool  _obscure  = true;

  bool get _isEdit => widget.docId != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!['guardName'] as String? ?? '';
      _idCtrl.text   = widget.existing!['guardId']   as String? ?? '';
      _codeCtrl.text = widget.existing!['accessCode']as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final id   = _idCtrl.text.trim().toUpperCase();
    final code = _codeCtrl.text.trim();

    if (name.isEmpty || id.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All fields are required.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {
        'guardName' : name,
        'guardId'   : id,
        'accessCode': code,
        'onDuty'    : widget.existing?['onDuty'] ?? false,
      };

      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection('guards')
            .doc(widget.docId)
            .update(payload);
      } else {
        await FirebaseFirestore.instance
            .collection('guards')
            .add(payload);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content        : Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _FormSheetShell(
      title  : _isEdit ? 'Edit Guard' : 'Add New Guard',
      icon   : Icons.shield_rounded,
      accent : _kAdminAccent,
      isDark : isDark,
      saving : _saving,
      onSave : _save,
      fields : [
        _SheetField(ctrl: _nameCtrl, label: 'Full Name',
            hint: 'e.g. Rajesh Kumar', icon: Icons.person_rounded, isDark: isDark),
        const SizedBox(height: 14),
        _SheetField(ctrl: _idCtrl, label: 'Guard ID',
            hint: 'e.g. GUARD1', icon: Icons.badge_rounded, isDark: isDark,
            capitalize: TextCapitalization.characters),
        const SizedBox(height: 14),
        _SheetField(ctrl: _codeCtrl, label: 'Access Code',
            hint: 'Set a secure code', icon: Icons.lock_rounded, isDark: isDark,
            obscure: _obscure,
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : AppTokens.lightTextHint),
              onPressed: () => setState(() => _obscure = !_obscure),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — RESIDENTS
// ─────────────────────────────────────────────────────────────────────────────
class _ResidentsTab extends StatelessWidget {
  const _ResidentsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('residents')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }
        final docs = snap.data?.docs ?? [];

        return Column(children: [
          _SummaryBar(items: [
            _SummaryItem('TOTAL FLATS', '${docs.length}', _kAdminAccent),
          ]),
          _AddButton(
            label : 'ADD NEW RESIDENT',
            onTap : () => _ResidentFormSheet.show(context),
          ),
          Expanded(
            child: docs.isEmpty
                ? const _EmptyState(
                icon   : Icons.home_outlined,
                message: 'No residents registered.',
                sub    : 'Tap ADD NEW RESIDENT to add the first flat.')
                : ListView.builder(
              padding    : const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount  : docs.length,
              itemBuilder: (ctx, i) {
                final doc  = docs[i];
                final data = doc.data() as Map<String, dynamic>;
                return _ResidentCard(docId: doc.id, data: data);
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ── Resident card ────────────────────────────────────────────────────────────
class _ResidentCard extends StatelessWidget {
  final String             docId;
  final Map<String, dynamic> data;
  const _ResidentCard({required this.docId, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final String owner = data['ownerName']  as String? ?? '—';
    final String code  = data['accessCode'] as String? ?? '—';

    return _AdminCard(
      accentColor: Colors.blueAccent,
      child: Row(children: [

        // Avatar
        CircleAvatar(
          radius         : 26,
          backgroundColor: Colors.blueAccent.withOpacity(0.15),
          child: Text(
            docId.length >= 2 ? docId.substring(0, 2).toUpperCase() : docId,
            style: const TextStyle(
                color: Colors.blueAccent, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(owner,
                  style: TextStyle(
                      color     : isDark ? Colors.white : const Color(0xFF1A1F36),
                      fontWeight: FontWeight.bold,
                      fontSize  : 15),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              _InfoRow(icon: Icons.apartment_rounded,
                  label: 'FLAT', value: docId, color: Colors.blueAccent),
              _InfoRow(icon: Icons.lock_rounded,
                  label: 'CODE', value: code,  color: Colors.white54,
                  isCode: true),
            ],
          ),
        ),

        // Actions
        Column(children: [
          _ActionIconBtn(
            icon   : Icons.edit_rounded,
            color  : _kAdminAccent,
            tooltip: 'Edit',
            onTap  : () => _ResidentFormSheet.show(context,
                flatId: docId, existing: data),
          ),
          const SizedBox(height: 6),
          _ActionIconBtn(
            icon   : Icons.delete_rounded,
            color  : Colors.redAccent,
            tooltip: 'Delete',
            onTap  : () => _confirmDelete(
              context,
              message: 'Delete Flat "$docId"? This cannot be undone.',
              onConfirm: () => FirebaseFirestore.instance
                  .collection('residents')
                  .doc(docId)
                  .delete(),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ── Resident form sheet ───────────────────────────────────────────────────────
class _ResidentFormSheet extends StatefulWidget {
  final String?             flatId;
  final Map<String, dynamic>? existing;
  const _ResidentFormSheet({this.flatId, this.existing});

  static Future<void> show(
      BuildContext context, {
        String?             flatId,
        Map<String, dynamic>? existing,
      }) {
    return showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      useSafeArea       : true,
      backgroundColor   : Colors.transparent,
      builder           : (_) =>
          _ResidentFormSheet(flatId: flatId, existing: existing),
    );
  }

  @override
  State<_ResidentFormSheet> createState() => _ResidentFormSheetState();
}

class _ResidentFormSheetState extends State<_ResidentFormSheet> {
  final _flatCtrl  = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  bool  _saving    = false;
  bool  _obscure   = true;

  bool get _isEdit => widget.flatId != null;

  @override
  void initState() {
    super.initState();
    if (widget.flatId != null) _flatCtrl.text = widget.flatId!;
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!['ownerName']  as String? ?? '';
      _codeCtrl.text = widget.existing!['accessCode'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _flatCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final flat = _flatCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim();

    if (flat.isEmpty || name.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content        : Text('All fields are required.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final payload = {'ownerName': name, 'accessCode': code};

      if (_isEdit) {
        // Flat number (doc ID) never changes on edit
        await FirebaseFirestore.instance
            .collection('residents')
            .doc(widget.flatId)
            .update(payload);
      } else {
        // Doc ID = flat number
        await FirebaseFirestore.instance
            .collection('residents')
            .doc(flat)
            .set(payload);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content        : Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _FormSheetShell(
      title : _isEdit ? 'Edit Resident' : 'Add New Resident',
      icon  : Icons.home_rounded,
      accent: Colors.blueAccent,
      isDark: isDark,
      saving: _saving,
      onSave: _save,
      fields: [
        _SheetField(ctrl: _flatCtrl, label: 'Flat Number',
            hint: 'e.g. A101', icon: Icons.apartment_rounded, isDark: isDark,
            capitalize: TextCapitalization.characters,
            enabled: !_isEdit),  // cannot change doc ID
        const SizedBox(height: 14),
        _SheetField(ctrl: _nameCtrl, label: 'Owner Name',
            hint: 'e.g. Priya Sharma', icon: Icons.person_rounded, isDark: isDark),
        const SizedBox(height: 14),
        _SheetField(ctrl: _codeCtrl, label: 'Access Code',
            hint: 'Set a secure code', icon: Icons.lock_rounded, isDark: isDark,
            obscure: _obscure,
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : AppTokens.lightTextHint),
              onPressed: () => setState(() => _obscure = !_obscure),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — ENTRY LOGS (read-only)
// ─────────────────────────────────────────────────────────────────────────────
class _LogsTab extends StatefulWidget {
  const _LogsTab();

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  // Filter state
  String _filterType = 'ALL'; // ALL | ENTRY | EXIT
  final _searchCtrl  = TextEditingController();
  String _searchText = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('logs')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingView();
        }

        var docs = snap.data?.docs ?? [];

        // Apply type filter
        if (_filterType != 'ALL') {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['type'] as String? ?? '')
                .toUpperCase() == _filterType;
          }).toList();
        }

        // Apply search
        if (_searchText.isNotEmpty) {
          final q = _searchText.toLowerCase();
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final flat = (data['flatNumber'] as String? ?? '').toLowerCase();
            final who  = (data['company']   as String? ?? '').toLowerCase();
            final plate= (data['plateNumber']as String? ?? '').toLowerCase();
            return flat.contains(q) || who.contains(q) || plate.contains(q);
          }).toList();
        }

        return Column(children: [

          // ── Search + filter bar ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(children: [
              // Search
              TextField(
                controller: _searchCtrl,
                onChanged : (v) => setState(() => _searchText = v),
                style: TextStyle(
                    color   : isDark ? Colors.white : const Color(0xFF1A1F36),
                    fontSize: 14),
                decoration: InputDecoration(
                  hintText : 'Search by flat, name, plate…',
                  hintStyle: TextStyle(
                      color  : isDark ? Colors.white38 : Colors.grey.shade400,
                      fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      size: 20),
                  suffixIcon: _searchText.isNotEmpty
                      ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          color: isDark ? Colors.white38 : Colors.grey,
                          size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchText = '');
                      })
                      : null,
                  filled    : true,
                  fillColor : isDark ? const Color(0xFF1A1D35) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: isDark ? const Color(0xFF2A2A4A) : Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: isDark ? const Color(0xFF2A2A4A) : Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _kAdminAccent, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                ),
              ),
              const SizedBox(height: 10),

              // Type filter chips
              Row(children: [
                for (final f in ['ALL', 'ENTRY', 'EXIT'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterType = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: _filterType == f
                              ? _kAdminAccent
                              : isDark
                              ? const Color(0xFF1A1D35)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _filterType == f
                                  ? _kAdminAccent
                                  : isDark
                                  ? const Color(0xFF2A2A4A)
                                  : Colors.grey.shade300),
                        ),
                        child: Text(f,
                            style: TextStyle(
                                color     : _filterType == f
                                    ? Colors.black
                                    : isDark ? Colors.white54 : Colors.grey.shade600,
                                fontWeight: FontWeight.bold,
                                fontSize  : 11,
                                letterSpacing: 0.5)),
                      ),
                    ),
                  ),
                const Spacer(),
                Text('${docs.length} record${docs.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        color  : isDark ? Colors.white38 : Colors.grey.shade500,
                        fontSize: 12)),
              ]),
            ]),
          ),

          const SizedBox(height: 8),

          // ── Log list ──────────────────────────────────────────────────
          Expanded(
            child: docs.isEmpty
                ? const _EmptyState(
                icon   : Icons.history_toggle_off_rounded,
                message: 'No logs found.',
                sub    : 'Try changing the filter or search term.')
                : ListView.builder(
              padding    : const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount  : docs.length,
              itemBuilder: (ctx, i) {
                final doc  = docs[i];
                final data = doc.data() as Map<String, dynamic>;
                return _LogCard(data: data);
              },
            ),
          ),
        ]);
      },
    );
  }
}

// ── Log card (read-only) ─────────────────────────────────────────────────────
class _LogCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LogCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final String type      = (data['type']       as String? ?? 'ENTRY').toUpperCase();
    final String entryType = data['entryType']   as String? ?? 'Movement';
    final String company   = data['company']     as String? ?? '—';
    final String flat      = data['flatNumber']  as String? ?? '—';
    final String plate     = data['plateNumber'] as String? ?? '';
    final String guard     = data['guardId']     as String? ?? '—';
    final ts               = data['timestamp']   as Timestamp?;

    final bool isEntry = type == 'ENTRY';
    final Color dirColor = isEntry ? Colors.greenAccent : Colors.orangeAccent;

    final String timeStr = ts != null
        ? () {
      final dt = ts.toDate().toLocal();
      return '${dt.day}/${dt.month}  '
          '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
    }()
        : '—';

    return _AdminCard(
      accentColor: dirColor,
      compact    : true,
      child: Row(children: [

        // Direction indicator
        Container(
          width : 36, height: 36,
          decoration: BoxDecoration(
            color       : dirColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isEntry ? Icons.login_rounded : Icons.logout_rounded,
            color: dirColor, size: 18,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(company,
                      style: TextStyle(
                          color     : isDark ? Colors.white : const Color(0xFF1A1F36),
                          fontWeight: FontWeight.bold,
                          fontSize  : 13),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text(timeStr,
                    style: TextStyle(
                        color  : isDark ? Colors.white38 : Colors.grey.shade500,
                        fontSize: 10)),
              ]),
              const SizedBox(height: 3),
              Wrap(spacing: 8, children: [
                _MiniChip('Flat $flat', Colors.blueAccent),
                if (plate.isNotEmpty) _MiniChip(plate, AppTokens.cyanAction),
                _MiniChip(entryType,   Colors.purpleAccent),
                _MiniChip('G: $guard', Colors.white38),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

// ── Generic admin card container ─────────────────────────────────────────────
class _AdminCard extends StatelessWidget {
  final Color  accentColor;
  final Widget child;
  final bool   compact;
  const _AdminCard({
    required this.accentColor,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin  : EdgeInsets.only(bottom: compact ? 10 : 14),
      padding : EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color       : isDark ? const Color(0xFF141428) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color     : isDark ? Colors.black26 : Colors.blueGrey.shade50,
            blurRadius: 8,
            offset    : const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────
class _SummaryItem {
  final String label;
  final String value;
  final Color  color;
  const _SummaryItem(this.label, this.value, this.color);
}

class _SummaryBar extends StatelessWidget {
  final List<_SummaryItem> items;
  const _SummaryBar({required this.items});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin : const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color       : isDark ? const Color(0xFF141428) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? const Color(0xFF2A2A4A) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.expand((item) sync* {
          yield _SummaryCell(item);
          if (item != items.last) {
            yield Container(
              width: 1, height: 32,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            );
          }
        }).toList(),
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final _SummaryItem item;
  const _SummaryCell(this.item);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.value,
            style: TextStyle(
                color     : item.color,
                fontSize  : 22,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(item.label,
            style: TextStyle(
                color      : Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                fontSize   : 9,
                fontWeight : FontWeight.bold,
                letterSpacing: 0.6)),
      ],
    );
  }
}

// ── ADD button ────────────────────────────────────────────────────────────────
class _AddButton extends StatelessWidget {
  final String     label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: SizedBox(
        width : double.infinity,
        height: 46,
        child : ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAdminAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          icon : const Icon(Icons.add_rounded, size: 20, color: Colors.black),
          label: Text(label,
              style: const TextStyle(
                  fontWeight   : FontWeight.w900,
                  fontSize     : 13,
                  letterSpacing: 0.8,
                  color        : Colors.black)),
        ),
      ),
    );
  }
}

// ── Icon action button ────────────────────────────────────────────────────────
class _ActionIconBtn extends StatelessWidget {
  final IconData     icon;
  final Color        color;
  final String       tooltip;
  final VoidCallback onTap;
  const _ActionIconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width : 34, height: 34,
          decoration: BoxDecoration(
            color       : color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

// ── Info row (label + value) ──────────────────────────────────────────────────
class _InfoRow extends StatefulWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final bool     isCode;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.isCode = false,
  });

  @override
  State<_InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<_InfoRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final String display = widget.isCode && !_revealed
        ? '•' * widget.value.length.clamp(4, 10)
        : widget.value;

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(children: [
        Icon(widget.icon, size: 12, color: widget.color.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text('${widget.label}: ',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                fontSize: 11)),
        Expanded(
          child: Text(display,
              style: TextStyle(
                  color     : widget.color,
                  fontSize  : 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: widget.isCode && !_revealed ? 'monospace' : null),
              overflow: TextOverflow.ellipsis),
        ),
        if (widget.isCode)
          GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: Icon(
              _revealed
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              size : 13,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        if (!widget.isCode)
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.value));
            },
            child: Icon(Icons.copy_rounded, size: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25)),
          ),
      ]),
    );
  }
}

// ── Mini chip ─────────────────────────────────────────────────────────────────
class _MiniChip extends StatelessWidget {
  final String text;
  final Color  color;
  const _MiniChip(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text,
          style: TextStyle(
              color    : color,
              fontSize : 9,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  final String   sub;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: cs.onSurface.withOpacity(0.12)),
            const SizedBox(height: 16),
            Text(message,
                style: TextStyle(
                    color: cs.onSurface.withOpacity(0.55),
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(sub,
                style: TextStyle(
                    color: cs.onSurface.withOpacity(0.35), fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Loading spinner ────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
    child: CircularProgressIndicator(color: _kAdminAccent, strokeWidth: 2.5),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _FormSheetShell — reusable bottom sheet wrapper for Add/Edit forms
// ─────────────────────────────────────────────────────────────────────────────
class _FormSheetShell extends StatelessWidget {
  final String       title;
  final IconData     icon;
  final Color        accent;
  final bool         isDark;
  final bool         saving;
  final VoidCallback onSave;
  final List<Widget> fields;

  const _FormSheetShell({
    required this.title,
    required this.icon,
    required this.accent,
    required this.isDark,
    required this.saving,
    required this.onSave,
    required this.fields,
  });

  @override
  Widget build(BuildContext context) {
    final Color sheetBg = isDark ? const Color(0xFF0A0A1A) : Colors.white;
    final Color handle  = isDark ? const Color(0xFF2A2A4A) : Colors.grey.shade300;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color       : sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: accent.withOpacity(0.3)),
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
            mainAxisSize     : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Handle bar
              Center(
                child: Container(
                  width : 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: handle, borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Header
              Row(children: [
                Container(
                  padding    : const EdgeInsets.all(9),
                  decoration : BoxDecoration(
                    color       : accent.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Text(title,
                    style: TextStyle(
                        color        : isDark ? Colors.white : const Color(0xFF1A1F36),
                        fontSize     : 17,
                        fontWeight   : FontWeight.w900,
                        letterSpacing: 0.5)),
              ]),

              const SizedBox(height: 24),

              // Fields
              ...fields,

              const SizedBox(height: 28),

              // Save button
              SizedBox(
                width : double.infinity,
                height: 52,
                child : ElevatedButton(
                  onPressed: saving ? null : onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor        : accent,
                    foregroundColor        : Colors.black,
                    disabledBackgroundColor: accent.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(
                      width : 22, height: 22,
                      child : CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2.5))
                      : const Text('SAVE',
                      style: TextStyle(
                          fontWeight   : FontWeight.w900,
                          fontSize     : 15,
                          letterSpacing: 1.2,
                          color        : Colors.black)),
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
// _SheetField — reusable form field inside bottom sheets
// ─────────────────────────────────────────────────────────────────────────────
class _SheetField extends StatelessWidget {
  final TextEditingController ctrl;
  final String                label;
  final String                hint;
  final IconData              icon;
  final bool                  isDark;
  final bool                  obscure;
  final bool                  enabled;
  final TextCapitalization    capitalize;
  final Widget?               suffixIcon;

  const _SheetField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.obscure   = false,
    this.enabled   = true,
    this.capitalize= TextCapitalization.words,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final Color text   = isDark ? Colors.white          : const Color(0xFF1A1F36);
    final Color label_ = isDark ? Colors.white54        : Colors.grey.shade600;
    final Color hint_  = isDark ? Colors.white24        : Colors.grey.shade400;
    final Color fill   = isDark ? const Color(0xFF1A1D35) : const Color(0xFFF8FAFF);
    final Color border = isDark ? const Color(0xFF2A2A4A) : const Color(0xFFCBD5E1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                color      : isDark ? const Color(0xFF7A7AAA) : Colors.grey.shade500,
                fontSize   : 10,
                fontWeight : FontWeight.bold,
                letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller        : ctrl,
          enabled           : enabled,
          obscureText       : obscure,
          textCapitalization: capitalize,
          style             : TextStyle(color: text, fontSize: 15),
          decoration: InputDecoration(
            hintText  : hint,
            hintStyle : TextStyle(color: hint_, fontSize: 14),
            prefixIcon: Icon(icon, color: _kAdminAccent, size: 20),
            suffixIcon: suffixIcon,
            filled    : true,
            fillColor : enabled ? fill : fill.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : BorderSide(color: border, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : BorderSide(color: border.withOpacity(0.4)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide  : const BorderSide(color: _kAdminAccent, width: 2),
            ),
            labelStyle    : TextStyle(color: label_),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 15),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm delete dialog helper
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _confirmDelete(
    BuildContext context, {
      required String     message,
      required Future<void> Function() onConfirm,
    }) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
        SizedBox(width: 10),
        Text('Confirm Delete',
            style: TextStyle(color: Colors.redAccent, fontSize: 16,
                fontWeight: FontWeight.bold)),
      ]),
      content: Text(message,
          style: TextStyle(
              color  : Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : const Color(0xFF1A1F36),
              fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('CANCEL',
              style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.grey.shade600,
                  fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('DELETE',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    try {
      await onConfirm();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }
}