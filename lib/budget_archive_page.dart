import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BudgetArchivePage extends StatefulWidget {
  const BudgetArchivePage({super.key});

  @override
  State<BudgetArchivePage> createState() => _BudgetArchivePageState();
}

class _BudgetArchivePageState extends State<BudgetArchivePage> {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  final List<bool> _selectedFilters = [true, false, false]; // Default: Daily
  final List<Map<String, dynamic>> _archivedBudgets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFilteredBudgets();
  }

  Future<void> _loadFilteredBudgets() async {
    setState(() {
      _archivedBudgets.clear();
    });

    final type = _selectedFilters[0]
        ? 'Daily'
        : _selectedFilters[1]
            ? 'Weekly'
            : 'Monthly';

    final snapshot = await FirebaseFirestore.instance
        .collection('budget_plans')
        .doc(userId)
        .collection(type)
        .where('budgetStatus', isEqualTo: 'Archived')
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final planName = data['budgetPlanName'] ?? 'Unnamed Plan';

      final contentsSnapshot = await doc.reference.collection('budget_contents').get();
      final contents = contentsSnapshot.docs.map((e) => e.data()).toList();

      _archivedBudgets.add({
        'budgetPlanName': planName,
        'budgetContents': contents,
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return "0";
    double? parsedAmount;
    if (amount is String) parsedAmount = double.tryParse(amount);
    if (amount is int) parsedAmount = amount.toDouble();
    if (amount is double) parsedAmount = amount;
    if (parsedAmount == null) return "0";
    return parsedAmount % 1 == 0
        ? parsedAmount.toInt().toString()
        : parsedAmount.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Archived Budgets")),
      body: Column(
        children: [
          // Filter buttons for Daily, Weekly, Monthly
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ToggleButtons(
              borderRadius: BorderRadius.circular(30),
              borderColor: const Color.fromARGB(255, 165, 35, 226),
              selectedBorderColor: const Color.fromARGB(255, 165, 35, 226),
              selectedColor: Colors.white,
              fillColor: const Color.fromARGB(255, 165, 35, 226),
              color: const Color.fromARGB(255, 165, 35, 226),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
              isSelected: _selectedFilters,
              onPressed: (int index) {
                setState(() {
                  for (int i = 0; i < _selectedFilters.length; i++) {
                    _selectedFilters[i] = i == index;
                  }
                  _isLoading = true;
                });
                _loadFilteredBudgets(); // Load filtered data
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
                ? const Center(child: CircularProgressIndicator())
                : _archivedBudgets.isEmpty
                    ? const Center(child: Text("No archived budget plans."))
                    : ListView.builder(
                        itemCount: _archivedBudgets.length,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final item = _archivedBudgets[index];
                          final planName = item['budgetPlanName'] as String;
                          final contents = item['budgetContents'] as List;

                          return Card(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$planName (Archived)',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  ...contents.map((item) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(item['Category'] ?? ''),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text.rich(
                                              TextSpan(
                                                text: 'RM ',
                                                children: [
                                                  TextSpan(
                                                    text: _formatAmount(
                                                        item['Remaining']),
                                                    style: const TextStyle(
                                                        color: Colors.red),
                                                  ),
                                                  const TextSpan(text: ' / '),
                                                  TextSpan(
                                                    text: _formatAmount(
                                                        item['Amount']),
                                                    style: const TextStyle(
                                                        color: Colors.green),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}