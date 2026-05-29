import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveVisitorsTab extends StatelessWidget {
  const ActiveVisitorsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('approvals')
          .where('status', isEqualTo: 'COMPLETED')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: cs.primary),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        // Only visitors still inside (no exitTime)
        final docs = (snapshot.data?.docs ?? [])
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['exitTime'] == null;
            })
            .toList();

        // ── Empty state ──────────────────────────────────────────────────────
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Colors.greenAccent,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No active visitors inside',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Society perimeter is clear.',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.38),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }

        // ── List with header count ───────────────────────────────────────────
        return Column(
          children: [
            // Header count banner
            Container(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.orangeAccent.withOpacity(0.12)
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.orangeAccent.withOpacity(isDark ? 0.4 : 0.55),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    color: isDark ? Colors.orangeAccent : Colors.orange.shade800,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${docs.length} visitor${docs.length == 1 ? '' : 's'} currently inside',
                    style: TextStyle(
                      color: isDark
                          ? Colors.orangeAccent
                          : Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Visitor tiles
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc  = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _VisitorTile(docId: doc.id, data: data);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VisitorTile — individual row with photo, details, Log Exit button
// ─────────────────────────────────────────────────────────────────────────────
class _VisitorTile extends StatefulWidget {
  final String             docId;
  final Map<String, dynamic> data;

  const _VisitorTile({required this.docId, required this.data});

  @override
  State<_VisitorTile> createState() => _VisitorTileState();
}

class _VisitorTileState extends State<_VisitorTile> {
  bool _loggingExit = false;

  Future<void> _logExit() async {
    setState(() => _loggingExit = true);
    try {
      await FirebaseFirestore.instance
          .collection('approvals')
          .doc(widget.docId)
          .update({
        'exitTime': FieldValue.serverTimestamp(),
        'status'  : 'EXITED',
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content         : Text('Failed to log exit: $e'),
            backgroundColor : Colors.red,
          ),
        );
        setState(() => _loggingExit = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs     = Theme.of(context).colorScheme;

    // Theme-resolved surface colours
    final cardBg     = isDark ? const Color(0xFF141428) : Colors.white;
    final cardBorder = isDark ? Colors.white10          : Colors.black.withOpacity(0.08);
    final titleColor = cs.onSurface;
    final flatColor  = isDark ? Colors.cyanAccent       : cs.primary;
    final timeColor  = cs.onSurface.withOpacity(0.40);
    final avatarBg   = isDark
        ? Colors.white10
        : Colors.blueGrey.shade100;
    final avatarText = isDark
        ? Colors.white60
        : Colors.blueGrey.shade600;

    final String company   = widget.data['company']    ?? 'Visitor';
    final String flat      = widget.data['flatNumber'] ?? '?';
    final String? photoUrl = widget.data['visitorPhotoUrl'] as String?;

    // Time inside
    String timeInsideLabel = '';
    final ts = widget.data['completedAt'] ?? widget.data['timestamp'];
    if (ts is Timestamp) {
      final diff = DateTime.now().difference(ts.toDate());
      timeInsideLabel = diff.inMinutes < 60
          ? '${diff.inMinutes}m inside'
          : '${diff.inHours}h ${diff.inMinutes % 60}m inside';
    }

    return Container(
      margin    : const EdgeInsets.only(bottom: 12),
      padding   : const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color       : cardBg,
        borderRadius: BorderRadius.circular(18),
        border      : Border.all(color: cardBorder),
        boxShadow   : isDark
            ? []
            : [
                BoxShadow(
                  color    : Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset   : const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [

          // ── Photo / avatar ───────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    width : 60,
                    height: 60,
                    fit   : BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _avatarFallback(company, avatarBg, avatarText),
                  )
                : _avatarFallback(company, avatarBg, avatarText),
          ),
          const SizedBox(width: 14),

          // ── Details ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company,
                  style: TextStyle(
                    color     : titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize  : 15,
                  ),
                ),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.apartment_rounded, color: flatColor, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    'Flat $flat',
                    style: TextStyle(color: flatColor, fontSize: 12),
                  ),
                ]),
                if (timeInsideLabel.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    timeInsideLabel,
                    style: TextStyle(color: timeColor, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),

          // ── Log Exit button ──────────────────────────────────────────
          SizedBox(
            width: 88,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding        : const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              onPressed: _loggingExit ? null : _logExit,
              child: _loggingExit
                  ? const SizedBox(
                      width : 16,
                      height: 16,
                      child : CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.exit_to_app_rounded,
                            color: Colors.white, size: 16),
                        SizedBox(height: 2),
                        Text(
                          'Log Exit',
                          style: TextStyle(
                            color     : Colors.white,
                            fontSize  : 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String company, Color bg, Color textColor) {
    return Container(
      width : 60,
      height: 60,
      decoration: BoxDecoration(color: bg),
      child: Center(
        child: Text(
          company.isNotEmpty ? company[0].toUpperCase() : '?',
          style: TextStyle(
            color     : textColor,
            fontWeight: FontWeight.bold,
            fontSize  : 22,
          ),
        ),
      ),
    );
  }
}
