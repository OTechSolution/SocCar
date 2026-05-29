// ─────────────────────────────────────────────────────────────────────────────
// AREA 3: FastDeliveryEntryForm
//
// Replaces _showApprovalRequestModal() in guard_dashboard.dart.
// Key improvements:
//   ✅ Vendor icon grid — single tap populates deliveryCompany
//   ✅ Predictive flat-number autocomplete (Firestore-backed, filters on 2+ chars)
//   ✅ No long typing required at peak hours
//
// Usage: call FastDeliveryEntryForm.show(context, guardId: _guardId, onSubmit: ...)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/notification_service.dart';

// Vendor definitions — add Flipkart/Blinkit entries as needed
class _Vendor {
  final String name;
  final IconData icon;
  final Color color;
  const _Vendor(this.name, this.icon, this.color);
}

const List<_Vendor> _vendors = [
  _Vendor('ZOMATO',   Icons.fastfood_rounded,        Color(0xFFE23744)),
  _Vendor('SWIGGY',   Icons.delivery_dining_rounded,  Color(0xFFFC8019)),
  _Vendor('AMAZON',   Icons.local_shipping_rounded,   Color(0xFFFF9900)),
  _Vendor('FLIPKART', Icons.shopping_bag_rounded,     Color(0xFF2874F0)),
  _Vendor('BLINKIT',  Icons.bolt_rounded,             Color(0xFFFFCC00)),
  _Vendor('OTHER',    Icons.pending_actions_rounded,  Color(0xFF607D8B)),
];

class FastDeliveryEntryForm extends StatefulWidget {
  final String? guardId;
  final String initialVendor;

  const FastDeliveryEntryForm({
    super.key,
    this.guardId,
    this.initialVendor = 'ZOMATO',
  });

  static Future<void> show(
    BuildContext context, {
    String? guardId,
    String initialVendor = 'ZOMATO',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FastDeliveryEntryForm(
        guardId: guardId,
        initialVendor: initialVendor,
      ),
    );
  }

  @override
  State<FastDeliveryEntryForm> createState() => _FastDeliveryEntryFormState();
}

class _FastDeliveryEntryFormState extends State<FastDeliveryEntryForm> {
  late String _selectedVendor;
  final TextEditingController _flatController = TextEditingController();
  final FocusNode _flatFocusNode = FocusNode();

  // Autocomplete state
  List<String> _flatSuggestions = [];
  List<String> _allFlats = []; // loaded once from Firestore
  bool _loadingFlats = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selectedVendor = widget.initialVendor;
    _loadFlats();
    _flatController.addListener(_onFlatTyped);
  }

  @override
  void dispose() {
    _flatController.removeListener(_onFlatTyped);
    _flatController.dispose();
    _flatFocusNode.dispose();
    super.dispose();
  }

  // ── Load all flat numbers once from Firestore ──────────────────────────
  Future<void> _loadFlats() async {
    setState(() => _loadingFlats = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('residents')
          .get();
      final flats = snap.docs
          .map((d) => (d.data()['flatNumber'] as String? ?? d.id).toUpperCase())
          .where((f) => f.isNotEmpty)
          .toList()
        ..sort();
      setState(() => _allFlats = flats);
    } catch (e) {
      debugPrint('⚠️ Could not load flat list: $e');
    } finally {
      setState(() => _loadingFlats = false);
    }
  }

  // ── Filter suggestions on every keystroke ──────────────────────────────
  void _onFlatTyped() {
    final query = _flatController.text.trim().toUpperCase();
    if (query.length < 2) {
      setState(() => _flatSuggestions = []);
      return;
    }
    setState(() {
      _flatSuggestions = _allFlats
          .where((f) => f.contains(query))
          .take(6)
          .toList();
    });
  }

  void _selectFlat(String flat) {
    _flatController.text = flat;
    _flatController.selection = TextSelection.fromPosition(
        TextPosition(offset: flat.length));
    setState(() => _flatSuggestions = []);
    _flatFocusNode.unfocus();
  }

  // ── Submit to Firestore + push notification ────────────────────────────
  Future<void> _submit() async {
    final flatNumber = _flatController.text.trim().toUpperCase();
    if (flatNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or select a flat number.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // Determine a placeholder photo for the vendor
      const photoMap = {
        'ZOMATO':   'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
        'SWIGGY':   'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
        'AMAZON':   'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?w=150',
        'FLIPKART': 'https://images.unsplash.com/photo-1523381210434-271e8be1f52b?w=150',
        'BLINKIT':  'https://images.unsplash.com/photo-1614190187639-37b0c04c19e1?w=150',
      };

      final docRef = await FirebaseFirestore.instance
          .collection('approvals')
          .add({
        'flatNumber': flatNumber,
        'company': _selectedVendor,
        'status': 'PENDING',
        'sentBy': widget.guardId ?? 'GUARD',
        'timestamp': FieldValue.serverTimestamp(),
        'visitorPhotoUrl':
            photoMap[_selectedVendor] ??
            'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150',
      });

      await NotificationService().notifyResidentOfDelivery(
        flatNumber: flatNumber,
        company: _selectedVendor,
        guardId: widget.guardId ?? 'GUARD',
        approvalDocId: docRef.id,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '📲 Alert sent to Flat $flatNumber — waiting for approval.'),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF141428),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Quick Delivery Entry',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          const Text('Tap a provider, then select the flat.',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 20),

          // ── Vendor Icon Grid ───────────────────────────────────────
          const Text('DELIVERY PROVIDER',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: _vendors.map((v) {
              final bool selected = _selectedVendor == v.name;
              return GestureDetector(
                onTap: () => setState(() => _selectedVendor = v.name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    color: selected
                        ? v.color.withOpacity(0.9)
                        : v.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: v.color,
                        width: selected ? 2 : 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(v.icon,
                          size: 15,
                          color: selected ? Colors.white : v.color),
                      const SizedBox(width: 5),
                      Text(
                        v.name,
                        style: TextStyle(
                          color: selected ? Colors.white : v.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          // ── Predictive Flat Search ─────────────────────────────────
          const Text('DESTINATION FLAT',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          TextField(
            controller: _flatController,
            focusNode: _flatFocusNode,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Type B-2 to filter...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.home_work_rounded,
                  color: Colors.cyanAccent),
              suffixIcon: _loadingFlats
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.cyanAccent, strokeWidth: 2)))
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: Colors.cyanAccent, width: 1.5)),
            ),
          ),

          // ── Suggestions list ───────────────────────────────────────
          if (_flatSuggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C3A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: _flatSuggestions.map((flat) {
                  return InkWell(
                    onTap: () => _selectFlat(flat),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          const Icon(Icons.apartment_rounded,
                              color: Colors.cyanAccent, size: 16),
                          const SizedBox(width: 10),
                          Text(flat,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // ── Submit ─────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text('SEND APPROVAL REQUEST',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOW TO INTEGRATE in guard_dashboard.dart:
//
// 1. Import this file.
// 2. Replace every call to _showApprovalRequestModal() with:
//      FastDeliveryEntryForm.show(context, guardId: _guardId, initialVendor: vendor['name']);
// 3. Remove the old _showApprovalRequestModal() method entirely.
// ─────────────────────────────────────────────────────────────────────────────
