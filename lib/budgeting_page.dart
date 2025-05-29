import 'package:flutter/services.dart'; // Make sure this is at the top
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ai_page.dart';
import 'expenseRecord_page.dart';
import 'dataVisual_page.dart';
import 'home_page.dart';
import 'budget_archive_page.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:logger/logger.dart';


class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final logger = Logger();
  double screenWidth = 0; // Screen Width for the "View Archived Budgets", "Add Budget Plan" button and bottom navigation bar
  double screenHeight = 0; // Screen Height for the "View Archived Budgets" and "Add Budget Plan" button
  double iconSize = 0;  // Icon size for the bottom navigation bar
  double buttonWidth = 0;  // Button size for the "View Archived Budgets" and "Add Budget Plan" button
  double buttonHeight = 0; // Button height for the "View Archived Budgets" and "Add Budget Plan" button

  final userId = FirebaseAuth.instance.currentUser!.uid;
  Map<String, List<Map<String, dynamic>>> allBudgets = {}; // Holds all filtered budget plans and their contents
  Map<String, String> planStatuses = {}; // Holds the status of each filtered budget plans (Active, Expired, etc.)
  bool _isLoading = true;
  Map<String, bool> isSaving = {}; // Add this to your state
  //final String _selectedBudgetType = 'Daily'; // Default budget type
  final List<bool> _selectedFilters = [true, false, false]; // Default filter selection (Daily)

  Map<String, bool> isEditing = {};
  Map<String, TextEditingController> planNameControllers = {};
  Map<String, List<TextEditingController>> categoryControllers = {};
  Map<String, List<TextEditingController>> amountControllers = {};

  static const Color purpleColor = Color.fromARGB(255, 165, 35, 226);

  List<String> categories = [];
  final String planName = "Budget Plan Name"; // Default plan name

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadFilteredBudgets();
    _updateExpiredBudgetStatuses(); // Update expired budget statuses
  }

  Future<void> _loadCategories() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final expenseDoc = await FirebaseFirestore.instance
        .collection('Categories')
        .doc(userId)
        .collection('Transaction Categories')
        .doc('Expense categories')
        .get();

    List<String> loadedCategories = [];

    if (expenseDoc.exists) {
      final expenseData = expenseDoc.data();
      if (expenseData != null && expenseData['categoryNames'] is List) {
        loadedCategories.addAll(
          (expenseData['categoryNames'] as List)
              .map((cat) => cat['name'].toString()),
        );
      }
    }

    setState(() {
      categories = loadedCategories.toSet().toList(); // Remove duplicates
    });
  }

  Future<void> _updateExpiredBudgetStatuses() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final now = DateTime.now();
    final types = ['Daily', 'Weekly', 'Monthly'];

    for (final type in types) {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('budget_plans')
          .doc(userId)
          .collection(type)
          .get();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();

        final endTimestamp = data['budgetPlanEnd'];
        final currentStatus = data['budgetStatus'];

        if (endTimestamp == null || currentStatus == 'Expired' || currentStatus == 'Archived') continue;

        final endDate = (endTimestamp as Timestamp).toDate();

        if (now.isAfter(endDate)) {
          await doc.reference.update({'budgetStatus': 'Expired'});
        }
      }
    }
  }

  Future<void> _loadFilteredBudgets() async {
    final firestore = FirebaseFirestore.instance;
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final type = _selectedFilters[0]
        ? 'Daily'
        : _selectedFilters[1]
            ? 'Weekly'
            : 'Monthly';

    final plansSnapshot = await firestore
        .collection('budget_plans')
        .doc(userId)
        .collection(type)
        .get();

    Map<String, List<Map<String, dynamic>>> tempBudgets = {};
    planStatuses.clear(); // Store statuses for display logic

    for (var doc in plansSnapshot.docs) {
      final data = doc.data();
      final planStatus = data['budgetStatus'] ?? ''; // Default to empty string if not found

      logger.i("Budget plan status: $planStatus");
      if (planStatus != 'Active' && planStatus != 'Expired') continue;

      String planName = doc['budgetPlanName'] ?? 'Unnamed Plan';
      String planId = doc.id;

      final contentSnapshot = await firestore
          .collection('budget_plans')
          .doc(userId)
          .collection(type)
          .doc(planId)
          .collection('budget_contents')
          .get();

      tempBudgets[planName] = contentSnapshot.docs.map((e) => e.data()).toList();
      planStatuses[planName] = planStatus; // Track status for UI logic

      isEditing[planName] = false;
      planNameControllers[planName] = TextEditingController(text: planName);

      categoryControllers[planName] = contentSnapshot.docs.map((e) {
        return TextEditingController(text: e['Category']);
      }).toList();

      amountControllers[planName] = contentSnapshot.docs.map((e) {
        return TextEditingController(text: e['Amount'].toString());
      }).toList();
    }

    setState(() {
      allBudgets = tempBudgets;
      _isLoading = false;
    });
  }

  // Builds and displays a list of budget plans, with the following functionalities:
  // - If no budget plans exist, a message "No budget plans yet." is displayed.
  // - Each budget plan is displayed as a card with the following components:
  //   - **Plan Name**: Shows the name of the budget plan. If the user is editing the plan, it turns into a text field to allow changes.
  //   - **Edit Button**: Allows the user to edit the plan name and its categories/amounts. When pressed, it toggles into an editable mode, showing text fields for each category and amount.
  //   - **Save/Cancel Button** (if in edit mode): Saves the changes or cancels the edit mode, reverting to the original plan data.
  //   - **Delete Button**: Prompts a confirmation dialog to delete the selected budget plan. If confirmed, the plan and its contents are deleted from the database.
  //   - **Category and Amount Display/Editing**: Displays the categories and amounts in each plan. In edit mode, users can update categories via a dropdown and change amounts via text fields.
  //   - **Add New Category Button**: Allows users to add a new category to the selected budget plan.
  Widget _buildBudgetList() {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    if (allBudgets.isEmpty) {
      return const Center(child: Text("No budget plans yet."));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: allBudgets.entries.map((entry) {
        final planName = entry.key;
        final contents = entry.value;

        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan name with Edit, Save, Cancel, and Delete buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    isEditing[planName] == true
                      ? Expanded(
                          child: TextFormField(
                            controller: planNameControllers[planName],
                            decoration: const InputDecoration(labelText: "Budget Plan Name"),
                          ),
                        )
                      : Text( // Display the plan name based on the budget status
                          planStatuses[planName] == 'Expired'
                              ? '$planName (Expired)' // If plan status is expired, then append "Expired" behind the plan name 
                              : planName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: planStatuses[planName] == 'Expired'
                                ? Colors.grey // Set the plan name to gray color for expired plan 
                                : const Color.fromARGB(255, 165, 35, 226),
                          ),
                        ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      // Display the Edit, Save, Cancel, and Delete buttons based on the budget status
                      children: planStatuses[planName] == 'Expired'
                          ? [
                              IconButton(
                                icon: const Icon(Icons.archive, color: Color.fromARGB(255, 165, 35, 226)),
                                onPressed: () async {
                                  // Show confirmation dialog before archiving
                                  final shouldArchive = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                      title: const Text(
                                        "Archive Budget Plan",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: Text(
                                        "Are you sure you want to archive '$planName'?",
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text(
                                            "Cancel",
                                            style: TextStyle(color: Colors.white),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text(
                                            "Archive",
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    )
                                  );

                                  if (shouldArchive == true) {
                                    final type = _selectedFilters[0]
                                        ? 'Daily'
                                        : _selectedFilters[1]
                                            ? 'Weekly'
                                            : 'Monthly';

                                    final querySnapshot = await FirebaseFirestore.instance
                                        .collection('budget_plans')
                                        .doc(userId)
                                        .collection(type)
                                        .where('budgetPlanName', isEqualTo: planName)
                                        .get();

                                    if (querySnapshot.docs.isNotEmpty) {
                                      final docId = querySnapshot.docs.first.id;

                                      await FirebaseFirestore.instance
                                          .collection('budget_plans')
                                          .doc(userId)
                                          .collection(type)
                                          .doc(docId)
                                          .update({'budgetStatus': 'Archived'});

                                      _loadFilteredBudgets();

                                      // Show success dialog after archiving
                                      if(mounted){
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                            title: const Text("Success"),
                                            content: Text("The budget plan '$planName' has been archived."),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: const Text("OK" ,style: TextStyle(color: Colors.white),),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      
                                    } else {
                                      // Show error dialog
                                      if(mounted){
                                        showDialog(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                            title: const Text("Error"),
                                            content: const Text("No matching budget plan found to archive."),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                child: const Text("OK", style: TextStyle(color: Colors.white),),                                                
                                              ),
                                            ],
                                          ),
                                        );
                                      }                                      
                                      logger.e('No matching budget plan found to archive.');
                                    }
                                  }
                                },
                              ),
                            ]
                          : isEditing[planName] == true
                              ? [
                                  isSaving[planName] == true
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226),strokeWidth: 2),
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.check),
                                          onPressed: () => _saveEditedBudget(planName),
                                        ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        isEditing[planName] = false;
                                        planNameControllers[planName]?.text = planName;
                                        for (int i = 0; i < allBudgets[planName]!.length; i++) {
                                          categoryControllers[planName]![i].text = allBudgets[planName]![i]['Category'];
                                          amountControllers[planName]![i].text = allBudgets[planName]![i]['Amount'].toString();
                                        }
                                      });
                                    },
                                  ),
                                ]
                              : [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: purpleColor),
                                    onPressed: () {
                                      categoryControllers[planName] ??= allBudgets[planName]!
                                          .map((e) => TextEditingController(text: e['Category']))
                                          .toList();

                                      amountControllers[planName] ??= allBudgets[planName]!
                                          .map((e) => TextEditingController(text: e['Amount'].toString()))
                                          .toList();

                                      setState(() {
                                        isEditing[planName] = true;
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: purpleColor),
                                    onPressed: () async {
                                      final shouldDelete = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                                          title: const Text(
                                            "Delete Budget Plan",
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          content: Text(
                                            "Are you sure you want to delete '$planName'?",
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text(
                                                "Cancel",
                                                style: TextStyle(color: Colors.white),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text(
                                                "Delete",
                                                style: TextStyle(color: Color.fromARGB(255, 247, 56, 43)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      final type = _selectedFilters[0]
                                          ? 'Daily'
                                          : _selectedFilters[1]
                                              ? 'Weekly'
                                              : 'Monthly';

                                      if (shouldDelete == true) {
                                        _deleteBudgetPlan(planName, type);
                                      }
                                    },
                                  ),
                                ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Budget contents (category + amount)
                ...List.generate(contents.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Expanded(
                          // A dropdown for selecting categories
                          // If not in edit mode, display the category as text
                          child: isEditing[planName] == true
                              ? DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: categories.contains(categoryControllers[planName]![index].text)
                                    ? categoryControllers[planName]![index].text
                                    : null,
                                items: categories.map((cat) {
                                  final selectedCategories = categoryControllers[planName]!
                                      .map((controller) => controller.text)
                                      .toList();
                                  final currentCategory = categoryControllers[planName]![index].text;
                                  final isUsed = cat != currentCategory && selectedCategories.contains(cat);

                                  return DropdownMenuItem<String>(
                                    value: cat, // Always assign the category string as value
                                    enabled: !isUsed,
                                    child: Text(
                                      cat + (isUsed ? " (already selected)" : ""),
                                      style: TextStyle(color: isUsed ? Colors.grey : Colors.black),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      categoryControllers[planName]![index].text = value;
                                    });
                                  }
                                },
                                decoration: const InputDecoration(labelText: "Category"),
                              )

                              : Text(contents[index]['Category']),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: isEditing[planName] == true
                            ? TextFormField( // Text field for entering amounts if in edit mode
                                controller: amountControllers[planName]![index],
                                decoration: const InputDecoration(labelText: "Amount"),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              )
                            : Text.rich( // Display remaining and total amount if not in edit mode
                                TextSpan(
                                  text: 'RM ',
                                  style: const TextStyle(color: Colors.black),
                                  children: [
                                    TextSpan(
                                      text: _formatAmount(contents[index]['Remaining']),
                                      style: const TextStyle(color: Colors.red),
                                    ),
                                    const TextSpan(text: ' / '),
                                    TextSpan(
                                      text: _formatAmount(contents[index]['Amount']),
                                      style: const TextStyle(color: Colors.green),
                                    ),
                                  ],
                                ),
                              ),
                        ),
                      ],
                    ),
                  );
                }),
                
                const SizedBox(height: 16),

                // Button to add a new category to the plan
                if (planStatuses[planName] == 'Active')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                        foregroundColor: purpleColor,
                      ),
                      onPressed: () => _showAddBudgetSheet(context, planName),
                      child: const Text(
                        "Add New Category to Plan",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // Formats the amount to a string with 2 decimal places if it's a double, or as an integer if it's a whole number.
  String _formatAmount(dynamic amount) {
    if (amount == null) return "0";

    double? parsedAmount;

    if (amount is String) {
      parsedAmount = double.tryParse(amount);
    } else if (amount is int) {
      parsedAmount = amount.toDouble();
    } else if (amount is double) {
      parsedAmount = amount;
    }

    if (parsedAmount == null) return "0";

    return parsedAmount % 1 == 0
        ? parsedAmount.toInt().toString()
        : parsedAmount.toStringAsFixed(2);
  }

  // Deletes a budget plan and its contents from Firestore
  Future<void> _deleteBudgetPlan(String planName, String type) async {
    logger.i("Deleting budget plan: $planName");
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final planQuery = await FirebaseFirestore.instance
        .collection('budget_plans')
        .doc(userId)
        .collection(type)
        .where('budgetPlanName', isEqualTo: planName)
        .limit(1)
        .get();

    if (planQuery.docs.isNotEmpty) {
      final planRef = planQuery.docs.first.reference;

      // Check if any budget content has includedExpenses
      final contentsSnapshot = await planRef.collection('budget_contents').get();
      bool hasIncludedExpenses = false;

      for (var doc in contentsSnapshot.docs) {
        final data = doc.data();
        final includedExpenses = data['includedExpenses'];
        if (includedExpenses != null && includedExpenses is List && includedExpenses.isNotEmpty) {
          hasIncludedExpenses = true;
          break;
        }
      }

      // If any category has includedExpenses, show confirmation dialog
      if (hasIncludedExpenses) {
        if (!mounted) return;

        bool confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Confirm Deletion"),
            content: const Text(
                "Some categories in this plan are linked to recorded expenses. Are you sure you want to delete this budget plan?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Confirm"),
              ),
            ],
          ),
        ) ?? false;

        if (!confirmed) return;
      }

      logger.i("Deletion checking 2");
      // Proceed to delete budget contents
      for (var doc in contentsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete the plan document
      await planRef.delete();

      // Proceed to delete the plan reference from the expenses collection 
      logger.i("budget page: userID: $userId, planName: $planName");
      final expenseRef = FirebaseFirestore.instance.collection('expenses').doc(userId).collection('Months');
      final monthsSnapshot = await expenseRef.get(); //Gets all the documents in the months collection
      // Log the list of month document IDs and count
      logger.i('Fetched ${monthsSnapshot.docs.length} month(s): ${monthsSnapshot.docs.map((doc) => doc.id).toList()}');


      for (final monthDoc in monthsSnapshot.docs) {
        logger.i("budget page: monthDoc.id: ${monthDoc.id}");

        // Fetch the 'availableDates' for the current month
        final monthData = monthDoc.data();
        final List<String> availableDates = List<String>.from(monthData['availableDates'] ?? []);

        for (final date in availableDates) {
          // Get the specific date collection
          final dateDocSnapshot = await expenseRef
              .doc(monthDoc.id)
              .collection(date)
              .get();

          // Loop through the documents within that date collection
          for (final dateDoc in dateDocSnapshot.docs) {
            final expenseData = dateDoc.data();
            logger.i('Expense data for ${monthDoc.id}/$date: $expenseData');

            // Check if budgetPlans exists and contains the deleted plan
            final List<dynamic>? plans = expenseData['budgetPlans'];
            if (plans != null && plans.contains(planName)) {
              await dateDoc.reference.update({
                'budgetPlans': FieldValue.arrayRemove([planName])
              });
            }
          }
        }
      }

      if (mounted) {
        await _loadFilteredBudgets();

        // Always check if still mounted *before* using context after async gap
        if (!mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Deletion Successful"),
            content: Text("Budget plan '$planName' has been deleted successfully."),
            actions: [
              TextButton(
                onPressed: () {
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    }
  }

  // Shows a dialog that allows the user to create a new budget plan.
  // - Displays a text input for the user to enter the budget plan name.
  // - If the user clicks "Create" and the name is valid, a new document is added to the 'budget_plans' collection in Firestore.
  // - After successfully creating a plan, the list of all budget plans is refreshed, and a success message is shown via a snackbar.
  void _showAddBudgetPlanDialog(BuildContext context) {
    //final TextEditingController planNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        String selectedType = 'Daily'; // Default type
        final planNameController = TextEditingController();

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 165, 35, 226),
              title: const Text(
                "New Budget Plan",
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: planNameController,
                    decoration: const InputDecoration(
                      labelText: "Plan Name",
                      hintText: "Enter budget plan name",
                      labelStyle: TextStyle(color: Colors.white),
                      hintStyle: TextStyle(color: Colors.white70),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: "Budget Plan Type",
                      labelStyle: TextStyle(color: Colors.white),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                    ),
                    dropdownColor: const Color.fromARGB(255, 165, 35, 226),
                    items: ['Daily', 'Weekly', 'Monthly']
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type, style: const TextStyle(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedType = value;
                        });
                      }
                    },
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color.fromARGB(255, 165, 35, 226),
                  ),
                  onPressed: () async {
                    final planName = planNameController.text.trim();
                    if (planName.isEmpty) return;

                    try {
                      final userId = FirebaseAuth.instance.currentUser!.uid;
                      final now = DateTime.now();

                      DateTime endDate;
                      if (selectedType == 'Daily') {
                        endDate = now.add(const Duration(days: 1));
                      } else if (selectedType == 'Weekly') {
                        endDate = now.add(const Duration(days: 7));
                      } else {
                        endDate = now.add(const Duration(days: 30));
                      }

                      await FirebaseFirestore.instance
                          .collection('budget_plans')
                          .doc(userId)
                          .collection(selectedType)
                          .add({
                        'userID': userId,
                        'budgetPlanName': planName,
                        'budgetPlanStart': now,
                        'budgetPlanEnd': endDate,
                        'budgetStatus': "Active"
                      });

                      if (!context.mounted) return;
                      Navigator.pop(dialogContext);

                      _loadFilteredBudgets();

                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                          title: const Text("Success", style: TextStyle(color: Colors.white)),
                          content: Text(
                            "Budget plan '$planName' created!",
                            style: const TextStyle(color: Colors.white),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text("OK", style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                          title: const Text("Error", style: TextStyle(color: Colors.white)),
                          content: Text(
                            "Failed to create budget plan: $e",
                            style: const TextStyle(color: Colors.white),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text("OK", style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
}

  // Saves the edited budget plan by updating both the budget plan name and its contents.
  // - The plan name is updated in the Firestore document corresponding to the old plan name.
  // - The existing budget contents (categories and amounts) are cleared and replaced with the updated values.
  // - The UI is refreshed to reflect the changes after the update.
  // - A success message is shown to the user upon completion.
  Future<void> _saveEditedBudget(String oldPlanName) async {
    setState(() {
      isSaving[oldPlanName] = true;
    });

    final firestore = FirebaseFirestore.instance;
    final newPlanName = planNameControllers[oldPlanName]!.text.trim();

    // Determine selected budget type
    final type = _selectedFilters[0]
        ? 'Daily'
        : _selectedFilters[1]
            ? 'Weekly'
            : 'Monthly';

    final userId = FirebaseAuth.instance.currentUser!.uid;

    // Find the existing budget plan
    final budgetQuery = await firestore
        .collection('budget_plans')
        .doc(userId)
        .collection(type)
        .where('budgetPlanName', isEqualTo: oldPlanName)
        .limit(1)
        .get();

    if (budgetQuery.docs.isNotEmpty) {
      final docRef = budgetQuery.docs.first.reference;

      // Update the budget plan name
      await docRef.update({'budgetPlanName': newPlanName});

      final contentsRef = docRef.collection('budget_contents');

      // Load old budget contents before deleting
      final oldContentsSnapshot = await contentsRef.get();

      // Map of old category → spent & remaining
      final Map<String, Map<String, double>> oldCategoryData = {};
      for (var doc in oldContentsSnapshot.docs) {
        final data = doc.data();
        oldCategoryData[data['Category']] = {
          'Spent': (data['Spent'] ?? 0).toDouble(),
          'Remaining': (data['Remaining'] ?? 0).toDouble(),
        };
      }

      // Delete old contents
      for (var doc in oldContentsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Re-create new budget contents
      for (int i = 0; i < categoryControllers[oldPlanName]!.length; i++) {
        final newCategory = categoryControllers[oldPlanName]![i].text.trim();
        final newAmount = double.parse(amountControllers[oldPlanName]![i].text.trim());

        // Check if this category existed before
        final oldData = oldCategoryData[newCategory];

        final double spent = oldData?['Spent'] ?? 0.0;
        final double remaining = (newAmount - spent).clamp(0, double.infinity);

        await contentsRef.add({
          'Category': newCategory,
          'Amount': newAmount,
          'Spent': spent,
          'Remaining': remaining,
        });
      }

      // Reload UI data
      await _loadFilteredBudgets();
    }

    setState(() {
      isEditing[oldPlanName] = false;
      isSaving[oldPlanName] = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Budget updated successfully!")),
      );
    }
  }

  // Displays a bottom sheet to add a new budget category to an existing budget plan.
  // - The bottom sheet is scrollable and occupies the remaining screen space below the app bar.
  // - The `_AddBudgetForm` widget is used inside the bottom sheet, allowing the user to input a new budget category.
  // - The function passes the current `planName` to the form and specifies a callback (`onBudgetAdded`) to refresh the budget list after adding a new category.
  // - The bottom sheet's height is dynamically adjusted based on the screen's height and the app bar's height.
  // - The form is padded appropriately, ensuring proper layout and responsiveness for different screen sizes.
  void _showAddBudgetSheet(BuildContext context, String planName) {
    final screenHeight = MediaQuery.of(context).size.height;
    const appBarHeight = kToolbarHeight;

    // Determine selected budget type
    final type = _selectedFilters[0]
        ? 'Daily'
        : _selectedFilters[1]
            ? 'Weekly'
            : 'Monthly';

    // Show the bottom sheet with dynamic height, ensuring it doesn't overlap with app bars
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SizedBox(
          height: screenHeight - appBarHeight - appBarHeight,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: _AddBudgetForm(
                onBudgetAdded: _loadFilteredBudgets, // Callback to refresh budget list
                planName: planName, // Pass the current plan name
                selectedType: type, // Pass the selected budget type
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width;
    screenHeight = MediaQuery.of(context).size.height;
    buttonWidth = screenWidth * 0.60;
    buttonHeight = screenHeight * 0.055;
    iconSize = screenWidth * 0.08;

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
        extendBodyBehindAppBar: true, // Let gradient go behind AppBar
        appBar: AppBar(
          backgroundColor: Colors.transparent, // Make AppBar transparent to show gradient
          elevation: 0,
          title: const Text(
            "Budgeting",
            style: TextStyle(color: Color.fromARGB(255, 154, 16, 179)),
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
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const HomePage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
                (route) => false,
              );
            },
          ),
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromARGB(255, 241, 109, 231), // pink/purple
                Colors.white, // fade to white
              ],
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.12), // Push content below AppBar
              // Archive Button
              SizedBox(
                height: buttonHeight,
                width: buttonWidth,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const BudgetArchivePage(),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[70],
                    foregroundColor: purpleColor,
                  ),
                  child: const Text("View Archived Budgets"),
                ),
              ),

              const SizedBox(height: 15),

              SizedBox(
                height: buttonHeight,
                width: buttonWidth,
                child: ElevatedButton(
                  onPressed: () => _showAddBudgetPlanDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[70],
                    foregroundColor: purpleColor,
                  ),
                  child: const Text("Add Budget Plan"),
                ),
              ),

              const SizedBox(height: 15),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ToggleButtons(
                  borderRadius: BorderRadius.circular(30),
                  borderColor: const Color.fromARGB(255, 165, 35, 226),
                  selectedBorderColor: const Color.fromARGB(255, 165, 35, 226),
                  selectedColor: Colors.white,
                  fillColor: const Color.fromARGB(255, 165, 35, 226),
                  color: const Color.fromARGB(255, 165, 35, 226),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
                  isSelected: _selectedFilters,
                  onPressed: (int index) {
                    setState(() {
                      for (int i = 0; i < _selectedFilters.length; i++) {
                        _selectedFilters[i] = i == index;
                      }
                      _isLoading = true;
                    });
                    _loadFilteredBudgets(); // Load new filter type
                  },
                  children: const [
                    Text("Daily"),
                    Text("Weekly"),
                    Text("Monthly"),
                  ],
                ),
              ),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)))
                    : _buildBudgetList(),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomAppBar(context, iconSize),
      ),
    );
  }

  Widget _buildBottomAppBar(BuildContext context, double iconSize) {
    double screenWidth = MediaQuery.of(context).size.width;
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
        height: 100,
        elevation: 0,
        color: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildNavIconWithCaption( context, "assets/icon/record-book.png","Record",iconSize,const ExpenseRecordPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/budget.png", "Budget", iconSize, const BudgetPage(), textColor: Colors.deepPurple),
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

// A form widget to add a new budget category to an existing budget plan.
// It allows the user to select a category from available options and input an amount.
// The form fetches categories from Firestore and ensures the selected category is not already in use in the current budget plan.
// After the form is submitted, the budget category is added to the plan and the UI is refreshed.
// - `onBudgetAdded`: A callback function to refresh the budget list after a new category is added.
// - `planName`: The name of the budget plan to which the category will be added.
class _AddBudgetForm extends StatefulWidget {
  final VoidCallback onBudgetAdded;
  final String planName;
  final String selectedType;

  const _AddBudgetForm({
    required this.onBudgetAdded,
    required this.planName,
    required this.selectedType,
  });

  @override
  State<_AddBudgetForm> createState() => _AddBudgetFormState();
}

class _AddBudgetFormState extends State<_AddBudgetForm> {
  final TextEditingController amountController = TextEditingController();
  String? selectedCategory;
  List<String> categories = [];
  List<String> usedCategories = [];
  bool isLoading = true; // Flag to indicate if data is still loading
  bool isSavingNewCat = true; // Flag to indicate if the form is saving

  static const Color purpleColor = Color.fromARGB(255, 165, 35, 226);

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUsedCategories();
  }

  // Loads available categories from Firestore
  Map<String, String> categoryIcons = {}; // name => iconPath

  Future<void> _loadCategories() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final expenseDoc = await FirebaseFirestore.instance
        .collection('Categories')
        .doc(userId)
        .collection('Transaction Categories')
        .doc('Expense categories')
        .get();

    List<String> loadedCategories = [];

    if (expenseDoc.exists) {
      final expenseData = expenseDoc.data();
      if (expenseData != null && expenseData['categoryNames'] is List) {
        for (var cat in expenseData['categoryNames']) {
          final name = cat['name'].toString();
          final icon = cat['icon'].toString();
          loadedCategories.add(name);
          categoryIcons[name] = icon;
        }
      }
    }

    setState(() {
      categories = loadedCategories.toSet().toList(); // Remove duplicates
    });
  }

  // Loads categories already used in the selected budget plan
  Future<void> _loadUsedCategories() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    final planQuery = await FirebaseFirestore.instance
        .collection('budget_plans')
        .doc(userId)
        .collection(widget.selectedType)
        .where('budgetPlanName', isEqualTo: widget.planName)
        .limit(1)
        .get();

    if (planQuery.docs.isNotEmpty) {
      final planDocRef = planQuery.docs.first.reference;

      final contentsSnapshot = await planDocRef.collection('budget_contents').get(); // Get all budget contents

      usedCategories = contentsSnapshot.docs
          .map((doc) => doc['Category'].toString())
          .toList();
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  // Builds the form UI for adding a new budget category
  // - Displays a dropdown for selecting a category and an input field for entering the amount.
  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double dropdownWidth = screenWidth * 0.55;
    // Show loading indicator while data is being fetched
    return isLoading
    ? const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)))
    : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative line at the top of the form
          Center(
            child: Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: purpleColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          // Display the plan name
          Text(
            "Budget Plan: ${widget.planName}",
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // Dropdown list to select a category
          DropdownButtonHideUnderline(
            child: DropdownButton2<String>(
              isExpanded: true,
              value: selectedCategory,
              hint: const Text("Select a category"),
              items: categories.map((cat) {
                final isUsed = usedCategories.contains(cat);
                final iconPath = categoryIcons[cat] ?? '';

                return DropdownMenuItem<String>(
                  value: isUsed ? null : cat,
                  enabled: !isUsed,
                  child: Row(
                    children: [
                      if (iconPath.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Image.asset(
                            iconPath,
                            width: 24,
                            height: 24,
                          ),
                        ),
                      Text(
                        cat + (isUsed ? " (existed)" : ""),
                        style: TextStyle(
                          color: isUsed ? Colors.grey : const Color.fromARGB(255, 165, 35, 226),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedCategory = value);
                }
              },
              buttonStyleData: const ButtonStyleData(
                height: 60,
                padding: EdgeInsets.symmetric(horizontal: 16),
              ),
              dropdownStyleData: DropdownStyleData(
                maxHeight: 250,
                width: dropdownWidth, // 40% of screen width
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                ),
                offset: Offset((screenWidth * 0.6), 0), // align dropdown to right
              ),
            ),
          ),

          const SizedBox(height: 15),

          // Input field for entering the amount
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: const InputDecoration(
              labelText: "Amount",
              labelStyle: TextStyle(color: Colors.black), // Default label color
              floatingLabelStyle: TextStyle(color: Colors.black), // Focused label color
              border: OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Color.fromARGB(255, 165, 35, 226),
                  width: 2.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),

          // Save button
          Center(
            child: isSavingNewCat
                ? ElevatedButton(
                    onPressed: () async {
                      if (selectedCategory == null || amountController.text.isEmpty) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Please select a category and enter an amount."),
                          ),
                        );
                        return;
                      }

                      setState(() => isSavingNewCat = false);

                      try {
                        final userId = FirebaseAuth.instance.currentUser!.uid;
                        final firestore = FirebaseFirestore.instance;

                        final planQuery = await firestore
                            .collection('budget_plans')
                            .doc(userId)
                            .collection(widget.selectedType)
                            .where('budgetPlanName', isEqualTo: widget.planName)
                            .limit(1)
                            .get();

                        if (planQuery.docs.isEmpty || !mounted) return;

                        final planRef = planQuery.docs.first.reference;
                        await planRef.collection('budget_contents').add({
                          'Category': selectedCategory,
                          'Amount': double.parse(amountController.text),
                          'Remaining': double.parse(amountController.text),
                          'Spent': 0.0,
                        });

                        if (!mounted) return;

                        await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              backgroundColor: const Color.fromARGB(255, 165, 35, 226),
                              title: const Text('Success', style: TextStyle(color: Colors.white),),
                              content: const Text('Category saved successfully!', style: TextStyle(color: Colors.white),),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK', style: TextStyle(color: Colors.white),),
                                ),
                              ],
                            );
                          },
                        );

                        if (!mounted) return;
                        Navigator.pop(context);
                        widget.onBudgetAdded();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error: $e")),
                        );
                      } finally {
                        if (mounted) setState(() => isSavingNewCat = true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      backgroundColor: purpleColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      "Save",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ) : const CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)) 
          ),
        ],
      );
  }
}




