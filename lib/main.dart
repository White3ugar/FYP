import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
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
import 'package:supabase_flutter/supabase_flutter.dart';
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
  loggerr.i("📌 callbackDispatcher initialized");

  Workmanager().executeTask((taskName, inputData) async {
    loggerr.i('Workmanager background task triggered: $taskName');

    await Firebase.initializeApp();
    final firestore = FirebaseFirestore.instance;
    final prefs = await SharedPreferences.getInstance();

    final uid = inputData?['uid'] as String?;

    loggerr.i('🔍 UID from inputData: $uid');

    if (uid == null || uid.isEmpty) {
      loggerr.w('⚠️ No UID provided in inputData. Skipping task.');
      return true;
    }

    switch (taskName) {
      case 'checkBudgetThresholds':
        await checkBudgetThresholds(firestore, prefs, uid, loggerr);
        break;

      case 'checkRecurringTransactions':
        await checkAndRepeatTransactions(firestore, uid, loggerr);
        break;

      case 'checkExpiredBudgets':
        await updateExpiredBudgetStatuses(firestore, uid, loggerr);
        break;

      default:
        loggerr.w('⚠️ Unknown task name: $taskName');
    }

    return true;
  });
}

Future<void> checkBudgetThresholds(FirebaseFirestore firestore, SharedPreferences prefs, String uid, Logger loggerr) async {
  const budgetTypes = ['Daily', 'Weekly', 'Monthly'];

  for (final type in budgetTypes) {
    loggerr.i('🔍 Checking budget type: $type');
    final budgetSnapshots = await firestore
        .collection('budget_plans')
        .doc(uid)
        .collection(type)
        .get();

    for (final budgetDoc in budgetSnapshots.docs) {
      final docData = budgetDoc.data();
      final String? status = docData['budgetStatus'];

      if (status != 'Active') {
        loggerr.i('⏩ Skipping budget plan "${docData['budgetPlanName']}" because status is "$status"');
        continue;
      }

      final budgetPlanName = docData['budgetPlanName'];
      final contents = await budgetDoc.reference.collection('budget_contents').get();

      for (final categoryDoc in contents.docs) {
        final data = categoryDoc.data();
        final double amount = data['Amount']?.toDouble() ?? 0;
        final double spent = data['Spent']?.toDouble() ?? 0;
        final String category = data['Category'] ?? '';
        final double threshold = amount * 0.8;

        final flagKey = '${uid}_$type${budgetDoc.id}_${categoryDoc.id}_notified';

        if (spent >= threshold) {
          final alreadyNotified = prefs.getBool(flagKey) ?? false;
          loggerr.i('🔍 $category | Spent: $spent / $amount | Flag: $alreadyNotified');

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
          await prefs.setBool(flagKey, false); // Reset if below 80%
        }
      }
    }
  }
}

Future<void> checkAndRepeatTransactions(FirebaseFirestore firestore, String uid, Logger logger) async {
  logger.i('🔍 Checking for recurring transactions for user: $uid');
  final today = DateTime.now();
  final oriDate = today;

  try {
    final incomeRecurringSnapshot = await firestore
        .collection('incomes')
        .doc(uid)
        .collection('Recurring')
        .get();

    final expenseRecurringSnapshot = await firestore
        .collection('expenses')
        .doc(uid)
        .collection('Recurring')
        .get();

    final combinedDocs = [
      ...incomeRecurringSnapshot.docs.map((doc) => {'doc': doc, 'type': 'incomes'}),
      ...expenseRecurringSnapshot.docs.map((doc) => {'doc': doc, 'type': 'expenses'}),
    ];

    for (var entry in combinedDocs) {
      final doc = entry['doc'] as QueryDocumentSnapshot;
      final type = entry['type'] as String;
      final data = doc.data() as Map<String, dynamic>;

      final repeatType = data['repeat'];
      final lastRepeated = (data['lastRepeated'] as Timestamp?)?.toDate();
      if (repeatType == null || lastRepeated == null || repeatType == 'None') continue;

      final daysDiff = today.difference(lastRepeated).inDays;
      for (int i = 1; i <= daysDiff; i++) {
        final repeatDate = lastRepeated.add(Duration(days: i));
        bool shouldRepeat = repeatType == 'Daily' ||
            (repeatType == 'Weekly' && i % 7 == 0) ||
            (repeatType == 'Monthly' &&
              (repeatDate.month != lastRepeated.month || repeatDate.year != lastRepeated.year));
        if (!shouldRepeat) continue;

        final amount = (data['amount'] ?? 0).toDouble();
        final category = data['category'];
        final desc = data['description'];
        final monthAbbr = _getMonthAbbreviation(repeatDate.month);
        final formattedDate = "${repeatDate.day.toString().padLeft(2, '0')}-${repeatDate.month.toString().padLeft(2, '0')}-${repeatDate.year}";

        final newTx = {
          'userId': uid,
          'amount': amount,
          'category': category,
          'description': desc,
          'repeat': repeatType,
          'date': repeatDate,
          'lastRepeated': oriDate,
        };

        if (type == 'expenses') {
          newTx['budgetPlans'] = List<String>.from(data['budgetPlans'] ?? []);
        }

        final txRef = firestore
            .collection(type)
            .doc(uid)
            .collection('Months')
            .doc(monthAbbr)
            .collection(formattedDate);

        await txRef.add(newTx);

        // Update monthly total + availableDates
        final monthlyRef = firestore.collection(type).doc(uid).collection('Months').doc(monthAbbr);
        final monthlySnap = await monthlyRef.get();
        final totalKey = type == 'incomes' ? 'Monthly_Income' : 'Monthly_Expense';

        double currentTotal = 0;
        List<String> availableDates = [];

        if (monthlySnap.exists) {
          final monthlyData = monthlySnap.data() as Map<String, dynamic>;
          currentTotal = (monthlyData[totalKey] ?? 0).toDouble();
          availableDates = List<String>.from(monthlyData['availableDates'] ?? []);
        }

        if (!availableDates.contains(formattedDate)) {
          availableDates.add(formattedDate);
        }

        await monthlyRef.set({
          totalKey: currentTotal + amount,
          'availableDates': availableDates,
        }, SetOptions(merge: true));

        // Update lastRepeated in recurring entry
        await doc.reference.update({'lastRepeated': repeatDate});
      }
    }

    logger.i('✔️ Recurring transactions checked and updated for user: $uid');
  } catch (e) {
    logger.e('❌ Error in recurring transaction checker: $e');
  }
}

