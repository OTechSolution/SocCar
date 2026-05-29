import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/email_otp_service.dart';
import '../main.dart' show AppTokens;

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String name;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.name,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _service     = EmailOtpService();
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes  = List.generate(6, (_) => FocusNode());

  bool    _verifying  = false;
  bool    _resending  = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes)  f.dispose();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() { _verifying = true; _error = null; _success = null; });

    final result = await _service.verifyOtp(
      email: widget.email,
      otp  : _otp,
    );

    if (!mounted) return;
    if (result.success) {
      setState(() { _verifying = false; _success = result.message; });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context, true); // ✅ pass true = verified
    } else {
      setState(() { _verifying = false; _error = result.message; });
    }
  }

  Future<void> _resend() async {
    setState(() { _resending = true; _error = null; _success = null; });
    final ok = await _service.sendOtp(email: widget.email, name: widget.name);
    if (!mounted) return;
    setState(() {
      _resending = false;
      _error     = ok ? null : 'Failed to resend. Try again.';
      _success   = ok ? 'New code sent to ${widget.email}' : null;
    });
    // Clear boxes
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? const Color(0xFF07090F) : const Color(0xFFF2F4FA);
    final cardBg  = isDark ? const Color(0xFF111728) : Colors.white;
    final borderC = isDark ? const Color(0xFF1E2340) : const Color(0xFFD0D8F0);
    final textClr = isDark ? Colors.white            : const Color(0xFF0D1B3E);
    final subClr  = isDark ? Colors.white60          : const Color(0xFF4A5580);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation      : 0,
        leading: IconButton(
          icon     : Icon(Icons.arrow_back_rounded, color: subClr),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const SizedBox(height: 16),

            // Icon
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(
                color : AppTokens.cyanAction.withOpacity(0.1),
                shape : BoxShape.circle,
                border: Border.all(
                    color: AppTokens.cyanAction.withOpacity(0.4), width: 2),
              ),
              child: const Icon(Icons.mark_email_read_rounded,
                  color: AppTokens.cyanAction, size: 40),
            ),
            const SizedBox(height: 24),

            Text('Enter Verification Code',
                style: TextStyle(color: textClr, fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Text('We sent a 6-digit code to',
                style: TextStyle(color: subClr, fontSize: 14)),
            const SizedBox(height: 4),
            Text(widget.email,
                style: const TextStyle(
                    color: AppTokens.cyanAction,
                    fontWeight: FontWeight.bold, fontSize: 14)),

            const SizedBox(height: 32),

            // OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (i) => _OtpBox(
                controller: _controllers[i],
                focusNode : _focusNodes[i],
                isDark    : isDark,
                onChanged : (val) {
                  if (val.isNotEmpty && i < 5) {
                    _focusNodes[i + 1].requestFocus();
                  }
                  if (val.isEmpty && i > 0) {
                    _focusNodes[i - 1].requestFocus();
                  }
                  if (_otp.length == 6) _verify();
                },
              )),
            ),

            const SizedBox(height: 24),

            // Error
            if (_error != null)
              _StatusBanner(message: _error!, isError: true),

            // Success
            if (_success != null)
              _StatusBanner(message: _success!, isError: false),

            const SizedBox(height: 24),

            // Verify button
            SizedBox(
              width: double.infinity, height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.cyanAction,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _verifying ? null : _verify,
                child: _verifying
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2.5))
                    : const Text('VERIFY',
                        style: TextStyle(fontWeight: FontWeight.w900,
                            fontSize: 15, letterSpacing: 1)),
              ),
            ),
            const SizedBox(height: 14),

            // Resend
            TextButton.icon(
              onPressed: _resending ? null : _resend,
              icon: _resending
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTokens.cyanAction))
                  : const Icon(Icons.refresh_rounded,
                      size: 16, color: AppTokens.cyanAction),
              label: Text(
                _resending ? 'Sending…' : 'Resend Code',
                style: const TextStyle(color: AppTokens.cyanAction,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Single OTP digit box ─────────────────────────────────────────────────────
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final bool                  isDark;
  final ValueChanged<String>  onChanged;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46, height: 56,
      child: TextField(
        controller        : controller,
        focusNode         : focusNode,
        textAlign         : TextAlign.center,
        keyboardType      : TextInputType.number,
        maxLength         : 1,
        onChanged         : onChanged,
        inputFormatters   : [FilteringTextInputFormatter.digitsOnly],
        style             : TextStyle(
          fontSize  : 22,
          fontWeight: FontWeight.bold,
          color     : isDark ? Colors.white : const Color(0xFF0D1B3E),
        ),
        decoration: InputDecoration(
          counterText : '',
          filled      : true,
          fillColor   : isDark
              ? const Color(0xFF111728) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : BorderSide(
                color: isDark
                    ? const Color(0xFF1E2340)
                    : const Color(0xFFD0D8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(
                color: AppTokens.cyanAction, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : BorderSide(
                color: isDark
                    ? const Color(0xFF1E2340)
                    : const Color(0xFFD0D8F0)),
          ),
        ),
      ),
    );
  }
}

// ── Status banner ────────────────────────────────────────────────────────────
class _StatusBanner extends StatelessWidget {
  final String message;
  final bool   isError;
  const _StatusBanner({required this.message, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : Colors.greenAccent;
    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin : const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color       : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border      : Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(children: [
        Icon(
          isError
              ? Icons.error_outline_rounded
              : Icons.check_circle_rounded,
          color: color, size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(message,
            style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}