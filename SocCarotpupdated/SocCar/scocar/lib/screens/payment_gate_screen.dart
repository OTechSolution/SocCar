import 'package:flutter/material.dart';
import '../main.dart' show AppTokens, themeNotifier;
import '../services/subscription_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PaymentGateScreen
//
// FLOW after admin credentials are verified in login_screen.dart:
//
//   1. Screen auto-calls SubscriptionService.checkSubscription()
//   2a. TRIAL (≥1 day left)  → show trial banner + "Continue Free Trial" btn
//   2b. ACTIVE               → show active badge + "Enter Dashboard" btn
//   2c. EXPIRED / REFUNDED   → show payment wall, "Pay ₹1000/year" btn
//
// On "Pay" the user is routed to RazorpayWebScreen (stub included below).
// On success callback → SubscriptionService.activateSubscription() is called
// and the user is pushed to /admin_dashboard.
//
// This screen is NOT accessible without valid admin credentials — login_screen
// already checked those before navigating here.
// ─────────────────────────────────────────────────────────────────────────────

class PaymentGateScreen extends StatefulWidget {
  final String placeId;
  final String societyName;
  final String societyAddress;

  const PaymentGateScreen({
    super.key,
    required this.placeId,
    required this.societyName,
    required this.societyAddress,
  });

  @override
  State<PaymentGateScreen> createState() => _PaymentGateScreenState();
}

