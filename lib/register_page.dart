import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

        // **Step 5: Now store user data in Firestore once the email is verified**
        await _firestore.collection('users').doc(user!.uid).set({
          'email': user.email,
          'username': _usernameController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // **Step 6: Create categories for Transaction Categories (Income and Expense)**
        List<String> incomeCategories = ['Deposit', 'Salary', 'Investment'];
        List<String> expenseCategories = [
          'Food', 'Drink', 'Transport', 'Entertainment', 'Sport', 'Stationary',
          'Medical', 'Electronic Device', 'Online Shopping'
        ];

        // Reference to the Categories collection
        CollectionReference categoriesRef = _firestore.collection('Categories');
        DocumentReference userCategoriesRef = categoriesRef.doc(user.uid);

        await userCategoriesRef.set({'userID': user.uid});

        CollectionReference transactionCategoriesRef = userCategoriesRef.collection('Transaction Categories');
        await transactionCategoriesRef.doc('Income categories').set({'categoryNames': incomeCategories});
        await transactionCategoriesRef.doc('Expense categories').set({'categoryNames': expenseCategories});

        // **Step 7: Create default budget plan for the user**
        CollectionReference budgetsRef = _firestore.collection('budget_plans');
        await budgetsRef.doc(user.uid).set({
          'userID': user.uid,
          'budgetPlanName': 'Budget Plan 1',
        });

        setState(() {
          _statusMessage = "Registration complete! Redirecting...";
        });

        // Step 8: Redirect to login page after a short delay
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pushReplacementNamed(context, "/");
      }
    } catch (e) {
      setState(() {
        _isLoading = false; // Set loading to false if there was an error
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to register: ${e.toString()}")),
      );
    }
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
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: screenHeight * 0.12),
            Text('Register Now!',
                style: TextStyle(fontSize: screenWidth * 0.07, fontWeight: FontWeight.bold)),
            SizedBox(height: screenHeight * 0.04),

            // Username
            Text('Username',
                style: TextStyle(fontSize: screenWidth * 0.04, fontWeight: FontWeight.w500)),
            SizedBox(height: screenHeight * 0.008),
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                hintText: 'Username123',
                contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.012, horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(screenWidth * 0.02)),
              ),
            ),
            SizedBox(height: screenHeight * 0.02),

            // Email Address
            Text('Email Address',
                style: TextStyle(fontSize: screenWidth * 0.04, fontWeight: FontWeight.w500)),
            SizedBox(height: screenHeight * 0.008),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: 'example@email.com',
                contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.012, horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(screenWidth * 0.02)),
              ),
            ),
            SizedBox(height: screenHeight * 0.02),

            // Password
            Text('Password',
                style: TextStyle(fontSize: screenWidth * 0.04, fontWeight: FontWeight.w500)),
            SizedBox(height: screenHeight * 0.008),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Enter your password',
                contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.012, horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(screenWidth * 0.02)),
              ),
              onChanged: (value) => _validatePasswords(),
            ),
            SizedBox(height: screenHeight * 0.02),

            // Confirm Password
            Text('Confirm Password',
                style: TextStyle(fontSize: screenWidth * 0.04, fontWeight: FontWeight.w500)),
            SizedBox(height: screenHeight * 0.008),
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Re-enter your password',
                contentPadding: EdgeInsets.symmetric(vertical: screenHeight * 0.012, horizontal: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(screenWidth * 0.02)),
                errorText: _errorMessage,
              ),
              onChanged: (value) => _validatePasswords(),
            ),
            SizedBox(height: screenHeight * 0.05),

            // Register Button
            Center(
              child: Column(
                children: [
                  _isLoading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _registerUser,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: screenHeight * 0.015, horizontal: screenWidth * 0.2),
                      ),
                      child: Text('Verify Email',
                          style: TextStyle(
                              fontSize: screenWidth * 0.045,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold)),
                    ),
                  if (_statusMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: screenWidth * 0.04,
                          color: Colors.grey[700],
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
    );
  }
}
