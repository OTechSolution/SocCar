// ============================================================================
// plans_screen.dart  —  Society Registration + Email OTP + Plan Selection + UPI
// ============================================================================
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/email_otp_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show AppTokens, themeNotifier;

const Color _kGold    = Color(0xFFFFB300);
const Color _kGold2   = Color(0xFFFFCA28);
const Color _kGoldDim = Color(0xFFFF8F00);

// ─────────────────────────────────────────────────────────────────────────────
// 🔧 CONFIGURE YOUR UPI DETAILS HERE
// ─────────────────────────────────────────────────────────────────────────────
const String _kUpiId      = 'YOUR_UPI_ID@upi';   // ← replace with your UPI ID
const String _kPayeeName  = 'SocCar';          // ← your name / business name
const int    _kAmount     = 1000;                 // ← amount in ₹
// ─────────────────────────────────────────────────────────────────────────────

/// Builds the UPI deep-link string that encodes into the QR code.
/// Format follows the BHIM / UPI URI specification.
String _upiLink(String societyId) =>
    'upi://pay?pa=$_kUpiId'
        '&pn=${Uri.encodeComponent(_kPayeeName)}'
        '&am=$_kAmount.00'
        '&cu=INR'
        '&tn=${Uri.encodeComponent('SocCar Annual Plan - $societyId')}';

