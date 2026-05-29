import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddVehicleScreen extends StatefulWidget {
  final String defaultFlat;
  const AddVehicleScreen({super.key, required this.defaultFlat});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final TextEditingController _plateController = TextEditingController();
  final TextEditingController _ownerController = TextEditingController();
  late TextEditingController _flatController;
  final TextEditingController _contactController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _flatController = TextEditingController(text: widget.defaultFlat);
  }

  @override
  void dispose() {
    _plateController.dispose();
    _ownerController.dispose();
    _flatController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _registerVehicle() async {
    final String plate = _plateController.text.trim().toUpperCase();
    final String owner = _ownerController.text.trim();
    final String flat = _flatController.text.trim().toUpperCase();
    final String phone = _contactController.text.trim();

    if (plate.isEmpty || owner.isEmpty || flat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All core configuration parameters required!")));
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      // 1. Log asset declaration metadata entry into 'vehicles' collection
      await FirebaseFirestore.instance.collection('vehicles').add({
        'plateNumber': plate,
        'ownerName': owner,
        'flatNumber': flat,
        'contact': phone,
        'timestamp': FieldValue.serverTimestamp(),
        'verificationStatus': 'PENDING', // Guard must verify before green
      });

      // 2. Safely sync the profile name schema into the 'residents' index document
      await FirebaseFirestore.instance.collection('residents').doc(flat).set({
        'ownerName': owner,
        'contact': phone,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vehicle registered! Awaiting guard verification."), backgroundColor: Colors.orange));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync execution crash: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register Vehicle Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          children: [
            _inputField("Plate ID Number (e.g., MH-12-AB-1234)", Icons.pin, _plateController),
            const SizedBox(height: 20),
            _inputField("Full Owner Legal Identity Name", Icons.person, _ownerController),
            const SizedBox(height: 20),
            _inputField("Flat Number (e.g. B-402)", Icons.home, _flatController),
            const SizedBox(height: 20),
            _inputField("Contact Number", Icons.phone, _contactController),
            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _registerVehicle,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("CONFIRM REGISTRATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _inputField(String label, IconData icon, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.black),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.blueAccent),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }
}