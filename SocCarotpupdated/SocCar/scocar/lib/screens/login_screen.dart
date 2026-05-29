import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart' show themeNotifier, AppTokens;
import 'log_movement_screen.dart' show activeGuardName;
import 'society_search_field.dart';
import 'plans_screen.dart';          // ← Plans & pricing screen
import 'payment_gate_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Role enum
// ─────────────────────────────────────────────────────────────────────────────
enum _Role { guard, resident, admin }

extension _RoleExt on _Role {
  String get label {
    switch (this) {
      case _Role.guard:    return 'Guard';
      case _Role.resident: return 'Resident';
      case _Role.admin:    return 'Admin';
    }
  }

  IconData get icon {
    switch (this) {
      case _Role.guard:    return Icons.shield_rounded;
      case _Role.resident: return Icons.home_rounded;
      case _Role.admin:    return Icons.admin_panel_settings_rounded;
    }
  }

  String get subtitle {
    switch (this) {
      case _Role.guard:    return 'Gate & delivery management';
      case _Role.resident: return 'Visitor approvals & vehicle logs';
      case _Role.admin:    return 'Society administration panel';
    }
  }

  // ALL roles now use the same cyan/blue accent — consistent design
  Color get accentColor => AppTokens.cyanAction;
}

const String _kAdminId   = 'ADMIN';
const String _kAdminCode = 'SadminocCar@';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  // ── NO role selected by default ──────────────────────────────────────────
  _Role? _role;
  bool   _isLoading  = false;
  bool   _loginLock  = false;
  bool   _obscureCode = true;

  PlaceSuggestion? _selectedSociety;

  final _idCtrl    = TextEditingController();
  final _codeCtrl  = TextEditingController();
  final _idFocus   = FocusNode();
  final _codeFocus = FocusNode();

  late AnimationController _slideCtrl;
  late Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end  : Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _idCtrl.dispose();
    _codeCtrl.dispose();
    _idFocus.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _selectRole(_Role r) {
    if (_isLoading) return;
    // Admin tapped — show Plans/Pricing screen first.
    // Only reveal the admin login form if the user taps "GET STARTED"
    // (Navigator.pop returns true). If they press back it returns null/false
    // and the admin chip stays unselected.
    if (r == _Role.admin && _role != _Role.admin) {
      _showPlansScreen();
      return;
    }
    _applyRoleSwitch(r);
  }

  void _applyRoleSwitch(_Role r) {
    setState(() {
      _role            = r;
      _idCtrl.clear();
      _codeCtrl.clear();
      _obscureCode     = true;
      _selectedSociety = null;
    });
    _slideCtrl..reset()..forward();
    FocusScope.of(context).unfocus();
  }

  Future<void> _showPlansScreen() async {
    // Push PlansScreen — it returns true when user taps "GET STARTED FREE"
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const PlansScreen(autoReturn: true),
        fullscreenDialog: true,
      ),
    );
    // result == true means they tapped "GET STARTED" and want to log in
    if (result == true && mounted) {
      _applyRoleSwitch(_Role.admin);
    }
    // result == null/false means they pressed back — do nothing
  }

  // ─── Auth ───────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (_loginLock || _role == null) return;
    _loginLock = true;

    final String inputId = _idCtrl.text.trim().toUpperCase();
    final String code    = _codeCtrl.text.trim();
    FocusScope.of(context).unfocus();

    if (inputId.isEmpty || code.isEmpty) {
      _toast('Error: Fields cannot be left blank.', Colors.orange);
      _loginLock = false;
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_role == _Role.admin) {
        if (_selectedSociety == null) {
          _toast('Please select a society / apartment first.', Colors.orange);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        if (inputId != _kAdminId || code != _kAdminCode) {
          _toast('ACCESS DENIED: Invalid admin credentials.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        if (mounted) {
          _grantAccess('✅ Admin credentials verified — checking subscription…');
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            // Route through PaymentGateScreen.
            // It will auto-navigate to /admin_dashboard if subscription is active,
            // or show the trial / payment wall if not.
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentGateScreen(
                  societyName    : _selectedSociety!.mainText,
                  societyAddress : _selectedSociety!.fullDescription,
                  placeId        : _selectedSociety!.placeId,
                ),
              ),
            );
          }
        }
        return;
      }

      DocumentSnapshot? userDoc;
      Map<String, dynamic>? data;

      if (_role == _Role.guard) {
        final snap = await FirebaseFirestore.instance
            .collection('guards')
            .where('guardId', isEqualTo: inputId)
            .get();
        if (snap.docs.isEmpty) {
          _toast('ACCESS DENIED: ID not registered in system.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        userDoc = snap.docs.first;
        data    = userDoc.data() as Map<String, dynamic>?;
      } else {
        final snap = await FirebaseFirestore.instance
            .collection('residents')
            .doc(inputId)
            .get();
        if (!snap.exists) {
          _toast('ACCESS DENIED: Flat not registered in system.', Colors.red);
          setState(() => _isLoading = false);
          _loginLock = false;
          return;
        }
        userDoc = snap;
        data    = userDoc.data() as Map<String, dynamic>?;
      }

      if (data == null ||
          !data.containsKey('accessCode') ||
          data['accessCode'] == null) {
        _toast('SERVER ERROR: Profile configuration incomplete.', Colors.redAccent);
        setState(() => _isLoading = false);
        _loginLock = false;
        return;
      }

      if (data['accessCode'].toString().trim() != code) {
        _toast('ACCESS DENIED: Incorrect Access Code.', Colors.red);
        setState(() => _isLoading = false);
        _loginLock = false;
        return;
      }

      if (_role == _Role.guard) {
        final guardName = (data['guardName'] as String?)?.trim() ?? '';
        activeGuardName = guardName.isNotEmpty ? guardName : inputId;
        await FirebaseFirestore.instance
            .collection('guards')
            .doc(userDoc.id)
            .update({
          'onDuty'   : true,
          'dutyStart': FieldValue.serverTimestamp(),
          'guardName': activeGuardName,
          'guardId'  : inputId,
        });
      }

      if (mounted) {
        _grantAccess('✅ Access Granted! Loading dashboard...');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            _role == _Role.guard ? '/guard_dashboard' : '/resident_dashboard',
            arguments: inputId,
          );
        }
      }
    } catch (e, st) {
      debugPrint('🚨 AUTH ERROR: $e\n$st');
      if (mounted) {
        _toast('System Error. Please try again.', Colors.red);
        setState(() => _isLoading = false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _loginLock = false;
    }
  }

  void _grantAccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      backgroundColor: Colors.green.shade700,
      duration       : const Duration(milliseconds: 800),
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin         : const EdgeInsets.all(16),
    ));
  }

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content : Text(msg,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: bg,
        behavior       : SnackBarBehavior.floating,
        margin         : const EdgeInsets.all(16),
        shape          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration       : const Duration(seconds: 4),
      ));
  }

  // ─── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor     = isDark ? AppTokens.darkBg         : AppTokens.lightBg;
    final Color cardColor   = isDark ? AppTokens.darkSurface     : AppTokens.lightSurface;
    final Color cardBorder  = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;
    final Color titleColor  = isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary;
    final Color subColor    = isDark ? AppTokens.darkAccent      : AppTokens.lightAccent;
    final Color shadowColor = isDark ? Colors.black38            : const Color(0xFFCBD5E1);

    final Color roleAccent  = _role?.accentColor ?? AppTokens.cyanAction;
    final bool  hasRole     = _role != null;
    final bool  isAdmin     = _role == _Role.admin;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (_, mode, __) => IconButton(
              icon: Icon(
                mode == ThemeMode.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: isDark ? Colors.white54 : AppTokens.lightTextSecond,
              ),
              tooltip  : 'Toggle Theme',
              onPressed: () => themeNotifier.value =
              mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              children: [

                // ── Logo ────────────────────────────────────────────────
                Hero(
                  tag: 'logo',
                  child: Icon(
                    isAdmin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.qr_code_scanner_rounded,
                    size : 70,
                    color: roleAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text('SocCar',
                    style: TextStyle(
                      color        : titleColor,
                      fontSize     : 22,
                      fontWeight   : FontWeight.bold,
                      letterSpacing: 5,
                    )),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey(_role),
                    hasRole
                        ? (isAdmin ? 'ADMIN CONTROL PANEL' : 'SECURE ACCESS TERMINAL')
                        : 'SELECT YOUR ROLE TO CONTINUE',
                    style: TextStyle(
                      color        : subColor,
                      fontSize     : 10,
                      letterSpacing: 2,
                      fontWeight   : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Card ────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color       : cardColor,
                    borderRadius: BorderRadius.circular(24),
                    border      : Border.all(color: cardBorder),
                    boxShadow   : [BoxShadow(blurRadius: 30, color: shadowColor)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // ── VERTICAL role selector ────────────────────────
                      Column(
                        children: _Role.values.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RoleChip(
                            role    : r,
                            selected: _role == r,
                            isDark  : isDark,
                            onTap   : () => _selectRole(r),
                          ),
                        )).toList(),
                      ),

                      // ── Form — only visible after role selected ───────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        curve   : Curves.easeInOut,
                        child   : hasRole
                            ? SlideTransition(
                          position: _slideAnim,
                          child: FadeTransition(
                            opacity: _slideCtrl,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                                // Divider
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Row(children: [
                                    Expanded(child: Divider(
                                        color: isDark ? Colors.white12 : Colors.grey.shade200)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Text('ENTER CREDENTIALS',
                                          style: TextStyle(
                                            color   : isDark ? Colors.white24 : Colors.grey.shade400,
                                            fontSize: 9,
                                            letterSpacing: 1.5,
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ),
                                    Expanded(child: Divider(
                                        color: isDark ? Colors.white12 : Colors.grey.shade200)),
                                  ]),
                                ),

                                // Society picker — Admin only
                                if (isAdmin) ...[
                                  SocietySearchField(
                                    isDark     : isDark,
                                    accentColor: roleAccent,
                                    onSelected : (s) =>
                                        setState(() => _selectedSociety = s),
                                  ),
                                  const SizedBox(height: 14),
                                  // Admin restricted banner
                                  Container(
                                    width  : double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color       : roleAccent.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: roleAccent.withOpacity(0.3)),
                                    ),
                                    child: Row(children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: roleAccent, size: 15),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Restricted — authorised personnel only.',
                                          style: TextStyle(
                                            color    : roleAccent,
                                            fontSize : 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ]),
                                  ),
                                  const SizedBox(height: 14),
                                ],

                                // ID field
                                _buildField(
                                  controller : _idCtrl,
                                  focusNode  : _idFocus,
                                  label      : _roleIdLabel,
                                  hint       : _roleIdHint,
                                  icon       : _role!.icon,
                                  inputAction: TextInputAction.next,
                                  capitalize : TextCapitalization.characters,
                                  onSubmitted: (_) => FocusScope.of(context)
                                      .requestFocus(_codeFocus),
                                  isDark     : isDark,
                                  accentColor: roleAccent,
                                ),
                                const SizedBox(height: 14),

                                // Access Code field
                                _buildField(
                                  controller : _codeCtrl,
                                  focusNode  : _codeFocus,
                                  label      : 'Access Code',
                                  hint       : 'Enter access code',
                                  icon       : Icons.lock_rounded,
                                  inputAction: TextInputAction.done,
                                  obscure    : _obscureCode,
                                  onSubmitted: (_) {
                                    if (!_isLoading) _login();
                                  },
                                  isDark     : isDark,
                                  accentColor: roleAccent,
                                  suffixIcon : IconButton(
                                    icon: Icon(
                                      _obscureCode
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size : 20,
                                      color: isDark
                                          ? Colors.white38
                                          : AppTokens.lightTextHint,
                                    ),
                                    onPressed: () => setState(
                                            () => _obscureCode = !_obscureCode),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Authenticate button
                                SizedBox(
                                  width : double.infinity,
                                  height: 54,
                                  child : ElevatedButton(
                                    onPressed: _isLoading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor        : roleAccent,
                                      foregroundColor        : Colors.black,
                                      disabledBackgroundColor: roleAccent.withOpacity(0.3),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.radiusButton)),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                        width : 22, height: 22,
                                        child : CircularProgressIndicator(
                                            color: Colors.black, strokeWidth: 2.5))
                                        : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(_role!.icon,
                                            size: 18, color: Colors.black),
                                        const SizedBox(width: 8),
                                        Text(
                                          isAdmin
                                              ? 'ENTER ADMIN PANEL'
                                              : 'AUTHENTICATE',
                                          style: const TextStyle(
                                            fontSize     : 15,
                                            fontWeight   : FontWeight.w900,
                                            letterSpacing: 1.3,
                                            color        : Colors.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Text(
                  hasRole
                      ? (isAdmin
                      ? 'Welcome to the Admin section.'
                      : 'Contact your society office if you need access.')
                      : 'Tap a role above to get started.',
                  style: TextStyle(
                      color   : isDark ? Colors.white24 : Colors.grey.shade400,
                      fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _roleIdLabel {
    switch (_role) {
      case _Role.guard:    return 'Guard ID';
      case _Role.resident: return 'Flat Number';
      case _Role.admin:    return 'Admin ID';
      case null:           return 'ID';
    }
  }

  String get _roleIdHint {
    switch (_role) {
      case _Role.guard:    return 'e.g. GUARD1';
      case _Role.resident: return 'e.g. A101';
      case _Role.admin:    return 'Enter admin ID';
      case null:           return '';
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required FocusNode             focusNode,
    required String                label,
    required String                hint,
    required IconData              icon,
    required TextInputAction       inputAction,
    required bool                  isDark,
    Color                          accentColor = AppTokens.cyanAction,
    bool                           obscure     = false,
    TextCapitalization             capitalize  = TextCapitalization.none,
    Widget?                        suffixIcon,
    void Function(String)?         onSubmitted,
  }) {
    final Color textColor   = isDark ? AppTokens.darkTextPrimary : AppTokens.lightTextPrimary;
    final Color labelColor  = isDark ? AppTokens.darkTextSecond  : AppTokens.lightTextSecond;
    final Color hintColor   = isDark ? AppTokens.darkTextHint    : AppTokens.lightTextHint;
    final Color fillColor   = isDark ? AppTokens.darkFieldFill   : AppTokens.lightFieldFill;
    final Color borderColor = isDark ? AppTokens.darkBorder      : AppTokens.lightBorder;

    return TextField(
      controller        : controller,
      focusNode         : focusNode,
      enabled           : !_isLoading,
      obscureText       : obscure,
      textCapitalization: capitalize,
      textInputAction   : inputAction,
      onSubmitted       : onSubmitted,
      style             : TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText : label,
        hintText  : hint,
        labelStyle: TextStyle(color: labelColor, fontSize: 14),
        hintStyle : TextStyle(color: hintColor,  fontSize: 14),
        prefixIcon: Icon(icon, color: accentColor, size: 20),
        suffixIcon: suffixIcon,
        filled    : true,
        fillColor : fillColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: borderColor, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          borderSide  : BorderSide(color: accentColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleChip — vertical full-width role card
// ─────────────────────────────────────────────────────────────────────────────
class _RoleChip extends StatelessWidget {
  final _Role        role;
  final bool         selected;
  final bool         isDark;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // All roles use the same cyan/blue accent — consistent blue phase
    const Color accent     = AppTokens.cyanAction;
    final Color idleBorder = isDark ? Colors.white12    : const Color(0xFFE2E8F0);
    final Color idleText   = isDark ? Colors.white70    : AppTokens.lightTextPrimary;
    final Color idleSubText= isDark ? Colors.white38    : AppTokens.lightTextSecond;
    final Color idleFill   = isDark ? const Color(0xFF141428) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration : const Duration(milliseconds: 220),
        width    : double.infinity,
        padding  : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color       : selected ? accent.withOpacity(0.12) : idleFill,
          borderRadius: BorderRadius.circular(AppTokens.radiusInput),
          border: Border.all(
            color: selected ? accent : idleBorder,
            width: selected ? 2.0 : 1.0,
          ),
          boxShadow: selected
              ? [BoxShadow(
              color    : accent.withOpacity(0.18),
              blurRadius: 10,
              offset   : const Offset(0, 3))]
              : null,
        ),
        child: Row(
          children: [
            // Role icon in a circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width : 40,
              height: 40,
              decoration: BoxDecoration(
                color       : selected
                    ? accent.withOpacity(0.18)
                    : (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                role.icon,
                size : 20,
                color: selected ? accent : idleSubText,
              ),
            ),
            const SizedBox(width: 14),
            // Label + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label,
                      style: TextStyle(
                        color     : selected ? accent : idleText,
                        fontWeight: FontWeight.bold,
                        fontSize  : 14,
                        letterSpacing: 0.3,
                      )),
                  const SizedBox(height: 2),
                  Text(role.subtitle,
                      style: TextStyle(
                        color  : selected
                            ? accent.withOpacity(0.7)
                            : idleSubText,
                        fontSize: 11,
                      )),
                ],
              ),
            ),
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width : 20,
              height: 20,
              decoration: BoxDecoration(
                shape      : BoxShape.circle,
                color      : selected ? accent : Colors.transparent,
                border     : Border.all(
                  color: selected ? accent : idleBorder,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                  size: 13, color: Colors.black)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}