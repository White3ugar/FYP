import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class viewTransactionsPage extends StatefulWidget {
  const viewTransactionsPage({super.key});

  @override
  State<viewTransactionsPage> createState() => _viewTransactionsPageState();
}

class _viewTransactionsPageState extends State<viewTransactionsPage> {
  String selectedType = 'Income'; // Default selection
  final Color purpleColor = const Color.fromARGB(255, 165, 35, 226);
  final logger = Logger();

  void _refreshCategories() {
    // Placeholder for your refresh logic
    logger.i("Selected type: $selectedType");
    // You could also fetch categories or navigate based on selection here.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Transaction Type'),
        backgroundColor: purpleColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose Type:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              children: ['Income', 'Expense'].map((type) {
                return ChoiceChip(
                  label: Text(
                    type,
                    style: TextStyle(
                      color: selectedType == type ? Colors.white : purpleColor,
                    ),
                  ),
                  selected: selectedType == type,
                  selectedColor: purpleColor,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: purpleColor),
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
            const SizedBox(height: 30),
            Text(
              'Currently Selected: $selectedType',
              style: TextStyle(fontSize: 16, color: purpleColor),
            ),
          ],
        ),
      ),
    );
  }
}
