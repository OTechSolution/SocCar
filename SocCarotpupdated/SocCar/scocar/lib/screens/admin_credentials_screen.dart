import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminCredentialsScreen
//
// WHAT CHANGED:
//   OLD: received adminId + accessCode as constructor params (from navigation)
//   NEW: fetches them LIVE from Firebase by matching societyName + email
//
// FIREBASE QUERY LOGIC:
//   1. Query societies collection where:
//        societyName == widget.societyName  AND  adminEmail == widget.email
//   2. If found → read adminId + accessCode from that document
//   3. Show credentials with copy buttons, countdown, checkbox
//   4. After "I've Saved" → mark credentialsShownAt in Firestore + go to dashboard
//
// This means even if navigation args were wrong/missing, the screen
// always shows the REAL credentials from Firebase.
// ─────────────────────────────────────────────────────────────────────────────

class AdminCredentialsScreen extends StatefulWidget {
  // These are used as the lookup keys — NOT the credential values
  final String societyName;
  final String email;

  // Optional fallback if Firebase fetch fails (can be empty strings)
  final String societyId;

  const AdminCredentialsScreen({
    super.key,
    required this.societyName,
    required this.email,
    required this.societyId,
  });

  @override
  State<AdminCredentialsScreen> createState() => _AdminCredentialsScreenState();
}

class _AdminCredentialsScreenState extends State<AdminCredentialsScreen> {

  // ── Fetched from Firebase ──────────────────────────────────────────────────
  String? _adminId;
  String? _accessCode;
  String? _resolvedSocietyId;
  bool    _isLoading    = true;
  String? _fetchError;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _idCopied    = false;
  bool _codeCopied  = false;
  bool _bothCopied  = false;
  bool _confirmed   = false;
  bool _canProceed  = false;
  int  _countdown   = 10;

  static const Color _kGold = Color(0xFFFFB300);

