import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'home_page.dart'; 
import 'register_page.dart';
import 'notification.dart'; 
import 'userPreference_page.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

Future<void> saveNotificationPreference() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    Logger().w("⚠️ Cannot save notification preference - user not logged in.");
    return;
  }

  final docRef = FirebaseFirestore.instance.collection('notifications').doc(user.uid);

  try {
    final docSnapshot = await docRef.get();

    // Check if allowNotification is explicitly false
    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null && data['allowNotification'] == false) {
        Logger().i("🔕 Notification preference is explicitly false — skipping update.");
        return;
      }
    }

    // Set allowNotification to true (or create it)
    await docRef.set({'allowNotification': true}, SetOptions(merge: true));
    Logger().i("✅ Notification preference set to true for user: ${user.uid}");
  } catch (e) {
    Logger().e("❌ Failed to save notification preference: $e");
  }
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

  // 4. Register periodic background task
  final uid = FirebaseAuth.instance.currentUser?.uid;
  logger.i('🔍 Current user UID at line 139: $uid');

  if (uid != null && uid.isNotEmpty) {
    final docRef = FirebaseFirestore.instance.collection('notifications').doc(uid);

    try {
      // Check if the user has allowed notifications
      final docSnapshot = await docRef.get();
      final allowNotification = docSnapshot.data()?['allowNotification'];

      if (allowNotification == true) {
        logger.i("🔔 Notifications allowed — registering background task");

        Workmanager().registerPeriodicTask(
          "checkBudgetTask",
          "checkBudgetTask",
          frequency: const Duration(hours: 1),
          inputData: {'uid': uid},
        );
      } else {
        logger.i("🔕 Notifications are disabled — skipping background task registration");
      }
    } catch (e) {
      logger.e("❌ Error reading notification preferences: $e");
    }
  } else {
    logger.w('⚠️ User not logged in; cannot register periodic task');
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

  Future<void> createPlanWithContents({
    required CollectionReference planRef,
    required String name,
    required Duration duration,
    required String userId,
  }) async {
    DateTime now = DateTime.now();

    final planDocRef = await planRef.add({
      'userID': userId,
      'budgetPlanName': name,
      'budgetPlanStart': now,
      'budgetPlanEnd': now.add(duration),
    });

    final contentsRef = planDocRef.collection('budget_contents');

    Map<String, num> defaultBudgetContents = {
      'Grocery': 500,
      'Transport': 200,
      'Food': 150,
    };

    for (var entry in defaultBudgetContents.entries) {
      await contentsRef.add({
        'Category': entry.key,
        'Amount': entry.value,
        'Spent': 0,
        'Remaining': entry.value,
      });
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

    // DAILY PLAN
    final dailyPlansRef = userDocRef1.collection('Daily');
    final dailySnapshot = await dailyPlansRef.limit(1).get();
    if (dailySnapshot.docs.isEmpty) {
      await createPlanWithContents(
        planRef: dailyPlansRef,
        name: 'My First Daily Budget',
        duration: const Duration(days: 1),
        userId: userId,
      );
    }

    // WEEKLY PLAN
    final weeklyPlansRef = userDocRef1.collection('Weekly');
    final weeklySnapshot = await weeklyPlansRef.limit(1).get();
    if (weeklySnapshot.docs.isEmpty) {
      await createPlanWithContents(
        planRef: weeklyPlansRef,
        name: 'My First Weekly Budget',
        duration: const Duration(days: 7),
        userId: userId,
      );
    }

    // MONTHLY PLAN
    final monthlyPlansRef = userDocRef1.collection('Monthly');
    final monthlySnapshot = await monthlyPlansRef.limit(1).get();
    if (monthlySnapshot.docs.isEmpty) {
      await createPlanWithContents(
        planRef: monthlyPlansRef,
        name: 'My First Monthly Budget',
        duration: const Duration(days: 30),
        userId: userId,
      );
    }

    setState(() {
      _isLoading = false;
    });

    // **Step 8: Navigate to appropriate page based on user preferences**
    final userDetailsSnapshot = await _firestore.collection('users').doc(user.uid).get();
    final userData = userDetailsSnapshot.data();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (userData != null && userData.containsKey('occupation')) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()), // Navigate to HomePage if occupation exists
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const UserPreferencesPage(fromPage: 'main')), // Navigate to UserPreferencesPage if occupation does not exist
      );
    }
    } catch (e) {
      final logger = Logger();
      logger.e("Google Sign-In error: $e");
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
        child: SingleChildScrollView( 
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: screenHeight * 0.25),      
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
              SizedBox(height: screenHeight * 0.05),
            ],
          ),
        ),
      ),
    );
  }
}
