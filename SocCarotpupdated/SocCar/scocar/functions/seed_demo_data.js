/**
 * SocCar OS — Firestore Demo Data Seeder
 * ─────────────────────────────────────────────────────────────────────────────
 * Run this script once to populate Firestore with clean demo data.
 *
 * Usage:
 *   npm install firebase-admin
 *   node seed_demo_data.js
 *
 * IMPORTANT: Set GOOGLE_APPLICATION_CREDENTIALS env var to your service account key
 *   export GOOGLE_APPLICATION_CREDENTIALS="path/to/serviceAccountKey.json"
 *
 * Or download the key from:
 *   Firebase Console → Project Settings → Service Accounts → Generate New Private Key
 */

const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "scocar-bd398",  // ← your project ID
});

const db = admin.firestore();

async function seed() {
  console.log("🌱 Seeding SocCar demo data...\n");

  // ── GUARDS ────────────────────────────────────────────────────────────────
  const guards = [
    { guardId: "G001", name: "Ram Singh", accessCode: "1234", shift: "MORNING", phone: "+91-9876543210" },
    { guardId: "G002", name: "Shyam Kumar", accessCode: "5678", shift: "NIGHT", phone: "+91-9876543211" },
  ];

  for (const guard of guards) {
    await db.collection("guards").doc(guard.guardId).set(guard);
    console.log(`✅ Guard: ${guard.name} (${guard.guardId})`);
  }

  // ── RESIDENTS ─────────────────────────────────────────────────────────────
  const residents = [
    { flatNumber: "A-101", ownerName: "Rahul Sharma", accessCode: "1111", phone: "+91-9876500001" },
    { flatNumber: "A-102", ownerName: "Priya Mehta",  accessCode: "2222", phone: "+91-9876500002" },
    { flatNumber: "B-201", ownerName: "Amit Verma",   accessCode: "3333", phone: "+91-9876500003" },
    { flatNumber: "B-202", ownerName: "Sunita Rao",   accessCode: "4444", phone: "+91-9876500004" },
  ];

  for (const resident of residents) {
    await db.collection("residents").doc(resident.flatNumber).set(resident);
    console.log(`✅ Resident: ${resident.ownerName} (${resident.flatNumber})`);
  }

  // ── VEHICLES ──────────────────────────────────────────────────────────────
  const vehicles = [
    { plateNumber: "DL-01-AB-1234", ownerName: "Rahul Sharma", flatNumber: "A-101", make: "Maruti Swift", color: "White" },
    { plateNumber: "DL-02-CD-5678", ownerName: "Priya Mehta",  flatNumber: "A-102", make: "Honda City",  color: "Silver" },
    { plateNumber: "UP-32-EF-9012", ownerName: "Amit Verma",   flatNumber: "B-201", make: "Hyundai i20", color: "Red" },
  ];

  for (const vehicle of vehicles) {
    await db.collection("vehicles").add(vehicle);
    console.log(`✅ Vehicle: ${vehicle.plateNumber} (${vehicle.flatNumber})`);
  }

  // ── LOGS (sample gate history) ─────────────────────────────────────────────
  const logs = [
    { plateNumber: "DL-01-AB-1234", type: "ENTRY", company: "GENERAL", flatNumber: "A-101", guardId: "G001" },
    { plateNumber: "DL-02-CD-5678", type: "ENTRY", company: "GENERAL", flatNumber: "A-102", guardId: "G001" },
    { plateNumber: "DL-01-AB-1234", type: "EXIT",  company: "GENERAL", flatNumber: "A-101", guardId: "G002" },
  ];

  for (const log of logs) {
    await db.collection("logs").add({
      ...log,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ Log: ${log.plateNumber} ${log.type}`);
  }

  // ── OWNERIDS (for login lookup) ────────────────────────────────────────────
  // ownerIds stores mapping for rapid lookup if needed
  // (your current login uses guards/residents collections directly — this is optional)

  console.log("\n✅ All demo data seeded successfully!");
  console.log("\n📋 LOGIN CREDENTIALS:");
  console.log("   Guards:    G001 / 1234,  G002 / 5678");
  console.log("   Residents: A-101 / 1111, A-102 / 2222, B-201 / 3333, B-202 / 4444");
  process.exit(0);
}

seed().catch((err) => {
  console.error("❌ Seeding failed:", err);
  process.exit(1);
});
