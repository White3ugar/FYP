import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'transaction_details_page.dart';

class ViewTransactionsPage extends StatefulWidget {
  const ViewTransactionsPage({super.key});

  @override
  State<ViewTransactionsPage> createState() => _ViewTransactionsPageState();
}

class _ViewTransactionsPageState extends State<ViewTransactionsPage> {
  String selectedType = 'Income';
  DateTimeRange? selectedRange;
  List<Map<String, dynamic>> transactions = [];

  void _refreshCategories() {
    setState(() {
      transactions.clear();
      selectedRange = null;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(start: now, end: now);
    final newRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: 'Select up to 7 days',
    );

    if (newRange != null &&
        newRange.duration.inDays <= 6) {
      setState(() {
        selectedRange = newRange;
      });
      await _fetchTransactions();
    } else if (newRange != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a range of 7 days or less.')),
      );
    }
  }

  Future<void> _fetchTransactions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || selectedRange == null) return;

    final collectionType = selectedType.toLowerCase(); // 'income' or 'expense'
    final userId = user.uid;
    final firestore = FirebaseFirestore.instance;

    final start = selectedRange!.start;
    final end = selectedRange!.end;

    List<Map<String, dynamic>> fetched = [];

    for (int i = 0; i <= end.difference(start).inDays; i++) {
      final date = start.add(Duration(days: i));
      final month = DateFormat('MMM').format(date);
      final dateKey = DateFormat('dd-MM-yyyy').format(date);

      final snapshot = await firestore
         .collection('${collectionType}s') // incomes or expenses
          .doc(userId)
          .collection('Months')
          .doc(month)
          .collection(dateKey)
          .get();

      for (var doc in snapshot.docs) {
        fetched.add({
          'id': doc.id,
          ...doc.data(),
        });
      }
    }

    setState(() {
      transactions = fetched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final logger = Logger();
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Transactions'),
        //backgroundColor: const Color.fromARGB(255, 165, 35, 226),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Type Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['Income', 'Expense'].map((type) {
                return ChoiceChip(
                  label: Text(
                    type,
                    style: TextStyle(
                      color: selectedType == type ? Colors.white : const Color.fromARGB(255, 165, 35, 226),
                    ),
                  ),
                  selected: selectedType == type,
                  selectedColor: const Color.fromARGB(255, 165, 35, 226),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color:Color.fromARGB(255, 165, 35, 226)),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() {
                      selectedType = type;
                      _refreshCategories();
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Date Picker Button
           ElevatedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range, color: Colors.white),
            label: Text(
              selectedRange == null
                  ? 'Select Date Range'
                  : '${DateFormat('dd MMM').format(selectedRange!.start)} - ${DateFormat('dd MMM').format(selectedRange!.end)}',
              style: const TextStyle(color: Colors.white), // Text color
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 165, 35, 226),
              foregroundColor: Colors.white, // This applies to icon & text
            ),
          ),

            const SizedBox(height: 20),

            // Results
            Expanded(
              child: transactions.isEmpty
                  ? const Center(child: Text('No transactions found.'))
                  : ListView.builder(
                      itemCount: transactions.length,
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final description = tx['description']?.toString() ?? '';
                        final hasDescription = description.trim().isNotEmpty;

                        return Card(
                          child: ListTile(
                            title: Text(tx['category']?.toString() ?? 'No Category'),
                            subtitle: hasDescription ? Text(description) : null,
                            trailing: Text("RM ${tx['amount']?.toString() ?? '0'}"),
                            onTap: () {
                              final docId = tx['id'];
                              final collectionLabel = '${selectedType}s'; // 'incomes' or 'expenses'

                              logger.i('Tapped transaction - Type: $collectionLabel, Doc ID: $docId');

                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (_, __, ___) => TransactionDetailsPage(
                                    documentID: docId as String,
                                    label: collectionLabel,
                                  ),
                                  transitionDuration: Duration.zero,
                                  reverseTransitionDuration: Duration.zero,
                                ),
                              );
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),        
                          ),
                          ),
                        );
                      },
                    ),
            ),  
          ],
        ),
      ),
    );
  }
}