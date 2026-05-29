import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Global guard name state (set by LoginScreen on Guard auth) ───────────────
String activeGuardName = 'Guard On Duty';

// ─── Provider model ───────────────────────────────────────────────────────────
class _DeliveryProvider {
  final String name;
  final Color color;
  final IconData icon;
  const _DeliveryProvider(this.name, this.color, this.icon);
}

const List<_DeliveryProvider> _kProviders = [
  _DeliveryProvider('ZOMATO',   Color(0xFFE23744), Icons.fastfood_rounded),
  _DeliveryProvider('SWIGGY',   Color(0xFFFC8019), Icons.delivery_dining),
  _DeliveryProvider('AMAZON',   Color(0xFFFF9900), Icons.local_shipping_rounded),
  _DeliveryProvider('FLIPKART', Color(0xFF2874F0), Icons.shopping_bag_rounded),
  _DeliveryProvider('BLINKIT',  Color(0xFFFFE100), Icons.electric_bolt_rounded),
  _DeliveryProvider('OTHER',    Color(0xFF8A8A8A), Icons.more_horiz_rounded),
];

// ─────────────────────────────────────────────────────────────────────────────
class LogMovementScreen extends StatefulWidget {
  const LogMovementScreen({super.key});

  @override
  State<LogMovementScreen> createState() => _LogMovementScreenState();
}