  @override
  void initState() {
    super.initState();
    _fetchCredentials();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1: Fetch credentials from Firebase
  //
  // Queries societies collection where:
  //   societyName matches  AND  adminEmail matches
  //
  // Falls back to societyId doc lookup if name+email query returns nothing
  // (handles edge case where society name has whitespace differences)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _fetchCredentials() async {
    setState(() { _isLoading = true; _fetchError = null; });

    try {
      final db = FirebaseFirestore.instance;
      DocumentSnapshot? foundDoc;

      // ── Strategy 1: match by societyName + adminEmail (most precise) ──────
      final byNameEmail = await db
          .collection('societies')
          .where('societyName', isEqualTo: widget.societyName)
          .where('adminEmail', isEqualTo: widget.email.trim().toLowerCase())
          .limit(1)
          .get();

      if (byNameEmail.docs.isNotEmpty) {
        foundDoc = byNameEmail.docs.first;
      }

      // ── Strategy 2: match by societyId doc (fallback) ─────────────────────
      if (foundDoc == null && widget.societyId.isNotEmpty) {
        final byId = await db.collection('societies').doc(widget.societyId).get();
        if (byId.exists) {
          final data = byId.data() as Map<String, dynamic>?;
          // Verify the email matches to prevent showing wrong credentials
          final storedEmail = (data?['adminEmail'] as String?)?.toLowerCase() ?? '';
          if (storedEmail == widget.email.trim().toLowerCase()) {
            foundDoc = byId;
          }
        }
      }

      // ── Strategy 3: match by email alone (last resort) ────────────────────
      if (foundDoc == null) {
        final byEmail = await db
            .collection('societies')
            .where('adminEmail', isEqualTo: widget.email.trim().toLowerCase())
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) {
          foundDoc = byEmail.docs.first;
        }
      }

      if (foundDoc == null) {
        setState(() {
          _isLoading  = false;
          _fetchError = 'No society found matching:\n'
              'Society: ${widget.societyName}\n'
              'Email: ${widget.email}\n\n'
              'Please contact support or re-register.';
        });
        return;
      }

      final data       = foundDoc.data() as Map<String, dynamic>;
      final adminId    = data['adminId']    as String?;
      final accessCode = data['accessCode'] as String?;

      if (adminId == null || adminId.isEmpty ||
          accessCode == null || accessCode.isEmpty) {
        setState(() {
          _isLoading  = false;
          _fetchError = 'Credentials not yet generated for this society.\n'
              'Please wait a moment and tap Retry.\n\n'
              'If this persists, contact support.';
        });
        return;
      }

      setState(() {
        _adminId            = adminId;
        _accessCode         = accessCode;
        _resolvedSocietyId  = foundDoc!.id;
        _isLoading          = false;
      });

      // Start countdown only after credentials are loaded
      _startCountdown();

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading  = false;
          _fetchError = 'Firebase error: $e\n\nCheck your internet connection and tap Retry.';
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Countdown — 10 seconds before Proceed button unlocks
  // ─────────────────────────────────────────────────────────────────────────
  void _startCountdown() {
    _countdown   = 10;
    _canProceed  = false;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _countdown--;
        if (_countdown <= 0) _canProceed = true;
      });
      return _countdown > 0;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Copy helpers
  // ─────────────────────────────────────────────────────────────────────────
  void _copy(String value, {required bool isCode}) {
    Clipboard.setData(ClipboardData(text: value));
    setState(() {
      if (isCode) _codeCopied = true;
      else        _idCopied   = true;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _idCopied = false; _codeCopied = false; });
    });
  }

  void _copyBoth() {
    final text = 'SocCar Admin Credentials\n'
        'Society:     ${widget.societyName}\n'
        'Admin ID:    $_adminId\n'
        'Access Code: $_accessCode\n'
        '⚠️  Keep this private. Not shown again.';
    Clipboard.setData(ClipboardData(text: text));
    setState(() => _bothCopied = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _bothCopied = false);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Proceed to dashboard
  // Also marks credentialsViewed in Firestore so we know they saw it
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _proceed() async {
    final sid = _resolvedSocietyId ?? widget.societyId;

    // Fire-and-forget: mark that credentials were shown
    if (sid.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('societies')
          .doc(sid)
          .update({'credentialsViewedAt': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/admin_dashboard',
      arguments: {
        'societyId'  : sid,
        'societyName': widget.societyName,
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF07090F) : const Color(0xFFF2F4FA);
    final cardBg  = isDark ? const Color(0xFF111728) : Colors.white;
    final borderC = isDark ? const Color(0xFF1E2340) : const Color(0xFFD0D8F0);
    final textClr = isDark ? Colors.white             : const Color(0xFF0D1B3E);
    final subClr  = isDark ? Colors.white60           : const Color(0xFF4A5580);
    final fieldBg = isDark ? const Color(0xFF0D0F1E)  : const Color(0xFFF8F9FE);

    return WillPopScope(
      onWillPop: () async {
        // Block back — only allow if loading failed (so they can escape)
        if (_fetchError != null) return true;
        _showCannotGoBack(context, textClr, cardBg);
        return false;
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: _isLoading
              ? _buildLoading(isDark)
              : _fetchError != null
              ? _buildError(isDark, textClr, subClr)
              : _buildCredentials(
              isDark, bg, cardBg, borderC, textClr, subClr, fieldBg),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Loading state
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildLoading(bool isDark) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kGold.withOpacity(0.10),
          shape: BoxShape.circle,
          border: Border.all(color: _kGold.withOpacity(0.3), width: 1.5),
        ),
        child: const CircularProgressIndicator(
            color: _kGold, strokeWidth: 2.5),
      ),
      const SizedBox(height: 24),
      Text('Fetching your credentials…',
          style: TextStyle(
              color: isDark ? Colors.white70 : const Color(0xFF0D1B3E),
              fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Verifying society: ${widget.societyName}',
          style: TextStyle(
              color: isDark ? Colors.white38 : const Color(0xFF4A5580),
              fontSize: 12)),
      const SizedBox(height: 4),
      Text(widget.email,
          style: const TextStyle(color: _kGold, fontSize: 12)),
    ]),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Error state
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildError(bool isDark, Color textClr, Color subClr) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1.5),
          ),
          child: const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 44),
        ),
        const SizedBox(height: 24),
        const Text('Could Not Load Credentials',
            style: TextStyle(
                color: Colors.redAccent,
                fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(_fetchError!,
            style: TextStyle(color: subClr, fontSize: 13, height: 1.6),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            onPressed: _fetchCredentials,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('RETRY',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('← Go Back',
              style: TextStyle(color: subClr, fontSize: 13)),
        ),
      ]),
    ),
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Main credentials view
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCredentials(bool isDark, Color bg, Color cardBg,
      Color borderC, Color textClr, Color subClr, Color fieldBg) {

    final bool canProceed = _canProceed && _confirmed;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // ── Firebase verified badge ────────────────────────────────────
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_rounded,
                    color: Colors.greenAccent, size: 14),
                const SizedBox(width: 7),
                Text('Fetched from Firebase · ${widget.email}',
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // ── Warning banner ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.redAccent.withOpacity(0.5), width: 1.5),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SHOWN ONLY ONCE',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 13, letterSpacing: 0.6)),
                      const SizedBox(height: 4),
                      Text(
                        'These credentials will never be displayed again. '
                            'Copy and save them somewhere safe before continuing.',
                        style: TextStyle(
                            color: Colors.redAccent.withOpacity(0.85),
                            fontSize: 12, height: 1.5),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 22),

          // ── Header ────────────────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _kGold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _kGold.withOpacity(0.3)),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: _kGold, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your Admin Credentials',
                        style: TextStyle(
                            color: textClr, fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Text(widget.societyName,
                        style: const TextStyle(
                            color: _kGold,
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Credentials card ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _kGold.withOpacity(0.4), width: 1.5),
              boxShadow: [BoxShadow(
                color: _kGold.withOpacity(0.08),
                blurRadius: 24, offset: const Offset(0, 6),
              )],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Admin ID
                _credLabel('ADMIN ID', subClr),
                const SizedBox(height: 8),
                _CredRow(
                  value    : _adminId!,
                  fieldBg  : fieldBg,
                  borderC  : borderC,
                  textClr  : textClr,
                  accent   : _kGold,
                  copied   : _idCopied,
                  onCopy   : () => _copy(_adminId!, isCode: false),
                  icon     : Icons.badge_rounded,
                  monospace: true,
                ),
                const SizedBox(height: 20),

                // Access Code
                _credLabel('ACCESS CODE', subClr),
                const SizedBox(height: 8),
                _CredRow(
                  value    : _accessCode!,
                  fieldBg  : fieldBg,
                  borderC  : borderC,
                  textClr  : textClr,
                  accent   : _kGold,
                  copied   : _codeCopied,
                  onCopy   : () => _copy(_accessCode!, isCode: true),
                  icon     : Icons.lock_rounded,
                  monospace: true,
                  isSecret : true,
                ),
                const SizedBox(height: 22),

                // Copy Both
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _bothCopied
                          ? Colors.greenAccent
                          : _kGold.withOpacity(0.15),
                      foregroundColor:
                      _bothCopied ? Colors.black : _kGold,
                      elevation: 0,
                      side: BorderSide(
                          color: _bothCopied
                              ? Colors.greenAccent
                              : _kGold.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _copyBoth,
                    icon: Icon(
                        _bothCopied
                            ? Icons.check_rounded
                            : Icons.copy_all_rounded,
                        size: 18),
                    label: Text(
                      _bothCopied
                          ? 'COPIED TO CLIPBOARD ✓'
                          : 'COPY BOTH TO CLIPBOARD',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Save tips ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.blueAccent.withOpacity(0.07)
                  : const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.tips_and_updates_rounded,
                      color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 8),
                  Text('Where to save these:',
                      style: TextStyle(
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF1A1A2E),
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                for (final tip in [
                  '📝  Screenshot this screen',
                  '📩  Forward to your own email',
                  '🔐  Save in a password manager',
                  '💬  WhatsApp yourself the code',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(tip,
                        style: TextStyle(
                            color: subClr, fontSize: 12.5, height: 1.4)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── How to login ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kGold.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _kGold.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_rounded, color: _kGold, size: 16),
                  const SizedBox(width: 8),
                  Text('How to log in next time:',
                      style: TextStyle(
                          color: textClr,
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                Text(
                  '1. Open SocCar OS → Login screen\n'
                      '2. Select the "Admin" role\n'
                      '3. Enter your Admin ID and Access Code\n'
                      '4. Tap "Authenticate"',
                  style: TextStyle(
                      color: subClr, fontSize: 12.5, height: 1.65),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Countdown indicator ───────────────────────────────────────
          if (!_canProceed) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _kGold.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGold.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: _kGold, size: 15),
                  const SizedBox(width: 7),
                  Text('Please read carefully — $_countdown seconds',
                      style: const TextStyle(
                          color: _kGold,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── Confirmation checkbox ─────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _confirmed = !_confirmed),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: _confirmed ? _kGold : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _confirmed ? _kGold : borderC,
                      width: 1.5,
                    ),
                  ),
                  child: _confirmed
                      ? const Icon(Icons.check_rounded,
                      color: Colors.black, size: 14)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I have copied or saved my Admin ID and Access Code. '
                        'I understand these will not be shown again.',
                    style: TextStyle(
                        color: textClr, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Proceed button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity, height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed
                    ? _kGold
                    : _kGold.withOpacity(0.3),
                foregroundColor: Colors.black,
                elevation: canProceed ? 6 : 0,
                shadowColor: _kGold.withOpacity(0.35),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: canProceed ? _proceed : null,
              icon: Icon(
                  canProceed
                      ? Icons.arrow_forward_rounded
                      : Icons.lock_rounded,
                  size: 22),
              label: Text(
                canProceed
                    ? "I'VE SAVED MY CREDENTIALS — CONTINUE"
                    : _confirmed
                    ? 'Please wait $_countdown seconds…'
                    : 'Tick the checkbox above to continue',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14, letterSpacing: 0.3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'You can reset your Access Code from the Admin Dashboard.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subClr, fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _credLabel(String text, Color color) => Text(
    text,
    style: TextStyle(
        color: color, fontSize: 10,
        fontWeight: FontWeight.w800, letterSpacing: 1.2),
  );

  void _showCannotGoBack(
      BuildContext ctx, Color textClr, Color cardBg) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: cardBg,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Text('Save Your Credentials',
              style: TextStyle(
                  color: Colors.white, fontSize: 16)),
        ]),
        content: Text(
          'Please copy or save your Admin ID and Access Code '
              'before leaving. They will not be shown again.',
          style: TextStyle(
              color: textClr.withOpacity(0.7),
              fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK, I'll save them first",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CredRow — individual credential field with copy + show/hide
// ─────────────────────────────────────────────────────────────────────────────
class _CredRow extends StatefulWidget {
  final String     value;
  final Color      fieldBg;
  final Color      borderC;
  final Color      textClr;
  final Color      accent;
  final bool       copied;
  final VoidCallback onCopy;
  final IconData   icon;
  final bool       monospace;
  final bool       isSecret;

  const _CredRow({
    required this.value,
    required this.fieldBg,
    required this.borderC,
    required this.textClr,
    required this.accent,
    required this.copied,
    required this.onCopy,
    required this.icon,
    this.monospace = false,
    this.isSecret  = false,
  });

  @override
  State<_CredRow> createState() => _CredRowState();
}

class _CredRowState extends State<_CredRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final display = (widget.isSecret && !_revealed)
        ? '•' * widget.value.length
        : widget.value;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: widget.fieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.copied
              ? Colors.greenAccent.withOpacity(0.6)
              : widget.borderC,
          width: widget.copied ? 1.5 : 1,
        ),
      ),
      child: Row(children: [
        Icon(widget.icon, color: widget.accent, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            display,
            style: TextStyle(
              color     : widget.copied
                  ? Colors.greenAccent
                  : widget.textClr,
              fontSize  : 15,
              fontWeight: FontWeight.bold,
              letterSpacing: widget.monospace ? 1.8 : 0,
              fontFamily: widget.monospace ? 'monospace' : null,
            ),
          ),
        ),
        // Show / hide toggle for Access Code
        if (widget.isSecret) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _revealed = !_revealed),
            child: Icon(
              _revealed
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: widget.textClr.withOpacity(0.4),
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
        ],
        // Copy button
        GestureDetector(
          onTap: widget.onCopy,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: widget.copied
                  ? Colors.greenAccent.withOpacity(0.15)
                  : widget.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.copied
                    ? Colors.greenAccent.withOpacity(0.4)
                    : widget.accent.withOpacity(0.3),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                widget.copied
                    ? Icons.check_rounded
                    : Icons.copy_rounded,
                size: 14,
                color: widget.copied
                    ? Colors.greenAccent
                    : widget.accent,
              ),
              const SizedBox(width: 4),
              Text(
                widget.copied ? 'Copied' : 'Copy',
                style: TextStyle(
                  color: widget.copied
                      ? Colors.greenAccent
                      : widget.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}