// ─────────────────────────────────────────────────────────────────────────────
// PlansScreen
// ─────────────────────────────────────────────────────────────────────────────
class PlansScreen extends StatefulWidget {
  final bool autoReturn;
  const PlansScreen({super.key, this.autoReturn = true});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _heroCtrl;
  late Animation<double>   _heroFade;
  late Animation<Offset>   _heroSlide;

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _heroFade  = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end  : Offset.zero,
    ).animate(CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg   = isDark ? const Color(0xFF080B18) : const Color(0xFFF4F6F9);
    final Color surf = isDark ? AppTokens.darkSurface    : AppTokens.lightSurface;
    final Color bd   = isDark ? AppTokens.darkBorder     : AppTokens.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation      : 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white60 : AppTokens.lightTextSecond),
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
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [

            // ── Full-bleed gradient hero ────────────────────────────────
            _HeroSection(
              isDark   : isDark,
              fadeAnim : _heroFade,
              slideAnim: _heroSlide,
            ),

            LayoutBuilder(
              builder: (context, constraints) {
                final double maxW = constraints.maxWidth;
                final double hPad = maxW > 1024 ? maxW * 0.12
                    : maxW > 600  ? maxW * 0.07
                    : 20.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(hPad, 28, hPad, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      _StatsRow(isDark: isDark, surf: surf, bd: bd),
                      const SizedBox(height: 32),

                      _SectionLabel('EVERYTHING YOU GET', isDark: isDark),
                      const SizedBox(height: 14),
                      _FeatureGrid(isDark: isDark, surf: surf, bd: bd),
                      const SizedBox(height: 32),

                      _SectionLabel('HOW IT WORKS', isDark: isDark),
                      const SizedBox(height: 14),
                      _HowItWorksTimeline(isDark: isDark),
                      const SizedBox(height: 32),

                      _SectionLabel('CHOOSE YOUR PLAN', isDark: isDark),
                      const SizedBox(height: 14),
                      _PricingRow(
                        isDark: isDark,
                        surf  : surf,
                        bd    : bd,
                      ),
                      const SizedBox(height: 28),

                      _RefundBanner(isDark: isDark),
                      const SizedBox(height: 32),

                      _TestimonialCard(isDark: isDark, surf: surf, bd: bd),
                      const SizedBox(height: 32),

                      _SectionLabel('FREQUENTLY ASKED QUESTIONS', isDark: isDark),
                      const SizedBox(height: 14),
                      _FaqSection(isDark: isDark, surf: surf, bd: bd),
                      const SizedBox(height: 36),

                      // Bottom CTA (free trial) — goes through registration
                      _CtaButton(onPressed: () {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        _SocietyRegistrationSheet.show(context, isDark: isDark, isPaid: false);
                      }),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          'Free trial starts immediately — no card needed.\n'
                              'Annual plan requires a one-time UPI payment of ₹$_kAmount.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color  : isDark ? Colors.white24 : Colors.grey.shade400,
                              fontSize: 11,
                              height : 1.7),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeroSection
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final bool              isDark;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  const _HeroSection({
    required this.isDark,
    required this.fadeAnim,
    required this.slideAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width  : double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 110, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin : Alignment.topCenter,
          end   : Alignment.bottomCenter,
          colors: isDark
              ? [
            const Color(0xFF1A1200),
            const Color(0xFF100D00),
            const Color(0xFF080B18),
          ]
              : [
            const Color(0xFFFFF8E1),
            const Color(0xFFFFF3CD),
            const Color(0xFFF4F6F9),
          ],
        ),
      ),
      child: FadeTransition(
        opacity : fadeAnim,
        child   : SlideTransition(
          position: slideAnim,
          child   : Column(
            children: [
              _ShieldBadge(isDark: isDark),
              const SizedBox(height: 20),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [_kGold2, _kGold, _kGoldDim],
                ).createShader(bounds),
                child: const Text(
                  'SocCar OS',
                  style: TextStyle(
                    color        : Colors.white,
                    fontSize     : 34,
                    fontWeight   : FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Society Gate Management System',
                style: TextStyle(
                  color        : isDark ? Colors.white54 : AppTokens.lightTextSecond,
                  fontSize     : 13.5,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing   : 8,
                runSpacing: 8,
                alignment : WrapAlignment.center,
                children  : [
                  _Pill('🔒 Secure',       _kGold),
                  _Pill('⚡ Real-time',    Colors.cyanAccent),
                  _Pill('📱 Mobile-first', Colors.greenAccent),
                  _Pill('🏠 India-built',  Colors.orangeAccent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShieldBadge extends StatefulWidget {
  final bool isDark;
  const _ShieldBadge({required this.isDark});
  @override
  State<_ShieldBadge> createState() => _ShieldBadgeState();
}

class _ShieldBadgeState extends State<_ShieldBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width : 110, height: 110,
            decoration: BoxDecoration(
              shape : BoxShape.circle,
              border: Border.all(color: _kGold.withOpacity(0.18), width: 12),
            ),
          ),
          Container(
            width : 90, height: 90,
            decoration: BoxDecoration(
              shape   : BoxShape.circle,
              border  : Border.all(color: _kGold.withOpacity(0.35), width: 2),
              gradient: RadialGradient(colors: [
                _kGold.withOpacity(0.18),
                _kGold.withOpacity(0.04),
              ]),
            ),
          ),
          const Icon(Icons.shield_rounded, color: _kGold, size: 44),
        ],
      ),
    );
  }
}

Widget _Pill(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color       : color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(20),
      border      : Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(label,
        style: TextStyle(
            color     : color,
            fontSize  : 11,
            fontWeight: FontWeight.bold)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsRow
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final bool  isDark;
  final Color surf;
  final Color bd;
  const _StatsRow({required this.isDark, required this.surf, required this.bd});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('500+',  'Societies'),
      ('10k+',  'Daily Scans'),
      ('99.9%', 'Uptime'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient    : LinearGradient(colors: [
          _kGold.withOpacity(0.08),
          _kGold.withOpacity(0.04),
        ]),
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: _kGold.withOpacity(0.2)),
      ),
      child: Row(
        children: stats.asMap().entries.map((e) {
          final idx  = e.key;
          final stat = e.value;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(stat.$1,
                          style: const TextStyle(
                            color        : _kGold,
                            fontSize     : 26,
                            fontWeight   : FontWeight.w900,
                            letterSpacing: 0.5,
                          )),
                      const SizedBox(height: 2),
                      Text(stat.$2,
                          style: TextStyle(
                            color  : isDark ? Colors.white38 : AppTokens.lightTextSecond,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
                if (idx < stats.length - 1)
                  Container(width: 1, height: 36, color: _kGold.withOpacity(0.2)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionLabel
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  final bool   isDark;
  const _SectionLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width : 3,
          height: 16,
          decoration: BoxDecoration(
            color       : _kGold,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: TextStyle(
              color        : isDark ? Colors.white60 : AppTokens.lightTextSecond,
              fontSize     : 10,
              fontWeight   : FontWeight.w900,
              letterSpacing: 1.4,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeatureGrid
// ─────────────────────────────────────────────────────────────────────────────
const _kFeatures = [
  (Icons.videocam_rounded,             'ANPR Camera',       'Auto number plate scanning via rear camera'),
  (Icons.gpp_good_rounded,             'Gate Approvals',    'Real-time resident approve/deny flow'),
  (Icons.directions_car_rounded,       'Vehicle Verify',    'Guard-verified plate database matching'),
  (Icons.history_rounded,              'Activity Logs',     'Full timestamped entry & exit history'),
  (Icons.shield_rounded,               'Guard Management',  'Multi-guard shift & duty tracking'),
  (Icons.notifications_active_rounded, 'Live Alerts',       'Instant FCM push for every event'),
  (Icons.home_rounded,                 'Resident Portal',   'Self-service flat approvals anytime'),
  (Icons.admin_panel_settings_rounded, 'Admin Panel',       'Full society control & analytics'),
];

class _FeatureGrid extends StatelessWidget {
  final bool  isDark;
  final Color surf;
  final Color bd;
  const _FeatureGrid({required this.isDark, required this.surf, required this.bd});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w       = constraints.maxWidth;
        final int    cols    = w <= 480 ? 2 : w <= 720 ? 3 : 4;
        final double spacing = w <= 480 ? 10 : 14;

        return GridView.builder(
          shrinkWrap  : true,
          physics     : const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount  : cols,
            childAspectRatio: w <= 480 ? 1.1 : w <= 720 ? 1.2 : 1.35,
            crossAxisSpacing: spacing,
            mainAxisSpacing : spacing,
          ),
          itemCount  : _kFeatures.length,
          itemBuilder: (_, i) {
            final f            = _kFeatures[i];
            final double iconSz= w <= 480 ? 18 : w <= 720 ? 20 : 22;
            final double titSz = w <= 480 ? 11.5 : w <= 720 ? 12.5 : 13;
            final double subSz = w <= 480 ? 10   : w <= 720 ? 11   : 11.5;
            final double ipad  = w <= 480 ? 8    : w <= 720 ? 10   : 11;
            final double cpad  = w <= 480 ? 12   : w <= 720 ? 14   : 18;

            return Container(
              padding: EdgeInsets.all(cpad),
              decoration: BoxDecoration(
                color       : surf,
                borderRadius: BorderRadius.circular(16),
                border      : Border.all(color: bd),
                boxShadow: [
                  BoxShadow(
                    color     : isDark
                        ? Colors.black.withOpacity(0.2)
                        : Colors.blueGrey.withOpacity(0.06),
                    blurRadius: 10,
                    offset    : const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding   : EdgeInsets.all(ipad),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        _kGold.withOpacity(0.18),
                        _kGold.withOpacity(0.06),
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(10),
                      border      : Border.all(color: _kGold.withOpacity(0.2)),
                    ),
                    child: Icon(f.$1, color: _kGold, size: iconSz),
                  ),
                  SizedBox(height: w <= 480 ? 8 : 12),
                  Text(f.$2,
                      style: TextStyle(
                        color     : isDark ? Colors.white : AppTokens.lightTextPrimary,
                        fontSize  : titSz,
                        fontWeight: FontWeight.bold,
                        height    : 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: w <= 480 ? 3 : 5),
                  Flexible(
                    child: Text(f.$3,
                        style: TextStyle(
                          color  : isDark ? Colors.white38 : AppTokens.lightTextSecond,
                          fontSize: subSz,
                          height : 1.45,
                        ),
                        maxLines: w <= 480 ? 2 : 3,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HowItWorksTimeline
// ─────────────────────────────────────────────────────────────────────────────
const _kSteps = [
  (Icons.person_add_rounded, 'Register Your Society',
  'Search for your society or apartment by name using the built-in Google Places search. '
      'Pick the correct listing and your society is registered in SocCar OS instantly.'),
  (Icons.badge_rounded, 'Add Guards & Residents',
  'From the Admin Dashboard, create guard profiles with unique IDs and access codes. '
      'Add resident flat records so every flat can receive real-time gate approvals.'),
  (Icons.videocam_rounded, 'Configure the Gate Camera',
  'Mount any Android device at the gate entrance. Enable ANPR mode — the camera '
      'reads incoming number plates and cross-references your vehicle registry automatically.'),
  (Icons.check_circle_rounded, 'Go Live',
  'Your society is now fully operational. Guards log entries, residents approve deliveries '
      'from their phones, and admins see everything in the live dashboard.'),
];

class _HowItWorksTimeline extends StatelessWidget {
  final bool isDark;
  const _HowItWorksTimeline({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _kSteps.asMap().entries.map((entry) {
        final idx    = entry.key;
        final step   = entry.value;
        final isLast = idx == _kSteps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width : 38, height: 38,
                  decoration: const BoxDecoration(
                    shape   : BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_kGold2, _kGoldDim],
                      begin : Alignment.topLeft,
                      end   : Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color     : Color(0x59FFB300),
                        blurRadius: 10,
                        offset    : Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(step.$1, color: Colors.black, size: 18),
                  ),
                ),
                if (!isLast)
                  Container(
                    width : 2,
                    height: 52,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin : Alignment.topCenter,
                        end   : Alignment.bottomCenter,
                        colors: [
                          _kGold.withOpacity(0.5),
                          _kGold.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color       : _kGold.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('Step ${idx + 1}',
                            style: const TextStyle(
                                color    : _kGold,
                                fontSize : 9,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(step.$2,
                            style: TextStyle(
                              color     : isDark ? Colors.white : AppTokens.lightTextPrimary,
                              fontSize  : 13,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(step.$3,
                        style: TextStyle(
                          color   : isDark ? Colors.white54 : AppTokens.lightTextSecond,
                          fontSize: 12,
                          height  : 1.55,
                        )),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _PricingRow  — Free Trial card + Annual Plan card
// Both plan buttons go through _SocietyRegistrationSheet first
// ─────────────────────────────────────────────────────────────────────────────
class _PricingRow extends StatelessWidget {
  final bool  isDark;
  final Color surf;
  final Color bd;

  const _PricingRow({
    required this.isDark,
    required this.surf,
    required this.bd,
  });

  void _openRegistration(BuildContext context, {required bool isPaid}) {
    _SocietyRegistrationSheet.show(
      context,
      isDark: isDark,
      isPaid: isPaid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Free Trial card ───────────────────────────────────────────────
        _PlanCard(
          isDark       : isDark,
          surf         : surf,
          bd           : bd,
          badge        : 'FREE TRIAL',
          badgeColor   : Colors.greenAccent,
          title        : '7-Day Trial',
          price        : '₹0',
          priceSub     : 'No credit card',
          isHighlighted: false,
          features     : const [
            'Full Admin Dashboard access',
            'Unlimited guards & residents',
            'Real-time gate logs',
            'ANPR camera scanning',
            'Delivery & visitor approvals',
            'Push notification alerts',
          ],
          actionButton: _PlanActionButton(
            label    : 'Start Free Trial',
            icon     : Icons.play_arrow_rounded,
            color    : Colors.greenAccent,
            onPressed: () => _openRegistration(context, isPaid: false),
          ),
        ),
        const SizedBox(height: 14),
        // ── Annual Plan card ──────────────────────────────────────────────
        _PlanCard(
          isDark       : isDark,
          surf         : surf,
          bd           : bd,
          badge        : '★  BEST VALUE',
          badgeColor   : _kGold,
          title        : 'Annual Plan',
          price        : '₹1,000',
          priceSub     : '/year  ·  ≈ ₹83/mo',
          isHighlighted: true,
          features     : const [
            'Everything in Free Trial',
            'Unlimited 365-day access',
            'Priority email support',
            'Renewal reminder before expiry',
            '30-day 50% refund policy',
            'Future feature updates free',
          ],
          actionButton: _PlanActionButton(
            label    : 'Pay ₹1,000  →  Unlock Now',
            icon     : Icons.qr_code_rounded,
            color    : _kGold,
            onPressed: () => _openRegistration(context, isPaid: true),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlanCard
// ─────────────────────────────────────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final bool         isDark;
  final Color        surf;
  final Color        bd;
  final String       badge;
  final Color        badgeColor;
  final String       title;
  final String       price;
  final String       priceSub;
  final bool         isHighlighted;
  final List<String> features;
  final Widget       actionButton;

  const _PlanCard({
    required this.isDark,
    required this.surf,
    required this.bd,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.price,
    required this.priceSub,
    required this.isHighlighted,
    required this.features,
    required this.actionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: isHighlighted
            ? LinearGradient(
          begin : Alignment.topLeft,
          end   : Alignment.bottomRight,
          colors: [_kGold.withOpacity(0.07), _kGold.withOpacity(0.02)],
        )
            : null,
        color       : isHighlighted ? null : surf,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isHighlighted ? _kGold : bd,
            width: isHighlighted ? 2      : 1),
        boxShadow: isHighlighted
            ? [BoxShadow(color: _kGold.withOpacity(0.15), blurRadius: 28, offset: const Offset(0, 8))]
            : [BoxShadow(
          color     : isDark ? Colors.black.withOpacity(0.15) : Colors.blueGrey.withOpacity(0.07),
          blurRadius: 14,
          offset    : const Offset(0, 4),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge row
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color       : badgeColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(7),
                border      : Border.all(color: badgeColor.withOpacity(0.35)),
              ),
              child: Text(badge,
                  style: TextStyle(
                      color        : badgeColor,
                      fontSize     : 9.5,
                      fontWeight   : FontWeight.bold,
                      letterSpacing: 0.5)),
            ),
            const Spacer(),
            if (isHighlighted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color       : _kGold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('MOST POPULAR',
                    style: TextStyle(
                        color       : _kGold,
                        fontSize    : 8,
                        fontWeight  : FontWeight.bold,
                        letterSpacing: 0.6)),
              ),
          ]),
          const SizedBox(height: 18),

          // Price
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price,
                  style: TextStyle(
                    color        : isHighlighted ? _kGold : (isDark ? Colors.white : AppTokens.lightTextPrimary),
                    fontSize     : 38,
                    fontWeight   : FontWeight.w900,
                    height       : 1,
                    letterSpacing: -1,
                  )),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(priceSub,
                    style: TextStyle(
                        color  : isDark ? Colors.white38 : AppTokens.lightTextSecond,
                        fontSize: 11,
                        height : 1.4)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(title,
              style: TextStyle(
                  color    : isDark ? Colors.white70 : AppTokens.lightTextPrimary,
                  fontSize : 15,
                  fontWeight: FontWeight.bold)),

          const SizedBox(height: 18),
          Divider(
              color: isHighlighted ? _kGold.withOpacity(0.2) : (isDark ? Colors.white10 : Colors.grey.shade200),
              height: 1),
          const SizedBox(height: 16),

          // Features
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin : const EdgeInsets.only(top: 1),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color : badgeColor.withOpacity(0.14),
                    shape : BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: badgeColor, size: 11),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(f,
                      style: TextStyle(
                          color  : isDark ? Colors.white70 : AppTokens.lightTextPrimary,
                          fontSize: 13,
                          height : 1.45)),
                ),
              ],
            ),
          )),

          const SizedBox(height: 20),
          // Action button embedded in card
          actionButton,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlanActionButton — reusable full-width button for each plan card
// ─────────────────────────────────────────────────────────────────────────────
class _PlanActionButton extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        color;
  final VoidCallback onPressed;
  const _PlanActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width : double.infinity,
      height: 52,
      child : ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation      : 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon : Icon(icon, size: 20, color: Colors.black),
        label: Text(label,
            style: const TextStyle(
                fontWeight   : FontWeight.w800,
                fontSize     : 13,
                letterSpacing: 0.5,
                color        : Colors.black)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PaymentSheet  — modal bottom sheet with UPI QR + UTR verification
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentSheet extends StatefulWidget {
  final bool   isDark;
  final String societyId;
  final String societyName;

  const _PaymentSheet({
    required this.isDark,
    required this.societyId,
    required this.societyName,
  });

  static Future<void> show(
      BuildContext context, {
        required bool   isDark,
        required String societyId,
        required String societyName,
      }) {
    return showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      backgroundColor   : Colors.transparent,
      builder           : (_) => _PaymentSheet(
        isDark     : isDark,
        societyId  : societyId,
        societyName: societyName,
      ),
    );
  }

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final TextEditingController _utrCtrl = TextEditingController();
  bool   _submitting  = false;
  bool   _submitted   = false;
  String? _errorMsg;

  @override
  void dispose() {
    _utrCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPayment() async {
    final utr = _utrCtrl.text.trim();
    if (utr.length < 6) {
      setState(() => _errorMsg = 'Please enter a valid UTR / Transaction ID.');
      return;
    }
    setState(() { _submitting = true; _errorMsg = null; });

    try {
      // Write payment proof to Firestore.
      // Admin dashboard checks planStatus == 'active' to allow entry.
      // You manually verify UTR in your bank app and then set planStatus = 'active'
      // in Firestore console, OR automate via Razorpay webhook.
      await FirebaseFirestore.instance
          .collection('societies')
          .doc(widget.societyId)
          .set({
        'societyName'        : widget.societyName,
        'planType'           : 'ANNUAL',
        'status'             : 'ACTIVE',
        'paidAt'             : FieldValue.serverTimestamp(),
        'expiresAt'          : Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365))),
        'razorpayOrderId'    : 'upi_manual_$utr',
        'razorpayPaymentId'  : utr,
        'refundAmount'       : null,
        'refundedAt'         : null,
      }, SetOptions(merge: true));

      if (mounted) setState(() { _submitting = false; _submitted = true; });
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _errorMsg = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg    = widget.isDark ? const Color(0xFF0F1120) : Colors.white;
    final surf  = widget.isDark ? const Color(0xFF1A1D2E) : const Color(0xFFF4F6F9);
    final txt   = widget.isDark ? Colors.white            : const Color(0xFF111827);
    final sub   = widget.isDark ? Colors.white54          : const Color(0xFF6B7280);
    final upiLink = _upiLink(widget.societyId);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize    : 0.6,
      maxChildSize    : 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color       : bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          physics   : const BouncingScrollPhysics(),
          child     : Column(
            children: [

              // ── Drag handle ──────────────────────────────────────────
              const SizedBox(height: 12),
              Container(
                width : 40, height: 4,
                decoration: BoxDecoration(
                  color       : Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              if (_submitted) ...[
                // ── Success state ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Container(
                        width : 90, height: 90,
                        decoration: BoxDecoration(
                          color : Colors.greenAccent.withOpacity(0.12),
                          shape : BoxShape.circle,
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.4), width: 2),
                        ),
                        child: const Icon(Icons.check_circle_rounded,
                            color: Colors.greenAccent, size: 44),
                      ),
                      const SizedBox(height: 24),
                      Text('Payment Submitted!',
                          style: TextStyle(
                              color     : txt,
                              fontSize  : 22,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(
                        'Your UTR has been recorded. We\'ll verify your payment '
                            'and activate your Annual Plan within a few minutes.\n\n'
                            'You\'ll be able to access the Admin Dashboard once '
                            'payment is confirmed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: sub, fontSize: 13, height: 1.6),
                      ),
                      const SizedBox(height: 28),
                      // Pending-access banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color       : _kGold.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border      : Border.all(color: _kGold.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.access_time_rounded, color: _kGold, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Verification usually takes 2–10 minutes during business hours.',
                              style: TextStyle(color: _kGold, fontSize: 12, height: 1.5),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width : double.infinity,
                        height: 52,
                        child : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('CLOSE',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ── Payment UI ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Header
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color       : _kGold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border      : Border.all(color: _kGold.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.qr_code_rounded, color: _kGold, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pay via UPI',
                                  style: TextStyle(
                                      color     : txt,
                                      fontWeight: FontWeight.bold,
                                      fontSize  : 18)),
                              Text('Annual Plan · ₹$_kAmount',
                                  style: TextStyle(color: sub, fontSize: 12)),
                            ],
                          ),
                        ),
                        // Close
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Icon(Icons.close_rounded, color: sub, size: 22),
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // QR code card
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color       : Colors.white,  // always white for QR readability
                            borderRadius: BorderRadius.circular(22),
                            border      : Border.all(color: _kGold.withOpacity(0.35), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color     : _kGold.withOpacity(0.18),
                                blurRadius: 24,
                                offset    : const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Society name above QR
                              Text(
                                widget.societyName,
                                style: const TextStyle(
                                  color     : Color(0xFF111827),
                                  fontWeight: FontWeight.bold,
                                  fontSize  : 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Annual Plan — ₹1,000',
                                style: TextStyle(
                                    color   : Color(0xFF6B7280),
                                    fontSize: 11),
                              ),
                              const SizedBox(height: 16),

                              // ── The actual QR code ──────────────────
                              QrImageView(
                                data           : upiLink,
                                version        : QrVersions.auto,
                                size           : 200,
                                backgroundColor: Colors.white,
                                // Embedded logo in centre of QR
                                embeddedImage  : const AssetImage('assets/images/logo.png'),
                                embeddedImageStyle: const QrEmbeddedImageStyle(
                                  size: Size(36, 36),
                                ),
                                errorStateBuilder: (_, __) => const SizedBox(
                                  width : 200,
                                  height: 200,
                                  child : Center(
                                    child: Text('QR error — check UPI ID',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Amount badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color       : const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(10),
                                  border      : Border.all(color: _kGold.withOpacity(0.35)),
                                ),
                                child: const Text(
                                  '₹1,000',
                                  style: TextStyle(
                                    color     : _kGoldDim,
                                    fontSize  : 22,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // UPI ID + copy
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(const ClipboardData(text: _kUpiId));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content : Text('UPI ID copied!'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color       : const Color(0xFFF4F6F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border      : Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.account_balance_wallet_rounded,
                                          size: 14, color: Color(0xFF6B7280)),
                                      const SizedBox(width: 6),
                                      Text(_kUpiId,
                                          style: const TextStyle(
                                              color     : Color(0xFF374151),
                                              fontWeight: FontWeight.w600,
                                              fontSize  : 12,
                                              fontFamily: 'monospace')),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.copy_rounded,
                                          size: 12, color: Color(0xFF9CA3AF)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tap UPI ID to copy · Scan with any UPI app',
                                style: TextStyle(
                                    color  : Color(0xFF9CA3AF),
                                    fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Steps
                      _PayStep(n: '1', text: 'Open any UPI app  (GPay, PhonePe, Paytm, BHIM…)'),
                      const SizedBox(height: 8),
                      _PayStep(n: '2', text: 'Scan the QR above  OR  enter UPI ID manually'),
                      const SizedBox(height: 8),
                      _PayStep(n: '3', text: 'Pay exactly ₹$_kAmount and note the UTR / Ref number'),
                      const SizedBox(height: 8),
                      _PayStep(n: '4', text: 'Enter the UTR below and tap Confirm'),

                      const SizedBox(height: 24),

                      // UTR input
                      Text('Transaction UTR / Reference ID',
                          style: TextStyle(
                              color    : txt,
                              fontWeight: FontWeight.w600,
                              fontSize : 13)),
                      const SizedBox(height: 8),
                      TextField(
                        controller : _utrCtrl,
                        style      : TextStyle(color: txt, fontSize: 14),
                        decoration : InputDecoration(
                          hintText   : 'e.g.  425612345678',
                          hintStyle  : TextStyle(color: sub.withOpacity(0.6)),
                          filled     : true,
                          fillColor  : surf,
                          border     : OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide  : BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide  : const BorderSide(color: _kGold, width: 1.5)),
                          prefixIcon : Icon(Icons.tag_rounded, color: sub, size: 18),
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),

                      if (_errorMsg != null) ...[
                        const SizedBox(height: 8),
                        Text(_errorMsg!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                      ],

                      const SizedBox(height: 20),

                      // Confirm button
                      SizedBox(
                        width : double.infinity,
                        height: 56,
                        child : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            elevation      : 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _submitting ? null : _submitPayment,
                          icon : _submitting
                              ? const SizedBox(
                              width : 18, height: 18,
                              child : CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.verified_rounded,
                              size: 20, color: Colors.black),
                          label: Text(
                            _submitting ? 'Submitting…' : 'I\'VE PAID — CONFIRM',
                            style: const TextStyle(
                                fontWeight   : FontWeight.w900,
                                fontSize     : 15,
                                letterSpacing: 0.6,
                                color        : Colors.black),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          'Your plan activates within minutes after payment is verified.',
                          style: TextStyle(color: sub, fontSize: 11),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PayStep — numbered instruction row
// ─────────────────────────────────────────────────────────────────────────────
class _PayStep extends StatelessWidget {
  final String n;
  final String text;
  const _PayStep({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width : 22, height: 22,
          decoration: BoxDecoration(
            color: _kGold.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(n,
                style: const TextStyle(
                    color    : _kGold,
                    fontSize : 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color  : isDark ? Colors.white60 : AppTokens.lightTextSecond,
                  fontSize: 12.5,
                  height : 1.5)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RefundBanner
// ─────────────────────────────────────────────────────────────────────────────
class _RefundBanner extends StatelessWidget {
  final bool isDark;
  const _RefundBanner({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient    : LinearGradient(colors: [
          Colors.greenAccent.withOpacity(0.07),
          Colors.teal.withOpacity(0.04),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border      : Border.all(color: Colors.greenAccent.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color       : Colors.greenAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.verified_user_rounded,
                color: Colors.greenAccent, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('30-Day Refund Guarantee',
                    style: TextStyle(
                        color     : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize  : 14)),
                const SizedBox(height: 6),
                Text(
                  'Not satisfied within 30 days? Email us with your transaction ID '
                      'and we\'ll refund 50% (₹500) within 5–7 business days. No questions asked.',
                  style: TextStyle(
                      color  : isDark ? Colors.white54 : AppTokens.lightTextSecond,
                      fontSize: 12,
                      height : 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TestimonialCard
// ─────────────────────────────────────────────────────────────────────────────
class _TestimonialCard extends StatelessWidget {
  final bool  isDark;
  final Color surf;
  final Color bd;
  const _TestimonialCard({required this.isDark, required this.surf, required this.bd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color       : surf,
        borderRadius: BorderRadius.circular(20),
        border      : Border.all(color: bd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('❝',
                style: TextStyle(color: _kGold, fontSize: 28, height: 1)),
            const Spacer(),
            Row(children: List.generate(5, (_) =>
            const Icon(Icons.star_rounded, color: _kGold, size: 14))),
          ]),
          const SizedBox(height: 12),
          Text(
            'SocCar OS transformed how our society manages gate access. '
                'The ANPR camera alone saves our guards 2 hours of manual logging every day.',
            style: TextStyle(
                color  : isDark ? Colors.white70 : AppTokens.lightTextPrimary,
                fontSize: 13.5,
                height : 1.6,
                fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(
              radius         : 18,
              backgroundColor: _kGold.withOpacity(0.2),
              child          : const Text('R',
                  style: TextStyle(color: _kGold, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ravi Sharma',
                    style: TextStyle(
                        color     : isDark ? Colors.white : AppTokens.lightTextPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize  : 13)),
                Text('Society Admin, Pune',
                    style: TextStyle(
                        color  : isDark ? Colors.white38 : AppTokens.lightTextSecond,
                        fontSize: 11)),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FaqSection
// ─────────────────────────────────────────────────────────────────────────────
const _kFaqs = [
  ('How do I start the free trial?',
  'Every new society registration receives a full 7-day free trial. During the trial you '
      'have complete, unrestricted access to every feature including ANPR, gate approvals, '
      'and the full Admin Dashboard. No payment information is required at signup.'),
  ('What happens when my 7-day trial ends?',
  'When the trial expires the next Admin login will be redirected to this plans page. '
      'Guards and residents are never affected. All your data is preserved and immediately '
      'accessible the moment payment is completed.'),
  ('How do I pay for the Annual Plan?',
  'Tap "Pay ₹1,000 → Unlock Now" on the Annual Plan card. A UPI QR code will appear — '
      'scan it with any UPI app (GPay, PhonePe, Paytm, BHIM). After paying, enter the '
      'UTR/reference number and tap Confirm. Your plan activates within minutes.'),
  ('Do guards or residents need to pay anything?',
  'No. The subscription is entirely an admin-level concern. Guards log in with their '
      'Guard ID and residents use their flat number — neither is ever prompted to pay.'),
  ('Is my payment information safe?',
  'Yes. Payments go directly through UPI — we never see, store, or transmit your card '
      'or bank details. The transaction happens entirely within your UPI app.'),
  ('What is the refund policy?',
  'We offer a 30-day 50% refund on the Annual Plan. Email us your society name and '
      'payment UTR within 30 days of payment. We\'ll refund ₹500 within 5–7 business days.'),
];

class _FaqSection extends StatelessWidget {
  final bool  isDark;
  final Color surf;
  final Color bd;
  const _FaqSection({required this.isDark, required this.surf, required this.bd});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _kFaqs.asMap().entries.map((e) => _FaqTile(
        isDark: isDark,
        surf  : surf,
        bd    : bd,
        index : e.key + 1,
        q     : e.value.$1,
        a     : e.value.$2,
      )).toList(),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final bool   isDark;
  final Color  surf;
  final Color  bd;
  final int    index;
  final String q;
  final String a;

  const _FaqTile({
    required this.isDark,
    required this.surf,
    required this.bd,
    required this.index,
    required this.q,
    required this.a,
  });

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  late AnimationController _ctrl;
  late Animation<double>   _expand;
  late Animation<double>   _rotate;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 260),
    );
    _expand = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _rotate = Tween<double>(begin: 0, end: 0.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color       : widget.surf,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _open ? _kGold.withOpacity(0.45) : widget.bd,
          width: _open ? 1.5 : 1,
        ),
        boxShadow: _open
            ? [BoxShadow(color: _kGold.withOpacity(0.07), blurRadius: 14, offset: const Offset(0, 4))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width : 24, height: 24,
                      margin: const EdgeInsets.only(top: 1, right: 12),
                      decoration: BoxDecoration(
                        color: _open
                            ? _kGold.withOpacity(0.15)
                            : (widget.isDark ? Colors.white10 : Colors.grey.shade100),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text('${widget.index}',
                            style: TextStyle(
                              color     : _open ? _kGold : (widget.isDark ? Colors.white38 : AppTokens.lightTextSecond),
                              fontSize  : 10,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ),
                    Expanded(
                      child: Text(widget.q,
                          style: TextStyle(
                            color     : widget.isDark ? Colors.white : AppTokens.lightTextPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize  : 13.5,
                            height    : 1.35,
                          )),
                    ),
                    const SizedBox(width: 8),
                    RotationTransition(
                      turns: _rotate,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _open ? _kGold : Colors.grey,
                        size : 22,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _expand,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
                child: Text(widget.a,
                    style: TextStyle(
                        color  : widget.isDark ? Colors.white60 : AppTokens.lightTextSecond,
                        fontSize: 12.5,
                        height : 1.65)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CtaButton — pulsing gold button (free trial CTA at bottom)
// ─────────────────────────────────────────────────────────────────────────────
class _CtaButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _CtaButton({required this.onPressed});
  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync   : this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.015)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width : double.infinity,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kGold2, _kGold, _kGoldDim],
            begin : Alignment.centerLeft,
            end   : Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color     : _kGold.withOpacity(0.45),
              blurRadius: 20,
              offset    : const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor    : Colors.transparent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: widget.onPressed,
          icon : const Icon(Icons.rocket_launch_rounded, size: 22, color: Colors.black),
          label: const Text(
            'GET STARTED FREE',
            style: TextStyle(
              fontWeight   : FontWeight.w900,
              fontSize     : 16,
              letterSpacing: 1.0,
              color        : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
// =============================================================================
// _SocietyRegistrationSheet
// =============================================================================
// Shown before ANY plan starts. Three steps:
//
//   STEP 1 — Society name
//            User types their society / apartment name.
//            A unique societyId is derived (slug of the name + 4-char suffix).
//
//   STEP 2 — Email entry
//            User types their email address.
//            We use Firebase Auth Email OTP (6-digit code, no password).
//            → FirebaseAuth.sendSignInLinkToEmail sends a sign-in link AND
//              we use signInWithEmailAndPassword with OTP via
//              FirebaseAuth.instance.signInWithEmailLink  (email link flow)
//            → Actually we use the simple OTP approach:
//              verifyBeforeUpdateEmail / createUserWithEmailAndPassword is
//              complex. Easiest FREE method: generate a 6-digit OTP ourselves,
//              store it in Firestore with a 10-min expiry, and call a
//              Cloud Function / use Firebase Extensions "Trigger Email" to
//              send it. BUT that needs a function.
//
//            ✅ Chosen approach: Firebase Auth Email Link (passwordless).
//               sendSignInLinkToEmail → user taps link in email → deep-link
//               back into app → isSignInWithEmailLink check → sign in.
//               This is 100% free, zero backend code, works in Flutter.
//
//   STEP 3 — Email verified → proceed to plan
//            After sign-in confirmed, society doc is created in Firestore
//            and we navigate to admin dashboard (trial) or payment sheet.
// =============================================================================

// ─── Helper: turn society name into a stable lowercase slug ID ───────────────
String _toSocietyId(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  // keep first 24 chars so IDs are readable
  return slug.length > 24 ? slug.substring(0, 24) : slug;
}

// ─── Deep-link URL configured in Firebase Console → Authentication →
//     Sign-in methods → Email/Password → Email link. Must also be added
//     to your AndroidManifest.xml / Info.plist as a custom URL scheme.
const String _kEmailLinkDomain = 'https://scocar-bd398.firebaseapp.com';
//                                ↑ replace with your Firebase Dynamic Link

class _SocietyRegistrationSheet extends StatefulWidget {
  final bool isDark;
  final bool isPaid; // false = trial, true = paid plan

  const _SocietyRegistrationSheet({
    required this.isDark,
    required this.isPaid,
  });

  static Future<void> show(
      BuildContext context, {
        required bool isDark,
        required bool isPaid,
      }) {
    return showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      backgroundColor   : Colors.transparent,
      builder           : (_) => _SocietyRegistrationSheet(
        isDark: isDark,
        isPaid: isPaid,
      ),
    );
  }

  @override
  State<_SocietyRegistrationSheet> createState() =>
      _SocietyRegistrationSheetState();
}

class _SocietyRegistrationSheetState
    extends State<_SocietyRegistrationSheet> {
  // ── Step controller ───────────────────────────────────────────────────────
  int _step = 1; // 1 = society name, 2 = email, 3 = link sent

  // ── Step 1 ────────────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  String  _societyId   = '';
  String  _societyName = '';

  // ── Step 2 ────────────────────────────────────────────────────────────────
  final _emailCtrl    = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes  = List.generate(6, (_) => FocusNode());
  bool    _sending    = false;
  bool    _verifying  = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes)  f.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1 → Step 2: validate society name
  // ─────────────────────────────────────────────────────────────────────────
  void _confirmSociety() {
    final name = _nameCtrl.text.trim();
    if (name.length < 3) {
      setState(() => _error = 'Please enter at least 3 characters.');
      return;
    }
    setState(() {
      _error       = null;
      _societyName = name;
      _societyId   = _toSocietyId(name);
      _step        = 2;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2: send Firebase Email Link (OTP-equivalent, 100% free)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() { _sending = true; _error = null; });
    final ok = await EmailOtpService().sendOtp(
      email: email,
      name : _societyName,
    );
    if (!mounted) return;
    if (ok) {
      setState(() { _sending = false; _step = 3; });
    } else {
      setState(() {
        _sending = false;
        _error   = 'Failed to send OTP. Check your Resend API key in Firestore.';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpControllers.map((c) => c.text).join();
    if (otp.length < 6) {
      setState(() => _error = 'Please enter all 6 digits.');
      return;
    }
    setState(() { _verifying = true; _error = null; });

    final result = await EmailOtpService().verifyOtp(
      email: _emailCtrl.text.trim(),
      otp  : otp,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() { _verifying = false; _error = result.message; });
      return;
    }

    // ✅ OTP verified — create society doc and navigate to admin
    final email      = _emailCtrl.text.trim();
    final societyId  = _societyId;
    final societyName = _societyName;
    final isPaid     = widget.isPaid;

    final docRef   = FirebaseFirestore.instance.collection('societies').doc(societyId);
    final existing = await docRef.get();

    if (!existing.exists) {
      final trialEnd = DateTime.now().add(const Duration(days: 7));
      await docRef.set({
        'societyName'    : societyName,
        'adminEmail'     : email,
        'placeId'        : societyId,
        'planType'       : 'TRIAL',
        'status'         : 'TRIAL',
        'trialStartedAt' : FieldValue.serverTimestamp(),
        'trialEndsAt'    : Timestamp.fromDate(trialEnd),
        'paidAt'         : null,
        'expiresAt'      : null,
      });
    } else {
      await docRef.update({'adminEmail': email});
    }

    if (!mounted) return;
    setState(() => _verifying = false);
    Navigator.pop(context); // close sheet
    await Navigator.pushNamed(
      context,
      '/admin',
      arguments: {'societyId': societyId, 'societyName': societyName},
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bg  = widget.isDark ? const Color(0xFF0F1120) : Colors.white;
    final txt = widget.isDark ? Colors.white            : const Color(0xFF111827);
    final sub = widget.isDark ? Colors.white54          : const Color(0xFF6B7280);
    final sf  = widget.isDark ? const Color(0xFF1A1D2E) : const Color(0xFFF4F6F9);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize    : 0.5,
      maxChildSize    : 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color       : bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          physics   : const BouncingScrollPhysics(),
          child     : Padding(
            padding: EdgeInsets.only(
              left  : 24,
              right : 24,
              top   : 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Drag handle ─────────────────────────────────────────
                Center(
                  child: Container(
                    width : 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color       : Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Step indicator ──────────────────────────────────────
                _StepIndicator(current: _step, isDark: widget.isDark),
                const SizedBox(height: 28),

                // ── Step content ────────────────────────────────────────
                AnimatedSwitcher(
                  duration : const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity : anim,
                    child   : SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.06, 0),
                        end  : Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _step == 1
                      ? _buildStep1(txt, sub, sf)
                      : _step == 2
                      ? _buildStep2(txt, sub, sf)
                      : _buildStep3(txt, sub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Local sheet helpers keep the step widgets in scope even if
  // other private widgets are moved/refactored elsewhere in file.
  Widget _StepIndicator({required int current, required bool isDark}) {
    return Row(
      children: List.generate(3, (i) {
        final n = i + 1;
        final active = n == current;
        final done = n < current;
        final col = done || active ? _kGold : Colors.grey.withOpacity(0.3);
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 4,
                  decoration: BoxDecoration(
                    color: col,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 6),
            ],
          ),
        );
      }),
    );
  }

  Widget _SheetHeader({
    required IconData icon,
    required String title,
    required String sub,
    required Color txt,
    required Color sub2,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _kGold.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGold.withOpacity(0.3)),
          ),
          child: Icon(icon, color: _kGold, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: txt,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(sub, style: TextStyle(color: sub2, fontSize: 12.5, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _SheetField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    required Color sf,
    required Color txt,
    required Color sub,
    bool autofocus = false,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textCapitalization: capitalization,
      style: TextStyle(color: txt, fontSize: 15),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: sub.withOpacity(0.5), fontSize: 14),
        prefixIcon: Icon(icon, color: sub, size: 20),
        filled: true,
        fillColor: sf,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kGold, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _SheetButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    bool loading = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
        )
            : Icon(icon, size: 20, color: Colors.black),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── STEP 1 — Society name ─────────────────────────────────────────────────
  Widget _buildStep1(Color txt, Color sub, Color sf) {
    return Column(
      key             : const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.start,
      children        : [
        _SheetHeader(
          icon : Icons.apartment_rounded,
          title: 'Your Society Name',
          sub  : 'Enter the name of your apartment or gated community.',
          txt  : txt,
          sub2 : sub,
        ),
        const SizedBox(height: 24),

        _SheetField(
          controller : _nameCtrl,
          hint       : 'e.g. Green Valley Apartments',
          icon       : Icons.search_rounded,
          isDark     : widget.isDark,
          sf         : sf,
          txt        : txt,
          sub        : sub,
          autofocus  : true,
          capitalization: TextCapitalization.words,
          onSubmitted: (_) => _confirmSociety(),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],

        const SizedBox(height: 8),
        Text(
          'Each society gets its own isolated data — guards, residents, and logs '
              'are private to your society.',
          style: TextStyle(color: sub, fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 28),

        _SheetButton(
          label    : 'Continue',
          icon     : Icons.arrow_forward_rounded,
          onPressed: _confirmSociety,
          color    : widget.isPaid ? _kGold : Colors.greenAccent,
        ),
      ],
    );
  }

  // ── STEP 2 — Email ────────────────────────────────────────────────────────
  Widget _buildStep2(Color txt, Color sub, Color sf) {
    return Column(
      key             : const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.start,
      children        : [
        _SheetHeader(
          icon : Icons.mail_outline_rounded,
          title: 'Verify Your Email',
          sub  : 'We\'ll send a 6-digit OTP code to verify your email.',
          txt  : txt,
          sub2 : sub,
        ),
        const SizedBox(height: 8),

        // Society name recap chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color       : _kGold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border      : Border.all(color: _kGold.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.apartment_rounded, color: _kGold, size: 14),
            const SizedBox(width: 6),
            Text(_societyName,
                style: const TextStyle(
                    color     : _kGold,
                    fontSize  : 12,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
        const SizedBox(height: 20),

        _SheetField(
          controller  : _emailCtrl,
          hint        : 'admin@email.com',
          icon        : Icons.alternate_email_rounded,
          isDark      : widget.isDark,
          sf          : sf,
          txt         : txt,
          sub         : sub,
          autofocus   : true,
          keyboardType: TextInputType.emailAddress,
          onSubmitted : (_) => _sendOtp(),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],

        const SizedBox(height: 10),
        // How it works mini-note
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color       : Colors.blueAccent.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border      : Border.all(color: Colors.blueAccent.withOpacity(0.2)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded,
                color: Colors.blueAccent, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'We\'ll send a 6-digit code to your email. Enter it on the next screen to verify.',
                style: TextStyle(color: sub, fontSize: 11.5, height: 1.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 28),

        Row(children: [
          // Back
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: sub,
              side           : BorderSide(color: sub.withOpacity(0.3)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onPressed: () => setState(() { _step = 1; _error = null; }),
            icon : const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SheetButton(
              label    : _sending ? 'Sending…' : 'Send OTP Code',
              icon     : _sending ? Icons.hourglass_bottom_rounded : Icons.send_rounded,
              onPressed: _sending ? () {} : _sendOtp,
              color    : widget.isPaid ? _kGold : Colors.greenAccent,
              loading  : _sending,
            ),
          ),
        ]),
      ],
    );
  }

  // ── STEP 3 — Email sent confirmation ─────────────────────────────────────
  Widget _buildStep3(Color txt, Color sub) {
    return Column(
      key: const ValueKey(3),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SheetHeader(
          icon : Icons.verified_rounded,
          title: 'Enter OTP Code',
          sub  : 'A 6-digit code was sent to ${_emailCtrl.text.trim()}',
          txt  : txt,
          sub2 : sub,
        ),
        const SizedBox(height: 28),

        // OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (i) => SizedBox(
            width: 44, height: 54,
            child: TextField(
              controller     : _otpControllers[i],
              focusNode      : _otpFocusNodes[i],
              textAlign      : TextAlign.center,
              keyboardType   : TextInputType.number,
              maxLength      : 1,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style          : TextStyle(
                fontSize  : 22,
                fontWeight: FontWeight.bold,
                color     : txt,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled     : true,
                fillColor  : widget.isDark
                    ? const Color(0xFF1A1D2E) : const Color(0xFFF4F6F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide  : BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide  : const BorderSide(color: _kGold, width: 2),
                ),
              ),
              onChanged: (val) {
                if (val.isNotEmpty && i < 5) {
                  _otpFocusNodes[i + 1].requestFocus();
                }
                if (val.isEmpty && i > 0) {
                  _otpFocusNodes[i - 1].requestFocus();
                }
                // Auto-verify when all 6 digits entered
                final otp = _otpControllers.map((c) => c.text).join();
                if (otp.length == 6) _verifyOtp();
              },
            ),
          )),
        ),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ],

        const SizedBox(height: 28),

        _SheetButton(
          label    : _verifying ? 'Verifying…' : 'Verify OTP',
          icon     : _verifying
              ? Icons.hourglass_bottom_rounded
              : Icons.check_circle_rounded,
          onPressed: _verifying ? () {} : _verifyOtp,
          color    : widget.isPaid ? _kGold : Colors.greenAccent,
          loading  : _verifying,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() { _step = 2; _error = null; }),
            icon : Icon(Icons.refresh_rounded, color: sub, size: 16),
            label: Text('Resend or change email',
                style: TextStyle(color: sub, fontSize: 12)),
          ),
        ),
      ],
    );
  }
}


class _CredentialGenerator {
  static const String _chars =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#\$%';

  /// Generate a memorable admin ID: ADM-<SocietyPrefix>-<4 random uppercase>
  static String generateAdminId(String societyName) {
    final prefix = societyName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .substring(0, math.min(5, societyName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length));
    final rand  = math.Random.secure();
    final suffix = List.generate(4, (_) =>
    'ABCDEFGHJKLMNPQRSTUVWXYZ'[rand.nextInt(24)]).join();
    return 'ADM-$prefix-$suffix';
  }

  /// Generate a strong 12-character access code
  static String generateAccessCode() {
    final rand = math.Random.secure();
    return List.generate(12, (_) => _chars[rand.nextInt(_chars.length)]).join();
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Global state for pending email sign-in (in-memory; use shared_preferences
// in production to survive app restarts)
