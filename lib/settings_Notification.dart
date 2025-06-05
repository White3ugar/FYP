import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

class NotificationManagerPage extends StatefulWidget {
 const NotificationManagerPage({super.key});

  @override
  State<NotificationManagerPage> createState() => _NotificationManagerPageState();
}

class _NotificationManagerPageState extends State<NotificationManagerPage> {
  final logger = Logger();
  bool _isLoading = true;
  bool _allowNotification = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      logger.w("⚠️ User not logged in; cannot load notification preference");
      return;
    }

    final docSnapshot = await FirebaseFirestore.instance
        .collection('notifications')
        .doc(user.uid)
        .get();

    setState(() {
      _allowNotification = docSnapshot.data()?['allowNotification'] ?? false;
      _isLoading = false;
    });
  }

  Future<void> _updateNotificationPreference(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      logger.w("⚠️ User not logged in; cannot update notification preference");
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(user.uid)
          .set({'allowNotification': value}, SetOptions(merge: true));

      logger.i("✅ Notification preference updated to $value");
      setState(() {
        _allowNotification = value;
      });
    } catch (e) {
      logger.e("❌ Failed to update notification preference: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notification Settings"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(top: 16.0), // Add padding here
              child: ListTile(
                title: const Text("Notification"),
                trailing: Switch(
                  value: _allowNotification,
                  onChanged: _updateNotificationPreference,
                  activeColor: const Color.fromARGB(255, 165, 35, 226),
                ),
              ),
            ),
    );
  }
}