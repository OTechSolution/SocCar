import 'package:cloud_firestore/cloud_firestore.dart';

enum SortDirection { asc, desc }

abstract class LogSortService {

  /// Sort Firestore docs by timestamp — Dart equivalent of JS sortFirebaseLogs().
  /// Handles: Firestore Timestamp, DateTime, String, int/double formats.
  /// Null timestamps are pushed to the end.
  static List<QueryDocumentSnapshot> sort(
    List<QueryDocumentSnapshot> docs, {
    SortDirection direction = SortDirection.desc,
  }) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final dateA = _extractDateTime(
          (a.data() as Map<String, dynamic>)['timestamp']);
      final dateB = _extractDateTime(
          (b.data() as Map<String, dynamic>)['timestamp']);

      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      return direction == SortDirection.desc
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });
    return sorted;
  }

  /// Sort raw log maps (from REST API or local cache).
  static List<Map<String, dynamic>> sortMaps(
    List<Map<String, dynamic>> logs, {
    SortDirection direction = SortDirection.desc,
  }) {
    final sorted = [...logs];
    sorted.sort((a, b) {
      final dateA = _extractDateTime(a['timestamp']);
      final dateB = _extractDateTime(b['timestamp']);

      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      return direction == SortDirection.desc
          ? dateB.compareTo(dateA)
          : dateA.compareTo(dateB);
    });
    return sorted;
  }

  static DateTime? _extractDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime)  return ts;
    if (ts is String) {
      final cleaned = ts
          .replaceAll(' at ', ' ')
          .replaceAll(RegExp(r'UTC[+-]\d+:\d+'), '')
          .trim();
      return DateTime.tryParse(cleaned);
    }
    if (ts is int)    return DateTime.fromMillisecondsSinceEpoch(ts);
    if (ts is double) return DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    return null;
  }

  /// Format timestamp for display:
  ///   < 1 min  → "Just now"
  ///   < 1 hr   → "5m ago"
  ///   < 24 hr  → "3h ago"
  ///   older    → "16/05/2026  10:18"
  static String formatForDisplay(dynamic ts) {
    final dt = _extractDateTime(ts);
    if (dt == null) return 'Just now';

    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';

    final d   = dt.day.toString().padLeft(2, '0');
    final m   = dt.month.toString().padLeft(2, '0');
    final h   = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year}  $h:$min';
  }
}