class _PaymentGateScreenState extends State<PaymentGateScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  SubscriptionInfo? _info;
  bool              _loading     = true;
  bool              _paying      = false;
  String?           _errorMsg;

  // ── Colours ───────────────────────────────────────────────────────────────
  static const Color _gold     = Color(0xFFFFB300);
  static const Color _goldDark = Color(0xFFFFCA28);

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  // ── Subscription check ────────────────────────────────────────────────────

  Future<void> _loadSubscription() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final info = await SubscriptionService().checkSubscription(
        placeId    : widget.placeId,
        societyName: widget.societyName,
      );
      if (mounted) setState(() { _info = info; _loading = false; });

      // Auto-pass ACTIVE subscriptions straight through
      if (mounted && info.isActive) {
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _enterDashboard();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Could not check subscription: $e';
          _loading  = false;
        });
      }
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _enterDashboard() {
    Navigator.pushReplacementNamed(
      context,
      '/admin_dashboard',
      arguments: {
        'societyName'   : widget.societyName,
        'societyAddress': widget.societyAddress,
        'placeId'       : widget.placeId,
      },
    );
  }

  // ── Simulated payment flow ─────────────────────────────────────────────────
  // ⚠️ Replace _simulatePayment() with real Razorpay integration:
  //   1. Create order on your backend → get orderId
  //   2. Open Razorpay checkout with orderId
  //   3. In the success callback call:
  //        SubscriptionService().activateSubscription(
  //          placeId          : widget.placeId,
  //          razorpayOrderId  : orderId,
  //          razorpayPaymentId: paymentId,
  //        );
  //   4. Then call _enterDashboard()

  Future<void> _simulatePayment() async {
    setState(() => _paying = true);
    try {
      // --- Razorpay integration stub ---
      // In production replace these two lines with actual Razorpay checkout.
      await Future.delayed(const Duration(seconds: 2)); // simulates network
      await SubscriptionService().activateSubscription(
        placeId          : widget.placeId,
        razorpayOrderId  : 'order_sim_${DateTime.now().millisecondsSinceEpoch}',
        razorpayPaymentId: 'pay_sim_${DateTime.now().millisecondsSinceEpoch}',
      );
      // ---------------------------------

      if (!mounted) return;
      _showSnack('🎉 Payment successful! Welcome to SocCar.', Colors.green.shade700);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) _enterDashboard();
    } catch (e) {
      if (mounted) {
        setState(() => _paying = false);
        _showSnack('Payment failed: $e', Colors.red.shade700);
      }
    }
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content        : Text(msg,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin         : const EdgeInsets.all(16),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? AppTokens.darkBg    : AppTokens.lightBg;
    final surf   = isDark ? AppTokens.darkSurface: AppTokens.lightSurface;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation      : 0,
        leading: IconButton(
          icon : Icon(Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white54 : AppTokens.lightTextSecond),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: isDark ? Colors.white38 : AppTokens.lightTextSecond,
              ),
              onPressed: () => themeNotifier.value =
                  mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
          ),
        ],
      ),
      body: _loading ? _buildLoading(isDark) : _buildBody(isDark, surf),
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Widget _buildLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _gold, strokeWidth: 2.5),
          const SizedBox(height: 20),
          Text(
            'Checking subscription…',
            style: TextStyle(
              color   : isDark ? Colors.white54 : AppTokens.lightTextSecond,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ── Main body ─────────────────────────────────────────────────────────────

  Widget _buildBody(bool isDark, Color surf) {
    if (_errorMsg != null) return _buildError(isDark);
    if (_info == null)     return _buildLoading(isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(
        children: [
          // Society header
          _buildSocietyHeader(isDark),
          const SizedBox(height: 28),

          // Main status card
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child   : _buildStatusCard(isDark, surf),
          ),
          const SizedBox(height: 20),

          // Features list (always visible)
          _buildFeaturesList(isDark),
          const SizedBox(height: 28),

          // CTA button
          _buildCtaButton(isDark),

          // Refund note
          const SizedBox(height: 16),
          Text(
            '30-day 50% refund policy  ·  Cancel anytime\n'
            'Secure payment via Razorpay',
            textAlign: TextAlign.center,
            style: TextStyle(
              color   : isDark ? Colors.white24 : AppTokens.lightTextSecond.withOpacity(0.5),
              fontSize: 11,
              height  : 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── Society header ────────────────────────────────────────────────────────

  Widget _buildSocietyHeader(bool isDark) {
    return Column(
      children: [
        Container(
          width : 64, height: 64,
          decoration: BoxDecoration(
            color       : _gold.withOpacity(0.12),
            shape       : BoxShape.circle,
            border      : Border.all(color: _gold.withOpacity(0.4), width: 2),
          ),
          child: const Icon(Icons.admin_panel_settings_rounded, color: _gold, size: 30),
        ),
        const SizedBox(height: 14),
        Text(
          widget.societyName,
          style: TextStyle(
            color     : isDark ? Colors.white : AppTokens.lightTextPrimary,
            fontSize  : 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          widget.societyAddress,
          style: TextStyle(
            color   : isDark ? Colors.white38 : AppTokens.lightTextSecond,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
          maxLines : 2,
          overflow : TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Status card ───────────────────────────────────────────────────────────

  Widget _buildStatusCard(bool isDark, Color surf) {
    final info = _info!;

    // ACTIVE
    if (info.isActive) {
      return _StatusCard(
        key        : const ValueKey('active'),
        isDark     : isDark,
        borderColor: Colors.greenAccent,
        icon       : Icons.verified_rounded,
        iconColor  : Colors.greenAccent,
        title      : '✅  Subscription Active',
        body       : 'Your annual plan is active. Full access to the Admin Dashboard.',
        badge      : info.expiresAt != null
            ? 'Renews: ${_fmtDate(info.expiresAt!)}'
            : null,
        badgeColor : Colors.greenAccent,
      );
    }

    // TRIAL
    if (info.isTrial) {
      final days = info.trialDaysLeft;
      return _StatusCard(
        key        : const ValueKey('trial'),
        isDark     : isDark,
        borderColor: _gold,
        icon       : Icons.hourglass_top_rounded,
        iconColor  : _gold,
        title      : '🆓  Free Trial — $days day${days == 1 ? '' : 's'} left',
        body       : 'You are on a 7-day free trial. Upgrade to continue access after '
                     '${_fmtDate(info.trialEndsAt)}.',
        badge      : 'Ends ${_fmtDate(info.trialEndsAt)}',
        badgeColor : _gold,
      );
    }

    // EXPIRED
    if (info.isExpired) {
      return _StatusCard(
        key        : const ValueKey('expired'),
        isDark     : isDark,
        borderColor: Colors.redAccent,
        icon       : Icons.lock_rounded,
        iconColor  : Colors.redAccent,
        title      : '🔒  Access Expired',
        body       : 'Your trial or subscription has ended. Subscribe for ₹1,000/year to restore full access.',
        badge      : 'Expired',
        badgeColor : Colors.redAccent,
      );
    }

    // REFUNDED
    return _StatusCard(
      key        : const ValueKey('refunded'),
      isDark     : isDark,
      borderColor: Colors.orangeAccent,
      icon       : Icons.money_off_rounded,
      iconColor  : Colors.orangeAccent,
      title      : '↩️  Refund Processed',
      body       : 'Your subscription was refunded. Subscribe again to re-activate access.',
      badge      : 'Refunded',
      badgeColor : Colors.orangeAccent,
    );
  }

  // ── Features list ─────────────────────────────────────────────────────────

  Widget _buildFeaturesList(bool isDark) {
    const features = [
      ('Unlimited Guard & Resident profiles', Icons.people_rounded),
      ('Real-time gate activity logs', Icons.history_rounded),
      ('ANPR camera integration', Icons.videocam_rounded),
      ('Delivery & visitor approval flow', Icons.local_shipping_rounded),
      ('Vehicle verification system', Icons.directions_car_rounded),
      ('Dark & light mode, full theme support', Icons.palette_rounded),
    ];

    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;
    final card   = isDark ? AppTokens.darkSurface: AppTokens.lightSurface;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color       : card,
        borderRadius: BorderRadius.circular(18),
        border      : Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT\'S INCLUDED',
            style: TextStyle(
              color        : isDark ? Colors.white38 : AppTokens.lightTextSecond,
              fontSize     : 10,
              fontWeight   : FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color       : _gold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(f.$2, color: _gold, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f.$1,
                    style: TextStyle(
                      color   : isDark ? Colors.white70 : AppTokens.lightTextPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 16),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ── CTA button ────────────────────────────────────────────────────────────

  Widget _buildCtaButton(bool isDark) {
    final info = _info!;

    // Active — just enter
    if (info.isActive) {
      return SizedBox(
        width : double.infinity,
        height: 58,
        child : ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          onPressed: _enterDashboard,
          icon : const Icon(Icons.dashboard_rounded, size: 22),
          label: const Text('ENTER DASHBOARD',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
        ),
      );
    }

    // Trial — continue for free
    if (info.isTrial) {
      return Column(
        children: [
          // Primary: continue trial
          SizedBox(
            width : double.infinity,
            height: 58,
            child : ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: _enterDashboard,
              icon : const Icon(Icons.arrow_forward_rounded, size: 22),
              label: const Text('CONTINUE FREE TRIAL',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary: pay now
          SizedBox(
            width : double.infinity,
            height: 52,
            child : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withOpacity(0.5), width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _paying ? null : _simulatePayment,
              icon : _paying
                  ? SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: _gold, strokeWidth: 2))
                  : const Icon(Icons.payment_rounded, size: 20),
              label: Text(
                _paying ? 'Processing…' : 'UPGRADE NOW — ₹1,000/year',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
        ],
      );
    }

    // Expired / Refunded — payment wall
    return SizedBox(
      width : double.infinity,
      height: 58,
      child : ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 6,
          shadowColor: _gold.withOpacity(0.4),
        ),
        onPressed: _paying ? null : _simulatePayment,
        icon: _paying
            ? const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
            : const Icon(Icons.payment_rounded, size: 22),
        label: Text(
          _paying ? 'Processing Payment…' : 'SUBSCRIBE — ₹1,000 / YEAR',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.8),
        ),
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color  : isDark ? Colors.white60 : AppTokens.lightTextSecond,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadSubscription,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon : const Icon(Icons.refresh_rounded),
              label: const Text('RETRY', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Date formatter ─────────────────────────────────────────────────────────

  static String _fmtDate(DateTime dt) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${m[dt.month]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatusCard — reusable card for the subscription state display
// ─────────────────────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final bool    isDark;
  final Color   borderColor;
  final IconData icon;
  final Color   iconColor;
  final String  title;
  final String  body;
  final String? badge;
  final Color?  badgeColor;

  const _StatusCard({
    super.key,
    required this.isDark,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppTokens.darkSurface : AppTokens.lightSurface;

    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color       : bg,
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: borderColor.withOpacity(0.5), width: 1.5),
        boxShadow   : [
          BoxShadow(
            color    : borderColor.withOpacity(0.12),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color : iconColor.withOpacity(0.12),
                  shape : BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color     : isDark ? Colors.white : AppTokens.lightTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize  : 15,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color       : (badgeColor ?? Colors.white).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: (badgeColor ?? Colors.white).withOpacity(0.35)),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color    : badgeColor ?? Colors.white,
                            fontSize : 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: TextStyle(
              color   : isDark ? Colors.white54 : AppTokens.lightTextSecond,
              fontSize: 13,
              height  : 1.5,
            ),
          ),
        ],
      ),
    );
  }
}