// Helper function to get month name abbreviation
String _getMonthAbbreviation(int monthNumber) {
  const monthAbbreviations = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return monthAbbreviations[monthNumber - 1];
}

Future<void> updateExpiredBudgetStatuses(
  FirebaseFirestore firestore,
  String uid,
  Logger logger,
) async {
  logger.i("📅 Checking for expired budgets for user: $uid");
  final now = DateTime.now();
  final types = ['Daily', 'Weekly', 'Monthly'];

  for (final type in types) {
    final querySnapshot = await firestore
        .collection('budget_plans')
        .doc(uid)
        .collection(type)
        .get();

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final endTimestamp = data['budgetPlanEnd'];
      final currentStatus = data['budgetStatus'];

      if (endTimestamp == null ||
          currentStatus == 'Expired' ||
          currentStatus == 'Archived') continue;

      final endDate = (endTimestamp as Timestamp).toDate();

      if (now.isAfter(endDate)) {
        logger.i("📅 Expiring budget in $type: ${doc.id}");
        await doc.reference.update({'budgetStatus': 'Expired'});
      }
    }
  }
}

Future<void> saveNotificationPreference() async {
  final user = fb_auth.FirebaseAuth.instance.currentUser;
  if (user == null) {
    Logger().w("⚠️ Cannot save notification preference - user not logged in.");
    return;
  }

  final docRef = FirebaseFirestore.instance.collection('notifications').doc(user.uid);

  try {
    final docSnapshot = await docRef.get();

    // Check if allowNotification is already explicitly set to true or false
    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null && data.containsKey('allowNotification')) {
        Logger().i("🔕 Notification preference already set to ${data['allowNotification']} — skipping update.");
        return;
      }
    }

    // Set allowNotification to true (only if it's not explicitly set)
    await docRef.set({'allowNotification': true}, SetOptions(merge: true));
    Logger().i("✅ Notification preference set to true for user: ${user.uid}");
  } catch (e) {
    Logger().e("❌ Failed to save notification preference: $e");
  }
}