class _LogMovementScreenState extends State<LogMovementScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final _plateController      = TextEditingController();
  final _flatController       = TextEditingController();
  final _driverNameController = TextEditingController();
  final _otpController        = TextEditingController();
  final _customCompanyCtrl    = TextEditingController();

  // State
  bool   _isEntry          = true;
  bool   _isSaving         = false;
  String _selectedCompany  = '';   // empty = none selected
  String _selectedVehicleType = 'Sedan';

  final List<String> _vehicleTypes = ['Sedan', 'SUV', 'Hatchback', 'Two-Wheeler'];

  // Animation controller for OTHER field reveal
  late final AnimationController _otherAnimCtrl;
  late final Animation<double>   _otherAnim;

  // Dark theme palette — always dark regardless of system theme
  static const _bg        = Color(0xFF111428);
  static const _surface   = Color(0xFF1A1D35);
  static const _surface2  = Color(0xFF22264A);
  static const _border    = Color(0xFF2E3160);
  static const _cyan      = Color(0xFF00E5FF);
  static const _textW     = Colors.white;
  static const _textW70   = Colors.white70;
  static const _textW38   = Colors.white38;

  @override
  void initState() {
    super.initState();
    _otherAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _otherAnim = CurvedAnimation(
      parent: _otherAnimCtrl,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    _flatController.dispose();
    _driverNameController.dispose();
    _otpController.dispose();
    _customCompanyCtrl.dispose();
    _otherAnimCtrl.dispose();
    super.dispose();
  }

  void _selectProvider(String name) {
    setState(() => _selectedCompany = name);
    if (name == 'OTHER') {
      _otherAnimCtrl.forward();
    } else {
      _otherAnimCtrl.reverse();
    }
  }

  void _simulatePlateScan() {
    setState(() => _plateController.text = 'MH 12 AB 1234');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Plate scanned successfully via OCR snapshot camera!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendApprovalRequest() async {
    final String plateText  = _plateController.text.trim().toUpperCase();
    final String targetFlat = _flatController.text.trim().toUpperCase();
    final String driverName = _driverNameController.text.trim();
    final String otpCode    = _otpController.text.trim();
    final String company    = _selectedCompany == 'OTHER'
        ? (_customCompanyCtrl.text.trim().toUpperCase().isEmpty
            ? 'OTHER'
            : _customCompanyCtrl.text.trim().toUpperCase())
        : _selectedCompany;

    if (company.isEmpty) {
      _showSnackbar('Please select a delivery provider.', Colors.orange);
      return;
    }
    if (plateText.isEmpty) {
      _showSnackbar('Number plate / tracking info is required.', Colors.orange);
      return;
    }
    if (targetFlat.isEmpty) {
      _showSnackbar('Destination flat number is required.', Colors.redAccent);
      return;
    }

    setState(() => _isSaving = true);

    const String driverPic =
        'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=300';

    try {
      final String generatedOtp = otpCode.isNotEmpty
          ? otpCode
          : (1000 + DateTime.now().millisecond % 9000).toString();

      // Write to logs collection
      await FirebaseFirestore.instance.collection('logs').add({
        'plateNumber' : plateText,
        'type'        : _isEntry ? 'ENTRY' : 'EXIT',
        'entryType'   : _isEntry ? 'ENTRY' : 'EXIT',
        'company'     : company,
        'vehicleModel': _selectedVehicleType,
        'guardId'     : activeGuardName,
        'guardName'   : activeGuardName,
        'driverName'  : driverName.isNotEmpty ? driverName : 'Delivery Agent',
        'driverPic'   : driverPic,
        'otpCode'     : generatedOtp,
        'flatNumber'  : targetFlat,   // ← resident Activity tab filters by this
        'flat_number' : targetFlat,   // ← legacy alias
        'timestamp'   : FieldValue.serverTimestamp(),
      });

      // Write to approvals collection
      await FirebaseFirestore.instance.collection('approvals').add({
        'company'     : company,
        'plateNumber' : plateText,
        'flatNumber'  : targetFlat,
        'status'      : 'PENDING',
        'sentBy'      : activeGuardName,
        'guardName'   : activeGuardName,
        'vehicleModel': _selectedVehicleType,
        'otpCode'     : generatedOtp,
        'driverName'  : driverName.isNotEmpty ? driverName : 'Delivery Agent',
        'driverPic'   : driverPic,
        'timestamp'   : FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _showSnackbar(
            'Approval request sent to Flat $targetFlat!', Colors.green);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _showSnackbar('Database write fault: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackbar(String text, Color bgColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: bgColor),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 14,
        left: 20,
        right: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Guard badge ──────────────────────────────────────────────
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded,
                        size: 13, color: Colors.greenAccent),
                    const SizedBox(width: 6),
                    Text(
                      'On Duty: $activeGuardName',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Heading ──────────────────────────────────────────────────
            const Text(
              'Quick Delivery Entry',
              style: TextStyle(
                color: _textW,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap a provider, then select the flat.',
              style: TextStyle(color: _textW38, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // ── Provider label ───────────────────────────────────────────
            _sectionLabel('DELIVERY PROVIDER'),
            const SizedBox(height: 10),

            // ── Provider grid ────────────────────────────────────────────
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: _kProviders.length,
              itemBuilder: (_, i) => _buildProviderChip(_kProviders[i]),
            ),
            const SizedBox(height: 10),

            // ── OTHER custom name field ──────────────────────────────────
            SizeTransition(
              sizeFactor: _otherAnim,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _darkField(
                  controller: _customCompanyCtrl,
                  label: 'Enter Custom Company Name',
                  hint: 'e.g. FedEx, Dunzo, Blue Dart...',
                  icon: Icons.business_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
            ),

            const SizedBox(height: 6),
            _sectionLabel('NUMBER PLATE / INFO'),
            const SizedBox(height: 10),

            // ── Plate + scan ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _darkField(
                    controller: _plateController,
                    label: 'Number Plate',
                    hint: 'e.g. MH 12 AB 1234',
                    icon: Icons.pin_rounded,
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _simulatePlateScan,
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _cyan.withOpacity(0.5)),
                    ),
                    child: const Icon(Icons.document_scanner_rounded,
                        color: _cyan, size: 26),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Driver name ──────────────────────────────────────────────
            _darkField(
              controller: _driverNameController,
              label: 'Driver / Agent Name (optional)',
              hint: 'e.g. Rajesh Kumar',
              icon: Icons.person_rounded,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),

            // ── OTP ──────────────────────────────────────────────────────
            _darkField(
              controller: _otpController,
              label: 'Verification OTP (optional)',
              hint: '4–6 digit code',
              icon: Icons.lock_rounded,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 18),

            // ── Vehicle type chips ───────────────────────────────────────
            _sectionLabel('VEHICLE TYPE'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _vehicleTypes.map((type) {
                final selected = _selectedVehicleType == type;
                return GestureDetector(
                  onTap: () => setState(() => _selectedVehicleType = type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? _cyan.withOpacity(0.15)
                          : _surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? _cyan : _border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color: selected ? _cyan : _textW70,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // ── Destination flat ─────────────────────────────────────────
            _sectionLabel('DESTINATION FLAT'),
            const SizedBox(height: 10),
            _darkField(
              controller: _flatController,
              label: 'Type B-2 to filter...',
              hint: 'e.g. B-402',
              icon: Icons.apartment_rounded,
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 14),

            // ── Check-in / Check-out toggle ──────────────────────────────
            Row(
              children: [
                _directionChip(
                    'CHECK-IN', true, Colors.greenAccent),
                const SizedBox(width: 12),
                _directionChip(
                    'CHECK-OUT', false, Colors.redAccent),
              ],
            ),
            const SizedBox(height: 22),

            // ── SEND APPROVAL REQUEST button ─────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _sendApprovalRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _cyan,
                  disabledBackgroundColor: _cyan.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'SEND APPROVAL REQUEST',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Provider chip ────────────────────────────────────────────────────────
  Widget _buildProviderChip(_DeliveryProvider p) {
    final selected = _selectedCompany == p.name;
    // Special: BLINKIT text is dark because background highlight is yellow
    final textColor = (selected && p.name == 'BLINKIT')
        ? Colors.black
        : (selected ? p.color : _textW70);

    return GestureDetector(
      onTap: () => _selectProvider(p.name),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? p.color.withOpacity(0.18) : _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? p.color : _border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(p.icon,
                size: 15,
                color: selected ? p.color : _textW38),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dark text field ──────────────────────────────────────────────────────
  Widget _darkField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      keyboardType: keyboardType,
      style: const TextStyle(color: _textW, fontSize: 14),
      cursorColor: _cyan,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: _cyan.withOpacity(0.8), size: 20),
        labelText: label,
        labelStyle: const TextStyle(color: _textW38, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: _textW38, fontSize: 13),
        filled: true,
        fillColor: _surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _cyan, width: 1.5),
        ),
      ),
    );
  }

  // ─── Section label ────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _textW38,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  // ─── Direction chip ───────────────────────────────────────────────────────
  Widget _directionChip(String label, bool isEntry, Color accent) {
    final selected = _isEntry == isEntry;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isEntry = isEntry),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 44,
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.15) : _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : _border,
              width: selected ? 1.5 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? accent : _textW70,
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}