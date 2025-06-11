import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class TransactionDetailsPage extends StatefulWidget {
  final String documentID;
  final String label; // "Incomes" or "Expenses"

  const TransactionDetailsPage({
    super.key,
    required this.documentID,
    required this.label,
  });

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  final logger = Logger();
  Map<String, dynamic>? transactionData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTransactionDetails();
  }

  Future<void> _fetchTransactionDetails() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final formattedMonth = DateFormat('MMM').format(now); // e.g., Jun
    final formattedDate = DateFormat('dd-MM-yyyy').format(now); // e.g., 06-06-2025

    final type = widget.label.toLowerCase(); // 'expenses' or 'incomes'
    final docId = widget.documentID;

    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection(type)
          .doc(user.uid)
          .collection('Months')
          .doc(formattedMonth)
          .collection(formattedDate)
          .doc(docId)
          .get();

      if (docSnapshot.exists) {
        setState(() {
          transactionData = docSnapshot.data();
          isLoading = false;
        });
        logger.i("Transaction data fetched: ${transactionData.toString()}");
      } else {
        logger.w("Document does not exist.");
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      logger.e("Error fetching transaction: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<String?> _getCategoryIconPath(String categoryName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final isExpense = widget.label.toLowerCase().contains("expense");
    final categoryTypeDoc = isExpense ? "Expense categories" : "Income categories";

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Categories')
          .doc(user.uid)
          .collection('Transaction Categories')
          .doc(categoryTypeDoc)
          .get();

      if (snapshot.exists) {
        final categories = snapshot.data()?['categoryNames'] as List<dynamic>?;
        final match = categories?.firstWhere(
          (cat) => cat['name'] == categoryName,
          orElse: () => null,
        );
        return match?['icon'] as String?;
      }
    } catch (e) {
      logger.e("Error fetching category icon: $e");
    }
    return null;
  }

  Widget _buildDataField(String title, dynamic value) {
    final double screenHeight = MediaQuery.of(context).size.height;

    // Handle special case for "Image" field
    if (title == "Image") {
      final imageUrl = value?.toString();
      final category = transactionData?['category'];

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: FutureBuilder<String?>(
          future: (imageUrl == null || imageUrl.isEmpty)
              ? _getCategoryIconPath(category)
              : Future.value(imageUrl),
          builder: (context, snapshot) {
            final imageToShow = snapshot.data;
            if (imageToShow == null || imageToShow.isEmpty) {
              return const Text("No image or icon available");
            }

            final isNetworkImage = imageToShow.startsWith("http");

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: isNetworkImage
                      ? Image.network(
                          imageToShow,
                          width: double.infinity,
                          height: screenHeight * 0.24,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text("Failed to load image"),
                        )
                      : Image.asset(
                          imageToShow,
                          width: double.infinity,
                          height: screenHeight * 0.24,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text("Failed to load icon"),
                        ),
                ),
              ],
            );
          },
        ),
      );
    }

    // Convert value to displayable string
    String displayValue;
    if (value == null) {
      displayValue = "-";
    } else if (value is Timestamp) {
      final dateTime = value.toDate();
      displayValue = DateFormat('dd MMM yyyy, hh:mm a').format(dateTime);
    } else if (value is List) {
      displayValue = value.isEmpty ? "-" : value.join(', ');
    } else {
      displayValue = value.toString();
    }

    // Special case for "Description" to stack title above value
    if (title == "Description") {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                "$title:",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 165, 35, 226),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Value in a container
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                height: screenHeight * 0.08,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  border: Border.all(color: const Color.fromARGB(255, 165, 35, 226)),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  displayValue,
                  style: const TextStyle(
                    color: Color.fromARGB(255, 165, 35, 226),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default: Title and value in one row
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title with left padding
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              "$title: ",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 165, 35, 226),
              ),
            ),
          ),
          // Value
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 200,
                height: 40,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  border: Border.all(color: const Color.fromARGB(255, 165, 35, 226)),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Text(
                    displayValue,
                    style: const TextStyle(
                      color: Color.fromARGB(255, 165, 35, 226),
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

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 239, 179, 236),
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Color.fromARGB(255, 165, 35, 226), // Back button color
        ),
        title: Text(
          '${widget.label == 'Expenses' ? 'Expense' : widget.label == 'Incomes' ? 'Income' : widget.label} Details',
          style: const TextStyle(
            color: Color.fromARGB(255, 165, 35, 226),
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 239, 179, 236),
        elevation: 0,
      ),
      body: isLoading
          ? const Center(
            child: CircularProgressIndicator(
              color: Color.fromARGB(255, 165, 35, 226),
            ),
          )
          : transactionData == null
              ? const Center(child: Text("No data found"))
              : Stack(
                  children: [
                    // Top Light Pink Section
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: const Color.fromARGB(255, 239, 179, 236),
                        height: screenHeight * 0.33,
                        alignment: Alignment.center,
                        child:  _buildDataField("Image", transactionData!['imageUrl']),
                      ),
                    ),

                    // Bottom Rounded Gradient Section
                    Positioned(
                      top: screenHeight * 0.33 - 40,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
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
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDataField("Category", transactionData!['category']),
                                _buildDataField("Amount", transactionData!['amount']),                                
                                _buildDataField("Date", transactionData!['date']),                                
                                if (widget.label == "Expenses") ...[
                                  _buildDataField("Budget Plans", transactionData!['budgetPlans']),
                                ],
                                _buildDataField("Repeat", transactionData!['repeat']),
                                _buildDataField("Description", transactionData!['description']),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

}