void main() async {
  final logger = Logger();
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Request permission
  await requestNotificationPermission();

  // Initialize local notifications
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://dnppguuvvexrmhzczsbs.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRucHBndXV2dmV4cm1oemN6c2JzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDkxNjM5MzAsImV4cCI6MjA2NDczOTkzMH0.sCjgy0KvLE9NTQaLVfDsOxQzOc1PpddGyrgPz1mwV9g',
  );

  // Initialize Workmanager
  logger.i("📌 Initializing Workmanager");
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // Delay task registration until currentUser is available
  fb_auth.FirebaseAuth.instance.authStateChanges().firstWhere((user) => user != null).then((user) async {
    if (user == null) {
      logger.w('⚠️ User is null, cannot register background tasks.');
      return;
    }
    final uid = user.uid;
    logger.i('✅ UID ready: $uid');

    saveNotificationPreference();

    // Register recurring task
    await Workmanager().registerPeriodicTask(
      "repeatTransactionsTask",
      "checkRecurringTransactions",
      frequency: const Duration(minutes: 15),
      inputData: {'uid': uid},
    );

    // Register expired budget checking task
    await Workmanager().registerPeriodicTask(
      "checkExpiredBudgetsTask",
      "checkExpiredBudgets",
      frequency: const Duration(minutes: 15),
      inputData: {'uid': uid},
    );

    // Check allowNotification and register threshold task
    final docRef = FirebaseFirestore.instance.collection('notifications').doc(uid);
    final docSnapshot = await docRef.get();
    final allowNotification = docSnapshot.data()?['allowNotification'];

    if (allowNotification == true) {
      logger.i("🔔 Registering budget threshold checker");
      await Workmanager().registerPeriodicTask(
        "checkBudgetTask",
        "checkBudgetThresholds",
        frequency: const Duration(hours: 1),
        inputData: {'uid': uid},
      );
    } else {
      logger.i("🔕 Notifications disabled.");
    }
  });

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
    final user = fb_auth.FirebaseAuth.instance.currentUser;

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
  final fb_auth.FirebaseAuth _auth = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _isLoading = false;

  Future<void> _signInWithEmail() async {
    try {
      fb_auth.UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      fb_auth.User? user = userCredential.user;
      if (user != null) {
        if (!mounted) return;

        if (user.emailVerified) {
          // ✅ Check if user preferences exist
          final userDetailsSnapshot = await _firestore.collection('users').doc(user.uid).get();
          final userData = userDetailsSnapshot.data();

          if (!mounted) return;

          setState(() {
            _isLoading = false;
          });

          if (userData != null && userData.containsKey('occupation')) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const UserPreferencesPage(fromPage: 'main'),
              ),
            );
          }
        } else {
          // ❌ Show alert if email is NOT verified
          _showAlertDialog("Email Not Verified", "Please verify your email before logging in");
        }
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      String errorMessage = "Login Failed. Please try again.";

      if (e.code == "wrong-password" || e.code == "invalid-credential") {
        errorMessage = "Wrong Password or Email Address";
      } else if (e.code == "user-not-found") {
        errorMessage = "No account found for this Email Address";
      } else if (e.code == "too-many-requests") {
        errorMessage = "Too many login attempts. Try again later.";
      }

      if (!mounted) return;

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
      'budgetStatus': 'Active',
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
    final fb_auth.AuthCredential credential = fb_auth.GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // **Step 4: Sign in to Firebase with the Google credentials**
    fb_auth.UserCredential userCredential = await _auth.signInWithCredential(credential);
    fb_auth.User? user = userCredential.user;

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

    // **Step 8: Save notification preference for the user**
    await saveNotificationPreference();

    // **Step 9: Navigate to appropriate page based on user preferences availability**
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.fromRGBO(255, 216, 218, 1), 
              Color.fromARGB(255, 241, 109, 231),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: screenHeight * 0.18),
                const Text(
                  'Sparx\nFinancial\nAssistance',
                  style: TextStyle(fontSize: 38,  color: Color.fromARGB(255, 165, 35, 226)),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Email field
                SizedBox(
                  width: 280,
                  height: 50,
                  child: TextField(
                    controller: _emailController,
                    textAlign: TextAlign.center, // Centers user input text
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(255, 165, 35, 226),
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                          width: 2.0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                        ),
                      ),
                    ),
                    textAlignVertical: TextAlignVertical.center,
                  ),
                ),

                const SizedBox(height: 20),

                // Password field
                SizedBox(
                  width: 280,
                  height: 50,
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    textAlign: TextAlign.center, // Center the input and hint text
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: const TextStyle(
                        color: Color.fromARGB(255, 165, 35, 226),
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                          width: 2.0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: const BorderSide(
                          color: Color.fromARGB(255, 165, 35, 226),
                        ),
                      ),
                    ),
                    textAlignVertical: TextAlignVertical.center,
                  ),
                ),

                const SizedBox(height: 30),

                // Login button
                SizedBox(
                  width: 100, 
                  height: 40, 
                  child: ElevatedButton(
                    onPressed: _signInWithEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color.fromARGB(255, 165, 35, 226),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: EdgeInsets.zero, 
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 50),

                const Row(
                  children: [
                    Expanded(
                      child: Divider(
                        thickness: 1,
                        color: Colors.white, 
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Or Continue With',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color.fromARGB(255, 165, 35, 226), 
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        thickness: 1,
                        color: Colors.white, 
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                // Google Sign-In button
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.white,)
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

                const SizedBox(height: 70),

                const Text(
                  'First Time User?',
                  style: TextStyle(color: Color.fromARGB(255, 165, 35, 226),fontWeight: FontWeight.bold),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const RegisterPage(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                  child: const Text(
                    'Register Now!',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),

                SizedBox(height: screenHeight * 0.05),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
