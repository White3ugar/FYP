import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? username;
  String? email;
  bool isEmailPasswordUser = false;
  bool isEditingUsername = false;

  final TextEditingController _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    User? user = _auth.currentUser;

    if (user != null) {
      email = user.email;

      // Check sign-in method
      isEmailPasswordUser = user.providerData.any((info) => info.providerId == 'password');

      // Fetch user document from Firestore
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();
      setState(() {
        username = userDoc['username'] ?? 'Unknown';
      });
    }
  }

  Future<void> updateUsername() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'username': _usernameController.text,
      });

      if (!mounted) return;

      setState(() {
        username = _usernameController.text;
        isEditingUsername = false;
      });

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color.fromARGB(255, 165, 35, 226), // purple background
          title: const Text(
            'Success',
            style: TextStyle(color: Colors.white), // text color to contrast background
          ),
          content: const Text(
            'Username has been updated.',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'OK',
                style: TextStyle(color: Colors.white), // button text color white
              ),
            ),
          ],
        ),
      );
    }
  }

  void changePassword() async {
    await _auth.sendPasswordResetEmail(email: email!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Sent'),
        content: const Text('Password reset email sent. Please check your inbox.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget buildLabeledInfo({
    required IconData icon,
    required String label,
    required String value,
    bool isEditable = false,
    VoidCallback? onEdit,
    TextEditingController? controller,
    VoidCallback? onSave,
    bool isEditing = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0), 
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: const Color.fromARGB(255, 165, 35, 226)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    //color: Color.fromARGB(255, 165, 35, 226),
                  ),
                ),
                const SizedBox(height: 4),
                isEditing && controller != null
                    ? TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      )
                    : Text(value, style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          if (isEditable)
            IconButton(
              icon: Icon(isEditing ? Icons.check : Icons.edit),
              color: const Color.fromARGB(255, 165, 35, 226),
              onPressed: isEditing ? onSave : onEdit,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (username == null || email == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color.fromARGB(255, 165, 35, 226),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromARGB(255, 165, 35, 226)),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text(
              "User Profile",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 165, 35, 226),
              ),
            ),
            const SizedBox(height: 24),

            // User Info
            buildLabeledInfo(
              icon: Icons.person,
              label: 'Username',
              value: username!,
              isEditable: true,
              isEditing: isEditingUsername,
              controller: _usernameController,
              onEdit: () => setState(() => isEditingUsername = true),
              onSave: updateUsername,
            ),
            buildLabeledInfo(
              icon: Icons.email,
              label: 'Email',
              value: email!,
              isEditable: false,
            ),
            const SizedBox(height: 24),
            if (isEmailPasswordUser)
              Padding(
                padding: const EdgeInsets.only(left: 16.0, bottom: 12.0),
                child: ElevatedButton(
                  onPressed: () => _auth.sendPasswordResetEmail(email: email!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    textStyle: const TextStyle(fontSize: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("Change Password"),
                ),
              )
          ],
        ),
      ),
    );
  }
}