import 'package:flutter/material.dart';
import 'ai_page.dart';
import 'budgeting_page.dart';
import 'dataVisual_page.dart';
import 'home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_datetime_picker_plus/flutter_datetime_picker_plus.dart' as picker;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

 Future<void> triggerBudgetBackgroundTask() async {
    final logger = Logger();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    logger.i("📌 expenseRecord page: triggerBudgetBackgroundTask called with UID: $uid");

    if (uid.isEmpty) {
      logger.w('⚠️ User not logged in; cannot register periodic task');
      return;
    }

    try {
      //Register a one-off task to check budget thresholds
       Workmanager().registerOneOffTask(
          "ExpenseRepeatTransactionsTask",
          "checkRecurringTransactions",
          inputData: {'uid': uid},
        );

      final docSnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .doc(uid)
          .get();

      final allowNotification = docSnapshot.data()?['allowNotification'];

      if (allowNotification == true) {
        logger.i('🔔 Notifications allowed — registering one-off task for UID: $uid');

        Workmanager().registerOneOffTask(
          "expenseBudgetTask",
          "checkBudgetThresholds",
          inputData: {'uid': uid},
        );
      } else {
        logger.i('🔕 Notifications are disabled — skipping one-off task registration');
      }
    } catch (e) {
      logger.e("❌ Error checking notification preferences: $e");
    }
  }

class ExpenseRecordPage extends StatefulWidget {
  const ExpenseRecordPage({super.key});

  @override
  State<ExpenseRecordPage> createState() => _ExpenseRecordPageState();
}

class _ExpenseRecordPageState extends State<ExpenseRecordPage> {
  final logger = Logger();
  bool isSubmitting = false;  // Flag to indicate if a transaction is being submitted
  bool isIncomeSelected = false;
  String selectedCategory = "";
  final TextEditingController amountController = TextEditingController(); 
  final TextEditingController descriptionController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  List<String> budgetPlans = []; // Store all budget plans for the user
  List<String> selectedBudgetPlans = []; // Store selected budget plans
  String selectedRepeat = 'None'; // Default repeat option
  final SupabaseClient supabase = Supabase.instance.client;
  XFile? _pickedImage;

  late Future<DocumentSnapshot> _incomeCategoriesFuture; 
  late Future<DocumentSnapshot> _expenseCategoriesFuture;

  @override
  void initState() {
    super.initState();
    String uid = FirebaseAuth.instance.currentUser!.uid;

    _incomeCategoriesFuture = FirebaseFirestore.instance
        .collection('Categories')
        .doc(uid)
        .collection('Transaction Categories')
        .doc('Income categories')
        .get();

    _expenseCategoriesFuture = FirebaseFirestore.instance
        .collection('Categories')
        .doc(uid)
        .collection('Transaction Categories')
        .doc('Expense categories')
        .get();

    _fetchUserBudgetPlans(uid);
  }

