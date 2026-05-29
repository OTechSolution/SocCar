import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SubscriptionService
//
// Manages the per-society subscription lifecycle:
//
//   FREE TRIAL  — 7 days from first admin login, no payment required
//   ACTIVE      — paid ₹1000/year, full access
//   EXPIRED     — trial or subscription ended, payment wall shown
//   REFUNDED    — 50% refund processed within 30 days of payment
//
// Firestore schema  (collection: 'subscriptions', doc id: placeId)
// ─────────────────────────────────────────────────────────────────────────────
//   {
//     placeId        : String,          // Google place_id as unique society key
//     societyName    : String,
//     planType       : 'TRIAL' | 'ANNUAL',
//     status         : 'TRIAL' | 'ACTIVE' | 'EXPIRED' | 'REFUNDED',
//     trialStartedAt : Timestamp,
//     trialEndsAt    : Timestamp,       // trialStartedAt + 7 days
//     paidAt         : Timestamp?,      // null until first payment
//     expiresAt      : Timestamp?,      // paidAt + 365 days
//     refundedAt     : Timestamp?,
//     refundAmount   : int?,            // 500 (50% of 1000)
//     razorpayOrderId: String?,
//     razorpayPaymentId: String?,
//   }
// ─────────────────────────────────────────────────────────────────────────────

enum SubscriptionStatus { trial, active, expired, refunded }

class SubscriptionInfo {
  final String             placeId;
  final String             societyName;
  final SubscriptionStatus status;
  final DateTime           trialEndsAt;
  final DateTime?          expiresAt;
  final DateTime?          paidAt;
  final bool               isRefunded;
  final bool               canRefund;   // within 30 days of payment
  final int                trialDaysLeft;

  const SubscriptionInfo({
    required this.placeId,
    required this.societyName,
    required this.status,
    required this.trialEndsAt,
    this.expiresAt,
    this.paidAt,
    this.isRefunded   = false,
    this.canRefund    = false,
    this.trialDaysLeft = 0,
  });

  bool get hasAccess =>
      status == SubscriptionStatus.trial || status == SubscriptionStatus.active;

  bool get isTrial  => status == SubscriptionStatus.trial;
  bool get isActive => status == SubscriptionStatus.active;
  bool get isExpired => status == SubscriptionStatus.expired;
}

class SubscriptionService {
  static final SubscriptionService _i = SubscriptionService._();
  factory SubscriptionService() => _i;
  SubscriptionService._();

  final _db = FirebaseFirestore.instance;

  // ── Check or create subscription for a society ─────────────────────────────
  Future<SubscriptionInfo> checkSubscription({
    required String placeId,
    required String societyName,
  }) async {
    final ref = _db.collection('subscriptions').doc(placeId);
    final snap = await ref.get();

    if (!snap.exists) {
      // First time this society logs in — create 7-day free trial
      final now        = DateTime.now();
      final trialEnds  = now.add(const Duration(days: 7));
      await ref.set({
        'placeId'       : placeId,
        'societyName'   : societyName,
        'planType'      : 'TRIAL',
        'status'        : 'TRIAL',
        'trialStartedAt': FieldValue.serverTimestamp(),
        'trialEndsAt'   : Timestamp.fromDate(trialEnds),
        'paidAt'        : null,
        'expiresAt'     : null,
        'refundedAt'    : null,
        'refundAmount'  : null,
        'razorpayOrderId'  : null,
        'razorpayPaymentId': null,
      });
      return SubscriptionInfo(
        placeId       : placeId,
        societyName   : societyName,
        status        : SubscriptionStatus.trial,
        trialEndsAt   : trialEnds,
        trialDaysLeft : 7,
      );
    }

    return _parseSubscription(snap.data()!);
  }

  // ── Mark subscription as paid (call after Razorpay success callback) ────────
  Future<void> activateSubscription({
    required String placeId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
  }) async {
    final now     = DateTime.now();
    final expires = now.add(const Duration(days: 365));
    await _db.collection('subscriptions').doc(placeId).update({
      'planType'         : 'ANNUAL',
      'status'           : 'ACTIVE',
      'paidAt'           : FieldValue.serverTimestamp(),
      'expiresAt'        : Timestamp.fromDate(expires),
      'razorpayOrderId'  : razorpayOrderId,
      'razorpayPaymentId': razorpayPaymentId,
    });
  }

  // ── Process 50% refund request ─────────────────────────────────────────────
  // NOTE: The actual Razorpay refund API call should be made from your
  // backend (Firebase Cloud Function) using the secret key.
  // This method records the refund intent in Firestore.
  // Your Cloud Function watches for status == 'REFUND_REQUESTED'
  // and calls Razorpay's POST /v1/payments/{id}/refund.
  Future<bool> requestRefund({required String placeId}) async {
    try {
      final snap = await _db.collection('subscriptions').doc(placeId).get();
      if (!snap.exists) return false;

      final data    = snap.data()!;
      final paidAt  = (data['paidAt'] as Timestamp?)?.toDate();
      if (paidAt == null) return false;

      // Only within 30 days of payment
      final daysSincePaid = DateTime.now().difference(paidAt).inDays;
      if (daysSincePaid > 30) return false;

      await _db.collection('subscriptions').doc(placeId).update({
        'status'       : 'REFUND_REQUESTED',
        'refundedAt'   : FieldValue.serverTimestamp(),
        'refundAmount' : 500, // 50% of ₹1000
      });
      return true;
    } catch (e) {
      debugPrint('SubscriptionService.requestRefund error: $e');
      return false;
    }
  }

  // ── Parse Firestore doc into SubscriptionInfo ──────────────────────────────
  SubscriptionInfo _parseSubscription(Map<String, dynamic> data) {
    final placeId     = data['placeId']      as String? ?? '';
    final societyName = data['societyName']  as String? ?? '';
    final statusStr   = data['status']       as String? ?? 'EXPIRED';
    final trialEnds   = (data['trialEndsAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final paidAt      = (data['paidAt']      as Timestamp?)?.toDate();
    final expiresAt   = (data['expiresAt']   as Timestamp?)?.toDate();
    final refundedAt  = (data['refundedAt']  as Timestamp?)?.toDate();

    final now = DateTime.now();

    // Determine effective status
    SubscriptionStatus status;
    switch (statusStr) {
      case 'TRIAL':
        status = now.isBefore(trialEnds)
            ? SubscriptionStatus.trial
            : SubscriptionStatus.expired;
        break;
      case 'ACTIVE':
        status = (expiresAt != null && now.isBefore(expiresAt))
            ? SubscriptionStatus.active
            : SubscriptionStatus.expired;
        break;
      case 'REFUNDED':
      case 'REFUND_REQUESTED':
        status = SubscriptionStatus.refunded;
        break;
      default:
        status = SubscriptionStatus.expired;
    }

    final trialDaysLeft = status == SubscriptionStatus.trial
        ? trialEnds.difference(now).inDays + 1
        : 0;

    // Refund eligibility: paid, within 30 days, not already refunded
    final canRefund = paidAt != null &&
        refundedAt == null &&
        now.difference(paidAt).inDays <= 30 &&
        status == SubscriptionStatus.active;

    return SubscriptionInfo(
      placeId       : placeId,
      societyName   : societyName,
      status        : status,
      trialEndsAt   : trialEnds,
      expiresAt     : expiresAt,
      paidAt        : paidAt,
      isRefunded    : refundedAt != null,
      canRefund     : canRefund,
      trialDaysLeft : trialDaysLeft,
    );
  }
}