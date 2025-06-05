import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'home_page.dart';
import 'settings_page.dart';

class UserPreferencesPage extends StatefulWidget {
  final String fromPage;

  const UserPreferencesPage({super.key, required this.fromPage});

  @override
  State<UserPreferencesPage> createState() => _UserPreferencesPageState();
}

class _UserPreferencesPageState extends State<UserPreferencesPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers and variables
  final TextEditingController occupationController = TextEditingController();
  final TextEditingController financialGoalController = TextEditingController();
  String? incomeRange;
  String? financialGoal;
  String? financeMethod;
  String? spendingPriority;

  final List<String> incomeOptions = [
    "Below RM2,000",
    "RM2,000–RM5,000",
    "RM5,000–RM10,000",
    "Above RM10,000"
  ];

  final List<String> goalOptions = [
    "Saving for a house",
    "Clearing debt",
    "Building emergency fund",
    "Investing",
    "Saving for travel",
    "Retirement planning",
    "Buying a car",
    "Education or student loan repayment",
    "Starting a business",
    "Home renovation",
    "Saving for children’s education",
    "Building wealth",
    "Down payment for property",
    "Improving credit score",
    "Achieving financial independence"
  ];

  final List<String> methodOptions = [
    "Spreadsheet",
    "Mobile app",
    "Manual budgeting",
    "Not tracking yet"
  ];

  List<String> spendingOptions = [];
  bool isLoadingCategories = true;

  Future<void> savePreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);

    await userDoc.set({
      'occupation': occupationController.text.trim(),
      'incomeRange': incomeRange,
      'financialGoals': financialGoalController.text.trim(),
      'financeMethod': financeMethod,
      'spendingPriority': selectedSpendingPriorities,
    }, SetOptions(merge: true));

    if(!mounted) return;

    if (widget.fromPage == 'main') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    } else if (widget.fromPage == 'setting') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SettingsPage()),
      );
    }
  }

  Future<void> fetchSpendingOptions() async {
    final Logger logger = Logger();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance
        .collection('Categories')
        .doc(user.uid)
        .collection('Transaction Categories')
        .doc('Expense categories');

    logger.i("Fetching spending options for user: ${user.uid}");

    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      final List<dynamic>? categoryArray = data?['categoryNames'];

      if (categoryArray != null) {
        setState(() {
          spendingOptions = categoryArray
              .map((e) => e['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toList();
          isLoadingCategories = false;
        });
      }
    } else {
      setState(() {
        isLoadingCategories = false;
      });
    }
  }

  Future<void> fetchUserPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (docSnapshot.exists) {
      final data = docSnapshot.data();
      if (data != null) {
        setState(() {
          occupationController.text = data['occupation'] ?? '';
          incomeRange = data['incomeRange'];
          financialGoalController.text = data['financialGoals'] ?? '';
          financeMethod = data['financeMethod'];
          selectedSpendingPriorities =
              List<String>.from(data['spendingPriority'] ?? []);
        });
      }
    }
  }
  
  @override
  void initState() {
    super.initState();
    fetchSpendingOptions();
    fetchUserPreferences();
  }

  List<String> selectedSpendingPriorities = [];

void _showMultiSelectDialog(FormFieldState<List<String>> formFieldState) async {
  final List<String> tempSelected = List.from(selectedSpendingPriorities);

  final result = await showDialog<List<String>>(
  context: context,
  builder: (context) {
    return AlertDialog(
      title: const Text("Select up to 3 categories"),
      content: StatefulBuilder(
        builder: (BuildContext context, StateSetter setStateDialog) {
          return SingleChildScrollView(
            child: Column(
              children: spendingOptions.map((option) {
                final isSelected = tempSelected.contains(option);
                return CheckboxListTile(
                  title: Text(option),
                  value: isSelected,
                  onChanged: (selected) {
                    setStateDialog(() {
                      if (selected == true && !isSelected && tempSelected.length < 3) {
                        tempSelected.add(option);
                      } else if (selected == false && isSelected) {
                        tempSelected.remove(option);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context, selectedSpendingPriorities),
        ),
        TextButton(
          child: const Text("Done"),
          onPressed: () {
            Navigator.pop(context, tempSelected);
          },
        ),
      ],
    );
  },
);

  // If result is not null (meaning the user clicked 'Done')
  if (result != null) {
    setState(() {
      selectedSpendingPriorities = result;
      formFieldState.didChange(result);  // Update the FormField state with the new value
    });
  }
}

  Widget buildSpendingPrioritySelector() {
    return FormField<List<String>>(
      initialValue: selectedSpendingPriorities,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "Please select at least one category";
        }
        return null;
      },
      builder: (formFieldState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Which categories do you spend most?",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Color.fromARGB(255, 165, 35, 226),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showMultiSelectDialog(formFieldState),
              child: InputDecorator(
                decoration:  InputDecoration(
                  border:  const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2),
                  ),
                  contentPadding:  const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  errorText: formFieldState.errorText, // Displays error message if any
                ),
                child: Text(
                  selectedSpendingPriorities.isEmpty
                      ? "Select Categories"
                      : selectedSpendingPriorities.join(", "),
                  style: TextStyle(
                    color: selectedSpendingPriorities.isEmpty
                        ? Colors.grey[600]
                        : Colors.black,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final Logger logger = Logger();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.fromPage == 'setting'
          ? Colors.white
          : const Color.fromARGB(255, 239, 179, 236),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color.fromARGB(255, 165, 35, 226)),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      backgroundColor: widget.fromPage == 'setting'
        ? Colors.white
        : const Color.fromARGB(255, 239, 179, 236),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Title
              Text(
                widget.fromPage == 'setting'
                ? "Preferences"
                : "Let’s get to know your financial preferences",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 165, 35, 226),
                ),
              ),
              const SizedBox(height: 24),

              // Occupation
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "What is your occupation?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: screenHeight * 0.055,
                    child: TextFormField(
                      controller: occupationController,
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? "Please enter your occupation" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Income Range
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "What is your monthly income range?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: screenHeight * 0.055,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      ),
                      value: incomeRange,
                      items: incomeOptions
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (val) => setState(() => incomeRange = val),
                      validator: (value) => value == null ? "Please select your income range" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Financial Goal
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "What is your top financial goal?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: screenHeight * 0.055,
                    child: TextFormField(
                      controller: financialGoalController,
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? "Please enter your financial goal" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Finance Method
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "How do you currently manage your finances?",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: screenHeight * 0.055,
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2),
                        ),
                        contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      ),
                      value: financeMethod,
                      items: methodOptions
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (val) => setState(() => financeMethod = val),
                      validator: (value) => value == null ? "Please select a method" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Spending Priority (multi-select with loading state)
              isLoadingCategories
                  ? Builder(
                      builder: (context) {
                        logger.i("loading now");
                        return const Center(child: CircularProgressIndicator());
                      },
                    )
                  : buildSpendingPrioritySelector(),
              const SizedBox(height: 45),

             Center(
              child: SizedBox(
                width: 250,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      savePreferences();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                  ),
                  child: const Text(
                    "Save Preferences",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            )
            ],
          ),
        ),
      ),
    );
  }
}