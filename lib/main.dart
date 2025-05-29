import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart'; 
import 'register_page.dart';
import 'notification.dart'; 
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io'; // Import dart:io for platform checks


Future<void> requestNotificationPermission() async {
  if (Platform.isAndroid) {
    if (await Permission.notification.isDenied ||
        await Permission.notification.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  final loggerr = Logger();
  loggerr.i("📌 notificationSender initialized");

  Workmanager().executeTask((taskName, inputData) async {
    loggerr.i('✅ Workmanager background task triggered: $taskName');

    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;
    final prefs = await SharedPreferences.getInstance();

    final uid = inputData?['uid'] as String?;

    loggerr.i('🔍 UID from inputData: $uid');

    if (uid == null || uid.isEmpty) {
      loggerr.w('⚠️ No UID provided in inputData. Skipping task.');
      return true;
    }

    const budgetTypes = ['Daily', 'Weekly', 'Monthly'];

    for (final type in budgetTypes) {
      loggerr.i('Testing 1');
      final budgetSnapshots = await firestore
          .collection('budget_plans')
          .doc(uid)
          .collection(type)
          .get();

      for (final budgetDoc in budgetSnapshots.docs) {
        loggerr.i('Testing 2');

        final docData = budgetDoc.data();
        final String? status = docData['budgetStatus'];

        if (status != 'Active') {
          loggerr.i('⏩ Skipping budget plan "${docData['budgetPlanName']}" because status is "$status"');
          continue; // Skip this document
        }

        final budgetPlanName = docData['budgetPlanName'];
        final contents = await budgetDoc.reference
            .collection('budget_contents')
            .get();

        for (final categoryDoc in contents.docs) {
          loggerr.i('Testing 3');
          final data = categoryDoc.data();
          final double amount = data['Amount']?.toDouble() ?? 0;
          final double spent = data['Spent']?.toDouble() ?? 0;
          final String category = data['Category'] ?? '';
          final double threshold = amount * 0.8;

          final flagKey = '${uid}_$type${budgetDoc.id}_${categoryDoc.id}_notified';

          // For debugging: force flag to false
          //await prefs.setBool(flagKey, false);

          if (spent >= threshold) {
            loggerr.i('Spent more than threshold, triggering notification sending');
            final alreadyNotified = prefs.getBool(flagKey) ?? false;
            loggerr.i('🔍 Notification flag for $category [$flagKey] = $alreadyNotified');

            if (!alreadyNotified) {
              final remaining = amount - spent;
              await showNotification(
                title: "Budget Alert",
                body:
                    'You have spent 80% for $category category under $type budget "$budgetPlanName", the remaining amount is RM ${remaining.toStringAsFixed(2)}',
              );

              loggerr.i('📣 Notification sent for $category in $type budget: $budgetPlanName');
              await prefs.setBool(flagKey, true);
            }
          } else {
            // Reset notification flag if spent goes below 80% again
            await prefs.setBool(flagKey, false);
          }
        }
      }
    }

    return true;
  });
}

void main() async {
  final logger = Logger();
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp();

  // 2. Request notification permission for android > 13
  await requestNotificationPermission();

  // 3. Initialize WorkManager (for background task)
  logger.i("📌 Initializing Workmanager for notificationSender function");
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Register one-off task for immediate execution (for debug)
  // Workmanager().registerOneOffTask(
  //   "testBudgetTask",
  //   "testBudgetTask",
  //   inputData: {
  //     'uid': FirebaseAuth.instance.currentUser?.uid ?? '',
  //   },
  // );

  // 4. Register periodic background task
  final uid = FirebaseAuth.instance.currentUser?.uid;
  logger.i('🔍 Current user UID at line 139: $uid');

  if (uid != null && uid.isNotEmpty) {
    Workmanager().registerPeriodicTask(
      "checkBudgetTask",
      "checkBudgetTask",
      frequency: const Duration(hours: 1),
      inputData: {'uid': uid},
    );
  } else {
    logger.w('User not logged in; cannot register periodic task with UID');
  }

  // 5. Initialize local notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 6. Launch your app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sparx Financial Assistance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(), // Widget to check auth
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      return const HomePage(); // ✅ Already logged in
    } else {
      return const LoginPage(); // ❌ Not logged in yet
    }
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  LoginPageState createState() => LoginPageState();
}

class LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;

  Future<void> _signInWithEmail() async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user != null) {
        if (user.emailVerified) {
          // ✅ Navigate to HomePage if email is verified
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        } else {
          // ❌ Show alert if email is NOT verified
          _showAlertDialog("Email Not Verified", "Please verify your email before logging in");
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Login Failed. Please try again.";

      if (e.code == "wrong-password" || e.code == "invalid-credential") {
        errorMessage = "Wrong Password or Email Address";
      } else if (e.code == "user-not-found") {
        errorMessage = "No account found for this Email Address";
      } else if (e.code == "too-many-requests") {
        errorMessage = "Too many login attempts. Try again later.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      setState(() {
      _isLoading = true;
    });

    // **Step 1: Trigger the Google Sign-In flow**
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // **Step 2: Get the Google authentication details**
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    // **Step 3: Create a new credential using the authentication tokens**
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // **Step 4: Sign in to Firebase with the Google credentials**
    UserCredential userCredential = await _auth.signInWithCredential(credential);
    User? user = userCredential.user;

    if (user == null) {
      throw Exception("User creation failed.");
    }

    // **Step 5: Save the user info into Firestore only if not exists**
    DocumentReference userDocRef = _firestore.collection('users').doc(user.uid);
    DocumentSnapshot userSnapshot = await userDocRef.get();

    if (!userSnapshot.exists) {
      await userDocRef.set({
        'email': user.email,
        'username': googleUser.displayName ?? "Unnamed",
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // **Step 6: Create default categories (Income & Expense) only if not exists**
    DocumentReference userCategoriesRef = _firestore.collection('Categories').doc(user.uid);
    DocumentSnapshot categoriesSnapshot = await userCategoriesRef.get();

    if (!categoriesSnapshot.exists) {
      await userCategoriesRef.set({'userID': user.uid});

      CollectionReference transactionCategoriesRef = userCategoriesRef.collection('Transaction Categories');

      // Define income and expense categories with icon paths
      List<Map<String, String>> incomeCategories = [
        {'name': 'Deposit', 'icon': 'assets/icon/deposit.png'},
        {'name': 'Salary', 'icon': 'assets/icon/salary.png'},
        {'name': 'Invests', 'icon': 'assets/icon/invest.png'},
      ];

      List<Map<String, String>> expenseCategories = [
        {'name': 'Food', 'icon': 'assets/icon/food.png'},
        {'name': 'Drink', 'icon': 'assets/icon/drink.png'},
        {'name': 'Transport', 'icon': 'assets/icon/transport.png'},
        {'name': 'Loan', 'icon': 'assets/icon/loan.png'},
        {'name': 'Sport', 'icon': 'assets/icon/sport.png'},
        {'name': 'Education', 'icon': 'assets/icon/book.png'},
        {'name': 'Medical', 'icon': 'assets/icon/medical.png'},
        {'name': 'Electronics', 'icon': 'assets/icon/monitor.png'},
        {'name': 'Grocery', 'icon': 'assets/icon/grocery.png'},
      ];

      await transactionCategoriesRef.doc('Income categories').set({
        'categoryNames': incomeCategories,
      });

      await transactionCategoriesRef.doc('Expense categories').set({
        'categoryNames': expenseCategories,
      });
    }

    // **Step 7: Create a default budget plan only if not exists**
    final userId = user.uid;
    final userDocRef1 = _firestore.collection('budget_plans').doc(userId);

    // Ensure parent doc exists
    await userDocRef1.set({'userID': userId}, SetOptions(merge: true));

    // Define default budget contents
    Map<String, num> defaultBudgetContents = {
      'Grocery': 500,
      'Transport': 200,
      'Food': 150,
    };

    // Function to create a plan and add default budget contents
    Future<void> createPlanWithContents(CollectionReference planRef, String name, Duration duration) async {
      DateTime now = DateTime.now();

      final planDocRef = await planRef.add({
        'userID': userId,
        'budgetPlanName': name,
        'budgetPlanStart': now,
        'budgetPlanEnd': now.add(duration),
      });

      final contentsRef = planDocRef.collection('budget_contents');

      for (var entry in defaultBudgetContents.entries) {
        await contentsRef.add({
          'Category': entry.key,
          'Amount': entry.value,
          'Spent': 0,
          'Remaining': entry.value,
        });
      }
    }

    // DAILY PLAN
    final dailyPlansRef = userDocRef1.collection('Daily');
    final dailySnapshot = await dailyPlansRef.limit(1).get();
    if (dailySnapshot.docs.isEmpty) {
      await createPlanWithContents(dailyPlansRef, 'My First Daily Budget', const Duration(days: 1));
    }

    // WEEKLY PLAN
    final weeklyPlansRef = userDocRef1.collection('Weekly');
    final weeklySnapshot = await weeklyPlansRef.limit(1).get();
    if (weeklySnapshot.docs.isEmpty) {
      await createPlanWithContents(weeklyPlansRef, 'My First Weekly Budget', const Duration(days: 7));
    }

    // MONTHLY PLAN
    final monthlyPlansRef = userDocRef1.collection('Monthly');
    final monthlySnapshot = await monthlyPlansRef.limit(1).get();
    if (monthlySnapshot.docs.isEmpty) {
      await createPlanWithContents(monthlyPlansRef, 'My First Monthly Budget', const Duration(days: 30));
    }

    setState(() {
      _isLoading = false;
    });

    // **Step 8: Navigate to the HomePage after successful sign-in**
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomePage()),
    );
    } catch (e) {
      print("Google Sign-In error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google Sign-In failed: ${e.toString()}")),
      );
    }
  }

  void _showAlertDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView( // Enables scrolling on small screens
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: screenHeight * 0.25), // Dynamic top spacing (10% of screen height)              
              const Text(
                'Sparx Financial Assistance',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Welcome',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Email field
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Password field
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _signInWithEmail,
                child: const Text('Login'),
              ),

              const SizedBox(height: 50),
              const Row(
                children: [
                  Expanded(child: Divider(thickness: 1)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Or Continue With',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(child: Divider(thickness: 1)),
                ],
              ),

              const SizedBox(height: 25),
              // Google Sign-In button
              _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _signInWithGoogle,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(12.0),
                      shape: const CircleBorder(),
                      backgroundColor: Colors.white,
                      elevation: 3,
                    ),
                    child: Image.asset(
                      'assets/icon/google.png',
                      height: 30,
                      width: 30,
                    ),
                  ),

              const SizedBox(height: 80),
              const Text('First Time User?'),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterPage()),
                  );
                },
                child: const Text('Register Now!'),
              ),
              SizedBox(height: screenHeight * 0.05), // Bottom spacing
            ],
          ),
        ),
      ),
    );
  }
}
