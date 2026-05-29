import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class EmailOtpService {
  static final EmailOtpService _i = EmailOtpService._();
  factory EmailOtpService() => _i;
  EmailOtpService._();

  final _db = FirebaseFirestore.instance;

  // ── Fetch Resend API key from Firestore ──────────────────────────────────
  Future<String?> _getApiKey() async {
    try {
      final snap = await _db.collection('config').doc('resend').get();
      return snap.data()?['apiKey'] as String?;
    } catch (e) {
      debugPrint('EmailOtpService: failed to fetch API key: $e');
      return null;
    }
  }

  // ── Generate 6-digit OTP ─────────────────────────────────────────────────
  String _generateOtp() {
    final rand = Random.secure();
    return (100000 + rand.nextInt(900000)).toString();
  }

  // ── Send OTP ─────────────────────────────────────────────────────────────
  // Returns true if the email was sent successfully.
  //
  // FIX 1: Removed debug internet-test request to google.com — not needed.
  // FIX 2: Added a 15-second timeout so the call doesn't hang forever.
  // FIX 3: 'from' address must match a domain verified in your Resend
  //         dashboard. Change 'onboarding@resend.dev' to your own verified
  //         sender e.g. 'noreply@yourdomain.com'. If you don't have a custom
  //         domain yet, Resend allows sending to your own registered email
  //         only on the free plan — add that email in Resend → Settings →
  //         Domains, or use a verified domain you own.
  Future<bool> sendOtp({
    required String email,
    required String name,
  }) async {
    try {
      final apiKey = await _getApiKey();
      if (apiKey == null) {
        debugPrint('EmailOtpService: API key not found in Firestore config/resend');
        return false;
      }

      final otp    = _generateOtp();
      final expiry = DateTime.now().add(const Duration(minutes: 10));

      // Save OTP to Firestore first (so verify works even if HTTP is slow)
      await _db.collection('otpVerifications').doc(email.toLowerCase()).set({
        'otp'      : otp,
        'name'     : name,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiry),
        'verified' : false,
        'attempts' : 0,
      });

      // ── Send via Resend API ──────────────────────────────────────────────
      // IMPORTANT: change the 'from' value below to your verified sender.
      // On Resend free plan → your Resend account email only.
      // With a verified domain → any address @yourdomain.com
      final response = await http
          .post(
            Uri.parse('https://api.resend.com/emails'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type' : 'application/json',
            },
            body: jsonEncode({
              'from'   : 'SocCar <onboarding@resend.dev>', // ← CHANGE THIS
              'to'     : [email],
              'subject': 'Your SocCar Verification Code',
              'html'   : _buildEmailHtml(name, otp),
            }),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('EmailOtpService: Resend API timed out after 15s');
              return http.Response('{"error":"timeout"}', 408);
            },
          );

      debugPrint('Resend status: ${response.statusCode}');
      debugPrint('Resend body  : ${response.body}');

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e, st) {
      debugPrint('EmailOtpService.sendOtp ERROR: $e\n$st');
      return false;
    }
  }

  // ── Verify OTP ───────────────────────────────────────────────────────────
  // FIX 4: Moved the attempts increment to AFTER the OTP match check so the
  //         user gets exactly 5 attempts and the "remaining" count is correct.
  Future<OtpResult> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final ref  = _db.collection('otpVerifications').doc(email.toLowerCase());
      final doc  = await ref.get();

      if (!doc.exists) {
        return const OtpResult(
            success: false,
            message: 'No OTP found. Please request a new one.');
      }

      final data     = doc.data()!;
      final attempts = (data['attempts'] ?? 0) as int;

      // Already verified
      if (data['verified'] == true) {
        return const OtpResult(success: true, message: 'Already verified.');
      }

      // Max 5 attempts
      if (attempts >= 5) {
        return const OtpResult(
            success: false,
            message: 'Too many incorrect attempts. Please request a new OTP.');
      }

      // Check expiry
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        return const OtpResult(
            success: false,
            message: 'OTP expired. Please request a new one.');
      }

      // Check OTP — increment ONLY on wrong answer
      if (data['otp'] != otp) {
        await ref.update({'attempts': attempts + 1});
        final remaining = 4 - attempts; // 5 total − 1 just used − already used
        return OtpResult(
          success: false,
          message: remaining > 0
              ? 'Incorrect code. $remaining attempt${remaining == 1 ? '' : 's'} remaining.'
              : 'Too many incorrect attempts. Please request a new OTP.',
        );
      }

      // ✅ Correct — mark verified
      await ref.update({'verified': true});
      return const OtpResult(success: true, message: 'Email verified successfully!');
    } catch (e) {
      debugPrint('EmailOtpService.verifyOtp ERROR: $e');
      return OtpResult(success: false, message: 'Error verifying code: $e');
    }
  }

  // ── Email HTML template ──────────────────────────────────────────────────
  String _buildEmailHtml(String name, String otp) => '''
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;
                background:#0A0A1A;color:#fff;border-radius:16px;padding:32px;">
      <h2 style="color:#00E5FF;margin-bottom:4px;">SocCar</h2>
      <p style="color:#B0B7D4;margin-top:0;">Society Car &amp; Delivery Management</p>
      <hr style="border-color:#2E3160;margin:20px 0"/>
      <p>Hi <strong>$name</strong>,</p>
      <p style="color:#B0B7D4;">Your verification code is:</p>
      <div style="background:#141428;border:2px solid #00E5FF;border-radius:12px;
                  text-align:center;padding:24px;margin:24px 0;">
        <span style="font-size:40px;font-weight:900;letter-spacing:12px;color:#00E5FF;">
          $otp
        </span>
      </div>
      <p style="color:#B0B7D4;font-size:13px;">
        &#9200; This code expires in <strong>10 minutes</strong>.<br/>
        If you didn&#39;t request this, ignore this email.
      </p>
    </div>
  ''';
}

class OtpResult {
  final bool   success;
  final String message;
  const OtpResult({required this.success, required this.message});
}