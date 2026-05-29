import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// ─────────────────────────────────────────────────────────────────────────────
/// NotificationService
///
/// Handles ALL notification logic for SocCar:
///   1. Local notifications (shown inside the app using flutter_local_notifications)
///   2. FCM token management (save/refresh tokens to Firestore)
///   3. Sending push notifications to residents via FCM HTTP v1 API
///   4. Sending push notifications to guards when resident responds
///
/// Architecture note:
///   Real-world production apps send FCM from a server (Cloud Functions, backend).
///   This service uses FCM HTTP v1 API directly from the app for demo/testing.
///   In production, move _sendFcmPush() to a Cloud Function triggered by
///   Firestore writes (index.js included in /functions/index.js).
/// ─────────────────────────────────────────────────────────────────────────────
class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  // ── Android notification channel ──────────────────────────────────────────
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'soccar_high_importance', // id
    'SocCar Alerts', // name
    description: 'Gate entry approvals, delivery alerts and vehicle logs',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ── Initialise local notifications + request permissions ─────────────────
  Future<void> init() async {
    // 1. Android init settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 2. iOS init settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 3. Create the high-importance channel on Android 8+
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 4. Request FCM permission (required for iOS / Android 13+)
    final NotificationSettings settings =
        await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
        '🔔 FCM permission status: ${settings.authorizationStatus}');

    // 5. Listen for foreground FCM messages → show as local notification
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. Handle notification tap when app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📬 Notification tapped (background): ${message.data}');
    });
  }

  // ── Called when a local notification is tapped ────────────────────────────
  void _onNotificationTap(NotificationResponse response) {
    debugPrint('🔔 Local notification tapped: ${response.payload}');
    // You can navigate using a global navigator key here if needed
  }

  // ── Show a local notification when app is in foreground ──────────────────
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await showLocalNotification(
      title: notification.title ?? 'SocCar Alert',
      body: notification.body ?? '',
      payload: jsonEncode(message.data),
    );
  }

  // ── Public: show any local notification immediately ───────────────────────
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'soccar_high_importance',
      'SocCar Alerts',
      channelDescription: 'Gate entry approvals and alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'SocCar',
      icon: '@mipmap/ic_launcher',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotif.show(
      id,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ── Save/refresh FCM token to Firestore for a resident ───────────────────
  // Future<void> saveResidentToken(String flatNumber) async {
  //   try {
  //     final String? token = await FirebaseMessaging.instance.getToken();
  //     if (token == null) {
  //       debugPrint('⚠️ FCM token is null — skipping save');
  //       return;
  //     }
  //     await FirebaseFirestore.instance
  //         .collection('residents')
  //         .doc(flatNumber)
  //         .set(
  //       {
  //         'fcmToken': token,
  //         'flatNumber': flatNumber, 
  //         'tokenUpdatedAt': FieldValue.serverTimestamp(),
  //       },
  //       SetOptions(merge: true),
  //     );
  //     debugPrint('✅ Resident FCM token saved for flat $flatNumber');

  //     // Listen for token refresh
  //     FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  //       await FirebaseFirestore.instance
  //           .collection('residents')
  //           .doc(flatNumber)
  //           .set(
  //         {'fcmToken': newToken, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
  //         SetOptions(merge: true),
  //       );
  //       debugPrint('🔄 FCM token refreshed for flat $flatNumber');
  //     });
  //   } catch (e) {
  //     debugPrint('❌ Error saving resident token: $e');
  //   }

  Future<void> saveResidentToken(String flatNumber) async {
  try {
    final String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) {
      debugPrint('⚠️ FCM token is null — skipping save');
      return;
    }
    final docRef = FirebaseFirestore.instance
        .collection('residents')
        .doc(flatNumber);
    await docRef.set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmToken': FieldValue.delete(),
        'flatNumber': flatNumber,
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    debugPrint('✅ Resident FCM token added to array for flat $flatNumber');
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await docRef.update({'fcmTokens': FieldValue.arrayRemove([token])});
      await docRef.update({
        'fcmTokens': FieldValue.arrayUnion([newToken]),
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    debugPrint('❌ Error saving resident token: $e');
  }
}
  

  // ── Save FCM token for a guard ────────────────────────────────────────────
  // Future<void> saveGuardToken(String guardId) async {
  //   try {
  //     final String? token = await FirebaseMessaging.instance.getToken();
  //     if (token == null) return;
  //     await FirebaseFirestore.instance
  //         .collection('guards')
  //         .doc(guardId)
  //         .set(
  //       {
  //         'fcmToken': token,
  //         'tokenUpdatedAt': FieldValue.serverTimestamp(),
  //       },
  //       SetOptions(merge: true),
  //     );
  //     debugPrint('✅ Guard FCM token saved for $guardId');

  //     FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  //       await FirebaseFirestore.instance
  //           .collection('guards')
  //           .doc(guardId)
  //           .set(
  //         {'fcmToken': newToken, 'tokenUpdatedAt': FieldValue.serverTimestamp()},
  //         SetOptions(merge: true),
  //       );
  //     });
  //   } catch (e) {
  //     debugPrint('❌ Error saving guard token: $e');
  //   }
  // }

  Future<void> saveGuardToken(String guardId) async {
  try {
    final String? token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final docRef = FirebaseFirestore.instance
        .collection('guards')
        .doc(guardId);
    await docRef.set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmToken': FieldValue.delete(),
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    debugPrint('✅ Guard FCM token added to array for $guardId');
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await docRef.update({'fcmTokens': FieldValue.arrayRemove([token])});
      await docRef.update({
        'fcmTokens': FieldValue.arrayUnion([newToken]),
        'tokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    });
  } catch (e) {
    debugPrint('❌ Error saving guard token: $e');
  }
}


  // ── CORE: Send a push notification to a specific FCM token ───────────────
  //
  // NOTE: This uses Firebase Cloud Messaging HTTP v1 API.
  // You MUST replace [_fcmServerKey] with your Firebase project's
  // SERVER KEY from: Firebase Console → Project Settings → Cloud Messaging
  //
  // For production: use Cloud Functions (see /functions/index.js)
  // The legacy FCM API key approach is shown below for simplicity.
  //
  static const String _fcmLegacyServerKey =
      "\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDWzElHKC/tiDUx\nrhoQhpJxtoQODzKyo9803d9mNylLRLxz2nvd090ws8FJQIq7Zsr5w7qa5a6x++eu\nhb8rJZ1Is/zojkMew5yrp1PX0ZbRHpxFkS3f+W7EKaUN8xjT2DgUxZ8hLRBBFw4R\nBClNFZU9BqcsJUyhJeFt3PWwaMynxlsV01231DjJSPJLjJXxXZoAiLmv9pNI9w3h\n/dtAcBSKzNiKvKOspXHA2AGL6aWdumXy6WC6mHLdGMlrqbI7Z25tjPx2YpNc2Juh\nN0/JFhnus3j7iqhZBZJmbugU1U9w+dMd0JKSapobiv2u/qWByWdjxEJwGAmzHH2g\ny4wJZx+3AgMBAAECggEAWBbtkmYTyclLb3VkMRTPaB0e6RkohISaHHdFkAjdQYYN\n90FJ/T5O/xMpGJ6EhrhwU6AGnlHFpC6X5EXrkYlaiJ9v//uf4TT9wpPb2a2VuWth\nUVJpyunjmEUv8Jmau/53eWVWjmeJu/f1h9r6CSfpzV42Hu+pDomXetPcWp2QGNmK\nxYxuzX38SelL9KrpwueQMcHe7RgxOAPnlprz3qTIDetHRzRNFAQpkXDFFkEicv5d\nFF4jdN0c4BUt7rQkUgygrysoKWep+5vqXKlfgb6XUYXJcmoVcH2EgPNFOvw/nmVx\nVD/NyO/huUsGF5+nFIL4+TfSSO2IV4D0vrEkwbMtkQKBgQDxIY3ylBxnDU2BNtN2\n0oWQlJHm1su7iBBrbpwayjZn0wxsFJAe28+8eBLtuZ8aAF29LHGgBZrxN3XjbcKB\nimKHqry6ldK6aqpd72SDYhpW6VF/IkOyuTiPZjBU5AaMWMYGEJHKHWPfl/4QiGRQ\n1fZpj76U+uaLt5P5CYNQolFujwKBgQDkCwsOZ/TMslZi79Wk/BqE/B9a35OTRvjK\n8hOYf9H2Ellc2IM/5nkXnQEsoi3PyHHZ9togmAd7QQPaGKrSQpQodLrosMIbQ93t\nc5wHYRFMBCS7OIVW2UFZPBTzFaqvhjk7lz/2uz8vi1ggVz+x47mkJlQcL9NOv5S1\nGE6g5EVQWQKBgQDa7/2DgMmdI+34YcB1RcayNMOY1fSb7HoEIaUpiesGMBE6XR1S\nd4DR/jApmv2DzUtPhXgRtKUvWYz3l+QgXHcD+ZlszLZOPqU7ry4TQNLrkONHTOQs\n9ZIOWdmOapArhDsgrJDC9BaHoOi1ODHlV7BpvnNrr7f+qgt39hQ99XN8rwKBgGGE\nG2lAqR0zkd9jAfA4YjrF+b6JZvkO22slk52d4zIf7JjYeV/E9blUSWFFxONaqtzz\nQ5m2iVR6m+QSslGRaPvX1umUVJ0GK4vT6T/6kUP5bZ+l7tcRtnErUSYV+NRwSF8k\nMZUXw1BYfQnvZWxznjoErekTxn+hSz0ZtN32X3GZAoGAWfTkxvLyJWTeSXPeG8w8\naR89HMciuNTHl+sdyJxPX54jsu2wKK7E57Ki6gwIz2sqQ5h8bNwb7BFDFdJexZJ7\nWnZOHqVGIk1Ox1ncI7hCnx6xXPjHMIRMgJM84JIwEFhKu2k4o4HtEDBzkTlqdcbn\npqJ8NQjyxeueq8E7VzInOXQ=\n";

  Future<bool> sendPushToToken({
    required String fcmToken,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (_fcmLegacyServerKey == 'YOUR_FCM_SERVER_KEY_HERE') {
      debugPrint('⚠️ FCM Server Key not set. Showing local notification only.');
      // Fallback: show local notification so dev can still test UI flow
      await showLocalNotification(title: title, body: body);
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_fcmLegacyServerKey',
        },
        body: jsonEncode({
          'to': fcmToken,
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
          },
          'data': data ?? {},
          'priority': 'high',
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'soccar_high_importance',
              'sound': 'default',
            },
          },
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Push notification sent successfully');
        return true;
      } else {
        debugPrint('❌ FCM error ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Exception sending push: $e');
      return false;
    }
  }

  // ── Send notification to resident when guard submits delivery request ─────
  Future<void> notifyResidentOfDelivery({
    required String flatNumber,
    required String company,
    required String guardId,
    required String approvalDocId,
  }) async {
    try {
      // 1. Fetch resident's FCM token from Firestore
      final QuerySnapshot residentSnap = await FirebaseFirestore.instance
          .collection('residents')
          .where('flatNumber', isEqualTo: flatNumber)
          .limit(1)
          .get();

      // Also try by document ID (in case doc ID == flatNumber)
      DocumentSnapshot? residentDoc;
      if (residentSnap.docs.isEmpty) {
        residentDoc = await FirebaseFirestore.instance
            .collection('residents')
            .doc(flatNumber)
            .get();
        if (!residentDoc.exists) {
          debugPrint('⚠️ No resident found for flat $flatNumber');
          return;
        }
      } else {
        residentDoc = residentSnap.docs.first;
      }

      final residentData = residentDoc.data() as Map<String, dynamic>?;
      final String? token = residentData?['fcmToken'] as String?;

      if (token == null || token.isEmpty) {
        debugPrint('⚠️ No FCM token for flat $flatNumber — resident not logged in');
        return;
      }

      // 2. Send push notification
      await sendPushToToken(
        fcmToken: token,
        title: '🚚 Delivery at Gate',
        body: '$company delivery arrived for Flat $flatNumber. Approve or deny?',
        data: {
          'type': 'delivery_request',
          'approvalId': approvalDocId,
          'flatNumber': flatNumber,
          'company': company,
        },
      );

      // 3. Also log to alerts collection
      await FirebaseFirestore.instance.collection('alerts').add({
        'type': 'DELIVERY_REQUEST',
        'targetFlat': flatNumber,
        'company': company,
        'guardId': guardId,
        'approvalId': approvalDocId,
        'message': '$company delivery arrived. Approve or deny?',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Resident notified for flat $flatNumber');
    } catch (e) {
      debugPrint('❌ Error notifying resident: $e');
    }
  }

  // ── Send notification to guard when resident approves/rejects ─────────────
  Future<void> notifyGuardOfDecision({
    required String guardId,
    required String flatNumber,
    required String company,
    required bool approved,
  }) async {
    try {
      // Fetch guard's FCM token
      QuerySnapshot guardSnap = await FirebaseFirestore.instance
          .collection('guards')
          .where('guardId', isEqualTo: guardId)
          .limit(1)
          .get();

      DocumentSnapshot? guardDoc;
      if (guardSnap.docs.isEmpty) {
        guardDoc = await FirebaseFirestore.instance
            .collection('guards')
            .doc(guardId)
            .get();
        if (!guardDoc.exists) {
          debugPrint('⚠️ Guard $guardId not found');
          return;
        }
      } else {
        guardDoc = guardSnap.docs.first;
      }

      final guardData = guardDoc.data() as Map<String, dynamic>?;
      final String? token = guardData?['fcmToken'] as String?;

      if (token == null || token.isEmpty) {
        debugPrint('⚠️ No FCM token for guard $guardId');
        return;
      }

      final String status = approved ? '✅ APPROVED' : '🚫 DENIED';
      final String emoji = approved ? '✅' : '🚫';

      await sendPushToToken(
        fcmToken: token,
        title: '$emoji Flat $flatNumber has responded',
        body: '$company delivery $status by Flat $flatNumber.',
        data: {
          'type': 'delivery_decision',
          'guardId': guardId,
          'flatNumber': flatNumber,
          'company': company,
          'approved': approved.toString(),
        },
      );

      debugPrint('✅ Guard $guardId notified of decision');
    } catch (e) {
      debugPrint('❌ Error notifying guard: $e');
    }
  }

  // ── Send vehicle entry alert to resident ──────────────────────────────────
  Future<void> notifyResidentOfVehicleEntry({
    required String flatNumber,
    required String plateNumber,
    required String type, // ENTRY or EXIT
  }) async {
    try {
      final DocumentSnapshot residentDoc = await FirebaseFirestore.instance
          .collection('residents')
          .doc(flatNumber)
          .get();

      if (!residentDoc.exists) return;

      final data = residentDoc.data() as Map<String, dynamic>?;
      final String? token = data?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;

      final String emoji = type == 'ENTRY' ? '🚗' : '🏁';
      await sendPushToToken(
        fcmToken: token,
        title: '$emoji Vehicle ${type == 'ENTRY' ? 'Entered' : 'Exited'}',
        body: 'Your vehicle $plateNumber has ${type == 'ENTRY' ? 'entered' : 'exited'} the society.',
        data: {
          'type': 'vehicle_movement',
          'plateNumber': plateNumber,
          'movementType': type,
          'flatNumber': flatNumber,
        },
      );

      // Log to alerts
      await FirebaseFirestore.instance.collection('alerts').add({
        'type': 'VEHICLE_$type',
        'plateNumber': plateNumber,
        'targetFlat': flatNumber,
        'message': 'Vehicle $plateNumber ${type == 'ENTRY' ? 'entered' : 'exited'} the gate.',
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('❌ Error sending vehicle alert: $e');
    }
  }
}