  // Fetch all Active budget plans for the user from the three subcollections 
  // (Daily, Weekly, Monthly) and combine them into a single list
  Future<void> _fetchUserBudgetPlans(String uid) async {
    try {
      // Fetch only "Active" plans from all three subcollections
      final dailyPlansQuery = await FirebaseFirestore.instance
          .collection('budget_plans')
          .doc(uid)
          .collection('Daily')
          .where('budgetStatus', isEqualTo: 'Active')
          .get();

      final weeklyPlansQuery = await FirebaseFirestore.instance
          .collection('budget_plans')
          .doc(uid)
          .collection('Weekly')
          .where('budgetStatus', isEqualTo: 'Active')
          .get();

      final monthlyPlansQuery = await FirebaseFirestore.instance
          .collection('budget_plans')
          .doc(uid)
          .collection('Monthly')
          .where('budgetStatus', isEqualTo: 'Active')
          .get();

      // Combine the data from all subcollections
      List<String> allBudgetPlans = [];

      for (var doc in dailyPlansQuery.docs) {
        allBudgetPlans.add(doc['budgetPlanName']);
      }

      for (var doc in weeklyPlansQuery.docs) {
        allBudgetPlans.add(doc['budgetPlanName']);
      }

      for (var doc in monthlyPlansQuery.docs) {
        allBudgetPlans.add(doc['budgetPlanName']);
      }

      if (allBudgetPlans.isNotEmpty) {
        logger.i("expense_record page line 99: First budget plan: ${allBudgetPlans.first}");
        setState(() {
          budgetPlans = allBudgetPlans;
        });
      } else {
        if (mounted) {
          setState(() {
            budgetPlans = [];
          });
        }
      }
    } catch (e) {
      logger.i("First budget plan: no plans found");
      logger.i("Error fetching budget plans: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching budget plans: $e")),
        );
      }
    }
  }

  // Show loading dialog with a message
  void _showLoadingDialog(String message) {
    logger.i("expenseRecord page: Loading dialog: $message");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Row(
            children: [
              const CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }

  // Check if the selected category is in all selected budget plans (This function is used in function _recordTransaction))
  Future<bool> isCategoryInAllSelectedBudgetPlans(String uid, String selectedCategory, List<String> selectedPlans) async {
    final planTypes = ['Daily', 'Weekly', 'Monthly'];

    for (final selectedPlan in selectedPlans) {
      bool found = false;

      for (final planType in planTypes) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('budget_plans')
            .doc(uid)
            .collection(planType)
            .where('budgetPlanName', isEqualTo: selectedPlan)
            .get();

        if (querySnapshot.docs.isEmpty) continue;

        final planDoc = querySnapshot.docs.first;

        final budgetContents = await planDoc.reference.collection('budget_contents').get();
        for (final contentDoc in budgetContents.docs) {
          final category = contentDoc['Category'];
          if (category == selectedCategory) {
            found = true;
            break;
          }
        }

        if (found) break; // Found in this plan type, no need to check other types
      }

      if (!found) {
        return false; // Category not found in this selectedPlan
      }
    }

    return true; // Category found in ALL selected plans
  }

  // Update budget values for the selected category in all selected budget plans (This function is used in function _recordTransaction))
  Future<void> _updateCategoryBudgetValues({
    required String userId,
    required String selectedCategory,
    required List<String> selectedBudgetPlans,
    required double amountToDeduct,
    required String expenseID,
  }) async {
    final planTypes = ['Daily', 'Weekly', 'Monthly'];

    for (final selectedPlanName in selectedBudgetPlans) {
      for (final planType in planTypes) {
        final planQuerySnapshot = await FirebaseFirestore.instance
            .collection('budget_plans')
            .doc(userId)
            .collection(planType)
            .where('budgetPlanName', isEqualTo: selectedPlanName)
            .get();

        if (planQuerySnapshot.docs.isEmpty) continue;

        final planDoc = planQuerySnapshot.docs.first;

        final budgetContentsSnapshot = await planDoc.reference.collection('budget_contents').get();

        for (final contentDoc in budgetContentsSnapshot.docs) {
          final category = contentDoc['Category'];
          if (category == selectedCategory) {
            final data = contentDoc.data();
            final remaining = (data['Remaining'] ?? 0).toDouble();
            final spent = (data['Spent'] ?? 0).toDouble();
            final updatedRemaining = (remaining - amountToDeduct).clamp(0, double.infinity);
            final updatedSpent = spent + amountToDeduct;

            // Update includedExpenses array
            List<dynamic> includedExpenses = List.from(data['includedExpenses'] ?? []);
            if (!includedExpenses.contains(expenseID)) {
              includedExpenses.add(expenseID);
            }

            await contentDoc.reference.update({
              'Remaining': updatedRemaining,
              'Spent': updatedSpent,
              'includedExpenses': includedExpenses,
            });

            break; // Stop after updating the matching category
          }
        }

        break; // Plan name found and processed; skip other types
      }
    }
  }

  // Record transaction (income or expense)
  Future<void> _recordTransaction(bool isIncome) async {
    String? imageUrl;
    // Check if the user has selected a category and entered an amount
    if (selectedCategory.isEmpty || amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a category and enter an amount!")),
      );
      return;
    }

    //Check if the selected category is in all selected budget plans (only for expenses)
    if (selectedBudgetPlans.isNotEmpty && !isIncome) {
      String userId = FirebaseAuth.instance.currentUser!.uid;
      bool validForAll = await isCategoryInAllSelectedBudgetPlans(userId, selectedCategory, selectedBudgetPlans);

      // If the category is not valid for all selected budget plans, show an error message
      if (!validForAll) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color.fromARGB(255, 165, 35, 226),
            title: const Text(
              "Invalid Category",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Selected category is not included in all selected budget plan(s)",
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  "OK",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
        return;
      }
    }

    _showLoadingDialog(isIncome ? "Recording income..." : "Recording expense...");

    // If an image is picked, upload it to Supabase storage
    if (_pickedImage != null) {
      try {
        final fileBytes = await _pickedImage!.readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_pickedImage!.name}';

        final storageResponse = await supabase.storage
          .from('transaction-images')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

        // Generate public URL
        imageUrl = supabase.storage.from('transaction-images').getPublicUrl(fileName);
        logger.i("Image uploaded: $imageUrl");
      } catch (e) {
        logger.e("Failed to upload image: $e");
      }
    }

    // Record the transaction in Firestore
    try {
      double amount = double.parse(amountController.text);
      String userId = FirebaseAuth.instance.currentUser!.uid;
      DateTime currentDate = selectedDate;
      String currentMonth = _getMonthAbbreviation(currentDate.month);
      String formattedDate = "${currentDate.day.toString().padLeft(2, '0')}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.year}";
      String collectionName = isIncome ? 'incomes' : 'expenses';

      Map<String, dynamic> transactionData = {
        'userId': userId,
        'amount': amount,
        'repeat': selectedRepeat,
        'category': selectedCategory,
        'description': descriptionController.text,
        'date': currentDate,
        'imageUrl': imageUrl,
      };

      // Add budget plans only if it's an expense
      if (!isIncome) {
        transactionData['budgetPlans'] = selectedBudgetPlans;
      }

      // If repeat is not "none", set lastRepeated to currentDate
      if (selectedRepeat != "None") {
        transactionData['lastRepeated'] = currentDate; // Add lastRepeated field
        logger.i("Last repeated date: $currentDate");

        await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(userId)
          .collection('Recurring')
          .add(transactionData);
      }

      // References
      DocumentReference userDocRef = FirebaseFirestore.instance.collection(collectionName).doc(userId);

      // Ensure user document exists
      DocumentSnapshot userSnapshot = await userDocRef.get();
      if (!userSnapshot.exists) {
        await userDocRef.set({
          'userId': userId,
        });
      }

      // Create/Update nested collection path: userID → Months → Apr → 20/4/2025 → expenseID
      CollectionReference dateCollectionRef = userDocRef
          .collection('Months')
          .doc(currentMonth)
          .collection(formattedDate);

      // Add the transaction to current Date subcollection
      DocumentReference transactionRef = await dateCollectionRef.add(transactionData);
      String expenseID = transactionRef.id;

      // Update Remaining and Spent for each selected budget plan (expenses only)
      if (!isIncome) {
        logger.i("expenseRecord page: Selected budget plans: $selectedBudgetPlans");
        logger.i("expenseRecord page: current expense ID: $expenseID");
        await _updateCategoryBudgetValues(
          userId: userId,
          selectedCategory: selectedCategory,
          selectedBudgetPlans: selectedBudgetPlans,
          amountToDeduct: amount,
          expenseID: expenseID,
        );
      }

      // Update monthly total and availableDates
      DocumentReference monthlyRef = userDocRef.collection('Months').doc(currentMonth);
      DocumentSnapshot monthlySnapshot = await monthlyRef.get();

      String totalKey = isIncome ? 'Monthly_Income' : 'Monthly_Expense';
      double currentTotal = 0;

      // Retrieve or create the monthly data
      List<String> availableDates = [];

      if (monthlySnapshot.exists) {
        Map<String, dynamic> data = monthlySnapshot.data() as Map<String, dynamic>;
        currentTotal = (data[totalKey] ?? 0).toDouble();
        availableDates = List<String>.from(data['availableDates'] ?? []);
      }

      // Add the current date to the availableDates list if not already there
      if (!availableDates.contains(formattedDate)) {
        availableDates.add(formattedDate);
      }

      await monthlyRef.set({
        totalKey: currentTotal + amount,
        'availableDates': availableDates, // Add or update availableDates
      }, SetOptions(merge: true));

      // Log the availableDates for debugging purposes
      logger.i("Updated availableDates for $currentMonth: $availableDates");

      // Update in users collection
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        isIncome ? 'incomes' : 'expenses': FieldValue.arrayUnion([transactionRef.id]),
      });

      triggerBudgetBackgroundTask(); // Call background task for notifications and check recurring transactions

      if (!mounted) return; // Check if the widget is still mounted before calling setState

      if (mounted) {
        setState(() {
                selectedCategory = "";
                amountController.clear();
                descriptionController.clear();
                selectedDate = DateTime.now();
              });
        }

      if (mounted) {

        Navigator.pop(context); // Close the current screen first
        // Show success dialog for recording income or expense
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color.fromARGB(255, 165, 35, 226),
            title: const Text(
              'Success',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              "${isIncome ? 'Income' : 'Expense'} recorded successfully!",
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); 
                },
                child: const Text(
                  'OK',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to record ${isIncome ? 'income' : 'expense'}: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _pickedImage = picked;
      });
      logger.i('Image selected: ${picked.path}');
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = screenWidth * 0.08;

    return PopScope(
      canPop: false, // Prevent default pop behavior
      onPopInvoked: (didPop) {
        if (!didPop) {
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: const Color.fromARGB(255, 239, 179, 236),
        appBar: AppBar(
          backgroundColor: const Color.fromARGB(255, 239, 179, 236),
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    isIncomeSelected = false;
                  });
                },
                child: Image.asset(
                  "assets/icon/spending.png",
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  color: isIncomeSelected ? Colors.grey : null,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    isIncomeSelected = true;
                  });
                },
                child: Image.asset(
                  "assets/icon/income.png",
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  color: isIncomeSelected ? null : Colors.grey,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 165, 35, 226),
            ),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
                (route) => false,
              );
            },
          ),
        ),
        body: isIncomeSelected ? _incomeInterface() : _spendingInterface(),
        bottomNavigationBar: _buildBottomAppBar(context, iconSize),
      ),
    );
  }

  // Build the category interface for both income and expense
  Widget _categoryInterface(String transactionType, List<Map<String, String>> categories, Function recordFunction) {
    final screenHeight = MediaQuery.of(context).size.height;
    final categorySelectionSectionHeight = screenHeight * 0.21;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // Top pink section
                  Container(
                    width: double.infinity,
                    height: categorySelectionSectionHeight,
                    color: const Color.fromARGB(255, 239, 179, 236),
                    padding: EdgeInsets.symmetric(vertical: screenHeight * 0.007),
                    child: _buildCategorySelection(categories),
                  ),

                  // Bottom gradient section
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.fromARGB(255, 241, 109, 231),
                            Colors.white,
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(35),
                          topRight: Radius.circular(35),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: screenHeight * 0.02,
                        horizontal: screenHeight * 0.03,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (transactionType == "Expense") _buildBudgetMultiSelect(),
                          _buildAmountInputField("Amount", amountController, TextInputType.number),
                          _buildRepeatDropdown(),
                          _buildDatePicker(context),
                          _buildDescriptionInputField("Description", descriptionController, TextInputType.text, _pickImage),
                          const SizedBox(height: 10),
                          isSubmitting
                              ? const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)))
                              : Center(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (!mounted) return;
                                      setState(() {
                                        isSubmitting = true;
                                      });

                                      await recordFunction();

                                      if (!mounted) return;
                                      setState(() {
                                        isSubmitting = false;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                    child: const Text(
                                      "Confirm",
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Interface for expense
  Widget _spendingInterface() {
    return FutureBuilder<DocumentSnapshot>(
      future: _expenseCategoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("No expense categories found."));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> categoryList = data['categoryNames'] ?? [];
        const String transactionType = "Expense";

        final List<Map<String, String>> categories = categoryList.map<Map<String, String>>((cat) {
          return {
            "icon": cat['icon'] ?? '',
            "label": cat['name'] ?? '',
          };
        }).toList();

        // return the category interface for expense
        return _categoryInterface(transactionType,categories, () => _recordTransaction(false) /* false for expense */); 
      },
    );
  }

  // Interface for Income
  Widget _incomeInterface() {
    return FutureBuilder<DocumentSnapshot>(
      future: _incomeCategoriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("No income categories found."));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final List<dynamic> categoryList = data['categoryNames'] ?? [];
        const String transactionType = "Income";

        final List<Map<String, String>> categories = categoryList.map<Map<String, String>>((cat) {
          return {
            "icon": cat['icon'] ?? '',
            "label": cat['name'] ?? '',
          };
        }).toList();
        return _categoryInterface(transactionType, categories, () => _recordTransaction(true)  /* false for income */); 
      },
    );
  }

  Widget _buildCategorySelection(List<Map<String, String>> categories) {
    return SizedBox(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.5,
        ),
        itemBuilder: (context, index) {
          return _buildCategoryButton(
            categories[index]["icon"]!,
            categories[index]["label"]!,
            selectedCategory == categories[index]["label"],
          );
        },
      ),
    );
  }

  //  Category Button Widget
  Widget _buildCategoryButton(String iconPath, String label, bool isSelected) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color.fromARGB(255, 241, 109, 231) : Colors.white, // Purple when selected, white otherwise for the button background
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: const BorderSide(color: Color.fromARGB(255, 165, 35, 226), width: 2), // Purple border
        ),
      ),
      onPressed: () {
        setState(() {
          selectedCategory = label; // Store the selected category
        });
      },
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconPath, width: 20, height: 20),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color.fromARGB(255, 165, 35, 226), // White text when selected, purple otherwise for the text color
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build the multi-select dropdown for budget plans
  Widget _buildBudgetMultiSelect() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double dropdownWidth = screenWidth * 0.8;
    double dropdownHeight = screenHeight * 0.06;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Budget Plan",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: dropdownWidth,
                height: dropdownHeight,
                child: GestureDetector(
                  onTap: () => _showMultiSelectDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      selectedBudgetPlans.isEmpty
                          ? "Select budget plan(s)"
                          : selectedBudgetPlans.length == 1
                              ? selectedBudgetPlans.first
                              : "${selectedBudgetPlans.length} budget plans selected",
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color.fromARGB(255, 165, 35, 226),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Show multi-select dialog for budget plans
  void _showMultiSelectDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder( // 👈 Wrap your AlertDialog here
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Select Budget Plan(s)"),
              content: SingleChildScrollView(
                child: ListBody(
                  children: budgetPlans.map((plan) {
                    return CheckboxListTile(
                      title: Text(plan),
                      value: selectedBudgetPlans.contains(plan),
                      activeColor: const Color.fromARGB(255, 165, 35, 226),
                      onChanged: (bool? checked) {
                        // Use the dialog's own setState
                        setStateDialog(() {
                          if (checked == true) {
                            selectedBudgetPlans.add(plan);
                          } else {
                            selectedBudgetPlans.remove(plan);
                          }
                        });

                        // Optionally also call your outer setState
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text("Cancel",
                    style: TextStyle(color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: const Text("OK",
                    style: TextStyle(color: Color.fromARGB(255, 165, 35, 226)),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Build the input field for amount
  Widget _buildAmountInputField(String label, TextEditingController controller, TextInputType keyboardType) {
    double screenHeight = MediaQuery.of(context).size.height;
    double inputHeight = screenHeight * 0.04;
    double screenWidth = MediaQuery.of(context).size.width;
    double fieldWidth = screenWidth * 0.4;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color.fromARGB(255, 165, 35, 226),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  cursorColor: const Color.fromARGB(255, 165, 35, 226), // Set cursor color
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: inputHeight * 0.25,
                      horizontal: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: Color.fromARGB(255, 165, 35, 226), // Set focus border color
                        width: 2,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: inputHeight * 0.6,
                    color: const Color.fromARGB(255, 165, 35, 226),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build the dropdown for repeat options
  Widget _buildRepeatDropdown() {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double fieldWidth = screenWidth * 0.4;
    double dropdownHeight = screenHeight * 0.06;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Repeat",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color.fromARGB(255, 165, 35, 226)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: fieldWidth,  // Ensure the width is constrained
                child: DropdownButtonFormField2<String>(
                  value: selectedRepeat,
                  buttonStyleData: ButtonStyleData(
                    height: dropdownHeight,  // Adjust the button height
                    width: fieldWidth,  // Adjust the button width
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  style: const TextStyle(color: Color.fromARGB(255, 165, 35, 226), fontSize: 14),
                  // Dropdown icon
                  iconStyleData: const IconStyleData(
                    icon: Icon(Icons.arrow_drop_down, color: Colors.purple),
                  ),
                  // Dropdown menu items
                  dropdownStyleData: DropdownStyleData(
                    maxHeight: 200,
                    width: fieldWidth, // Adjust dropdown list width
                    padding: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white,
                    ),
                    elevation: 4,
                    offset: const Offset(0, 0),
                  ),
                  items: ['None', 'Daily', 'Weekly', 'Monthly']
                      .map((value) => DropdownMenuItem<String>(
                            value: value,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(value),
                            ),
                          ))
                      .toList(),
                  onChanged: (newValue) {
                    setState(() {
                      selectedRepeat = newValue!;
                    });
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double datePickerWidth = screenWidth * 0.63;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            "Date",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color.fromARGB(255, 165, 35, 226),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {
                  picker.DatePicker.showDateTimePicker(
                    context,
                    showTitleActions: true,
                    minTime: DateTime(2000),
                    maxTime: DateTime(2100),
                    currentTime: selectedDate,
                    locale: picker.LocaleType.en,
                    onConfirm: (DateTime pickedDateTime) {
                      setState(() => selectedDate = pickedDateTime);
                    },
                  );
                },
                child: SizedBox(
                  width: datePickerWidth,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "${selectedDate.day.toString().padLeft(2, '0')} "
                          "${_getMonthAbbreviation(selectedDate.month)} "
                          "${selectedDate.year} "
                          "${selectedDate.hour.toString().padLeft(2, '0')}:${selectedDate.minute.toString().padLeft(2, '0')}",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color.fromARGB(255, 165, 35, 226),
                          ),
                        ),
                        const Icon(Icons.calendar_today, color: Colors.purple),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionInputField(
    String label,
    TextEditingController controller,
    TextInputType keyboardType,
    VoidCallback onImagePick, // Pass a function to pick image
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row containing label and image button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color.fromARGB(255, 165, 35, 226),
                ),
              ),
              TextButton(
                onPressed: onImagePick,
                child: const Text(
                  "Add Image",
                  style: TextStyle(
                    fontSize: 14,
                    color: Color.fromARGB(255, 165, 35, 226),
                    decoration: TextDecoration.underline, 
                  ),
                ),
              ),
            ],
          ),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            cursorColor: const Color.fromARGB(255, 165, 35, 226),
            maxLines: null,
            minLines: 3,
            style: const TextStyle(
              color: Color.fromARGB(255, 165, 35, 226),
              fontSize: 16,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color.fromARGB(255, 165, 35, 226),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to get month name abbreviation
  String _getMonthAbbreviation(int monthNumber) {
    const monthAbbreviations = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return monthAbbreviations[monthNumber - 1];
  }

  Widget _buildBottomAppBar(BuildContext context, double iconSize) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double bottomAppBarHeight = screenHeight * 0.115; // 11.5% of screen height
    double iconSpacing = screenWidth * 0.14;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomAppBar(
        height: bottomAppBarHeight,
        elevation: 0,
        color: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildNavIconWithCaption(context, "assets/icon/record-book.png","Record",iconSize,const ExpenseRecordPage(), textColor: Colors.deepPurple),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/budget.png", "Budget", iconSize, const BudgetPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/dataVisual.png", "Graphs", iconSize, const DataVisualPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/chatbot.png", "AI", iconSize, const AIPage()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavIconWithCaption(
    BuildContext context,
    String assetPath,
    String caption,
    double size,
    Widget page, {
    Color textColor = Colors.grey
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => page,
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          },
          child: SizedBox(
            width: size,
            height: size,
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: TextStyle(
            fontSize: 13,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
