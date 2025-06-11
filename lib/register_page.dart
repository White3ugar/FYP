import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';  
import 'userPreference_page.dart';
import 'package:logger/logger.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  RegisterPageState createState() => RegisterPageState();
}

class RegisterPageState extends State<RegisterPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  String? _errorMessage;
  String? _statusMessage;
  
  bool _isLoading = false; // Flag to track loading state

  void _validatePasswords() {
    setState(() {
      if (_passwordController.text != _confirmPasswordController.text) {
        _errorMessage = "Passwords do not match!";
      } else {
        _errorMessage = null;
      }
    });
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

  Future<void> _registerUser() async {
    setState(() {
      _isLoading = true; // Set loading state to true when email verification starts
      _statusMessage = "Creating account...";
    });

    try {
      // **Step 1: Create a new Firebase user**
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        // **Step 2: Send email verification immediately after user creation**
         setState(() {
          _statusMessage = "Sending verification email...";
        });
        await user.sendEmailVerification();

        // **Step 3: Notify the user to check their email**
        setState(() {
          _statusMessage = "Verification email sent! Waiting for email verification...";
        });

        // **Step 4: Wait for the email to be verified**
        while (user != null && user.emailVerified != true) {
          // Wait for email verification
          await Future.delayed(const Duration(seconds: 2));
          await user.reload();
          user = _auth.currentUser; // Refresh the user instance

          // Safe check to ensure the user object is still not null before proceeding
          if (user == null) {
            setState(() {
              _statusMessage = null;
              _isLoading = false;
            });
            return;
          }

          // Optional: Check if the email is verified here too
          if (user.emailVerified != true) {
            await Future.delayed(const Duration(seconds: 2)); // Delay for a while before rechecking
          }
        }

        setState(() {
          _statusMessage = "Email verified! Finalizing setup...";
        });

        // **Step 5: Save the user info into Firestore only if not exists**
        DocumentReference userDocRef = _firestore.collection('users').doc(user!.uid);
        DocumentSnapshot userSnapshot = await userDocRef.get();

        if (!userSnapshot.exists) {
          await userDocRef.set({
            'email': user.email,
            'username': _usernameController.text.trim(),
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


        // **Step 8: Save notification preference**
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
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const HomePage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        } else {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const UserPreferencesPage(fromPage: 'main'),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = "Failed to create user.";
        }); 
      }
    } catch (e) {
      setState(() {
        _isLoading = false; // Set loading to false if there was an error
      });

      if(!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to register: ${e.toString()}")),
      );
    }
  }

  Widget _buildInputField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    required double screenWidth,
    required double screenHeight,
    bool obscureText = false,
    String? errorText,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: screenWidth * 0.04,
            color: const Color.fromARGB(255, 165, 35, 226),
          ),
        ),
        SizedBox(height: screenHeight * 0.008),
        TextField(
          controller: controller,
          obscureText: obscureText,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: Colors.white,
            errorText: errorText,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 165, 35, 226),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(screenWidth * 0.03),
              borderSide: const BorderSide(
                color: Color.fromARGB(255, 165, 35, 226),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          ),
        ),
        SizedBox(height: screenHeight * 0.02),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenHeight = MediaQuery.of(context).size.height;
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromARGB(255, 165, 35, 226)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: screenHeight,
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
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: screenHeight * 0.12),
              Text(
                'Register Now!',
                style: TextStyle(
                  fontSize: screenWidth * 0.065,
                  fontWeight: FontWeight.bold,
                  color: const Color.fromARGB(255, 165, 35, 226),
                ),
              ),
              SizedBox(height: screenHeight * 0.04),

              _buildInputField(
                label: 'Username',
                controller: _usernameController,
                hintText: 'Username123',
                screenWidth: screenWidth,
                screenHeight: screenHeight,
              ),
              _buildInputField(
                label: 'Email Address',
                controller: _emailController,
                hintText: 'example@email.com',
                screenWidth: screenWidth,
                screenHeight: screenHeight,
              ),
              _buildInputField(
                label: 'Password',
                controller: _passwordController,
                hintText: 'Enter your password',
                obscureText: true,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                onChanged: (_) => _validatePasswords(),
              ),
              _buildInputField(
                label: 'Confirm Password',
                controller: _confirmPasswordController,
                hintText: 'Re-enter your password',
                obscureText: true,
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                errorText: _errorMessage,
                onChanged: (_) => _validatePasswords(),
              ),
              SizedBox(height: screenHeight * 0.05),

              Center(
                child: Column(
                  children: [
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.white,)
                        : TextButton(
                            onPressed: _registerUser,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: screenHeight * 0.015,
                                horizontal: screenWidth * 0.2,
                              ),
                            ),
                            child: Text(
                              'Verify Email',
                              style: TextStyle(
                                fontSize: screenWidth * 0.045,
                                color: const Color.fromARGB(255, 165, 35, 226),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                    if (_statusMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: screenWidth * 0.04,
                            color: Colors.grey[200],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: screenHeight * 0.05),
            ],
          ),
        ),
      ),
    );
  }
}
