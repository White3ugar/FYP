  // for usage in home_page.dart
  // define this function and call it at initState()  
  
  // Function to check and repeat transactions;
  // This function checks for recurring transactions and creates new ones if needed
  // Future<void> checkAndRepeatTransactions() async {
  //   final user = _auth.currentUser;
  //   if (user == null) return;

  //   final userId = user.uid;
  //   final today = DateTime.now();
  //   final oriDate = today;

  //   try {
  //     if (!mounted) return;
  //     setState(() {
  //       isLoading = true;
  //     });

  //     // Get recurring transactions for both income and expense
  //     final incomeRecurringSnapshot = await _firestore
  //         .collection('incomes')
  //         .doc(userId)
  //         .collection('Recurring')
  //         .get();

  //     final expenseRecurringSnapshot = await _firestore
  //         .collection('expenses')
  //         .doc(userId)
  //         .collection('Recurring')
  //         .get();

  //     // Combine both snapshots
  //     final combinedRecurringDocs = [
  //       ...incomeRecurringSnapshot.docs
  //           .map((doc) => {'doc': doc, 'type': 'incomes'}),
  //       ...expenseRecurringSnapshot.docs
  //           .map((doc) => {'doc': doc, 'type': 'expenses'}),
  //     ];

  //     for (var entry in combinedRecurringDocs) {
  //       final recurringTransactionDoc = entry['doc'] as QueryDocumentSnapshot; // Document reference
  //       final recurringTransactionDataFields = recurringTransactionDoc.data() as Map<String, dynamic>?; // Data map

  //       if (recurringTransactionDataFields == null) continue; // skip if data is null

  //       final repeatType = recurringTransactionDataFields['repeat'];
  //       final lastRepeated = recurringTransactionDataFields['lastRepeated'];
  //       final description = recurringTransactionDataFields['description'];
  //       final List<String> selectedBudgetPlans = recurringTransactionDataFields['budgetPlans'] != null
  //           ? List<String>.from(recurringTransactionDataFields['budgetPlans'])
  //           : [];

  //       if (repeatType == 'None' || repeatType == null || lastRepeated == null) {
  //         continue;
  //       }

  //       final lastRepeatedDate = (lastRepeated is Timestamp)
  //           ? lastRepeated.toDate()
  //           : DateTime.tryParse(lastRepeated.toString()) ?? today;

  //       // Calculate the total number of days since the last repeated date
  //       int daysDifference = today.difference(lastRepeatedDate).inDays;

  //       // Loop over the days to repeat transactions for each missed day
  //       for (int i = 1; i <= daysDifference; i++) {
  //         final dateToRepeat = lastRepeatedDate.add(Duration(days: i));

  //         // Determine if the transaction should repeat on this day
  //         bool shouldRepeat = false;
  //         if (repeatType == 'Daily') {
  //           shouldRepeat = true;
  //         } else if (repeatType == 'Weekly') {
  //           shouldRepeat = dateToRepeat.difference(lastRepeatedDate).inDays >= 7;
  //         } else if (repeatType == 'Monthly') {
  //           shouldRepeat = dateToRepeat.month != lastRepeatedDate.month ||
  //               dateToRepeat.year != lastRepeatedDate.year;
  //         } 
          
  //         if (shouldRepeat) {
  //           final amount = (recurringTransactionDataFields['amount'] ?? 0).toDouble();
  //           final category = recurringTransactionDataFields['category'];

  //           final collectionPath = recurringTransactionDoc.reference.path.contains('incomes') ? 'incomes' : 'expenses';
  //           logger.i("home_page Line 292: Collection path is $collectionPath");
  //           final monthAbbr = _getMonthAbbreviation(today.month);

  //           final newTransaction = {
  //             'userId': userId,
  //             'amount': amount,
  //             'repeat': repeatType,
  //             'category': category,
  //             'description': description,
  //             'date': dateToRepeat,
  //             'lastRepeated': oriDate,
  //           };

  //           if (collectionPath == 'expenses') {
  //             newTransaction['budgetPlans'] = selectedBudgetPlans;
  //           }

  //           final userDocRef = _firestore.collection(collectionPath).doc(userId); // Reference to the user's document for the collection expenses or incomes
  //           final dateCollectionRef = userDocRef
  //               .collection('Months')
  //               .doc(monthAbbr)
  //               .collection("${dateToRepeat.day.toString().padLeft(2, '0')}-${dateToRepeat.month.toString().padLeft(2, '0')}-${dateToRepeat.year}");

  //           await dateCollectionRef.add(newTransaction);

  //           final monthlyRef = userDocRef.collection('Months').doc(monthAbbr);
  //           final monthlySnapshot = await monthlyRef.get();

  //           String totalKey = collectionPath == 'incomes' ? 'Monthly_Income' : 'Monthly_Expense';
  //           double currentTotal = 0;
  //           if (monthlySnapshot.exists) {
  //             final monthlyData = monthlySnapshot.data() ?? {};
  //             currentTotal = (monthlyData[totalKey] ?? 0).toDouble();
  //           }

  //           // Update the monthly total for income or expense
  //           await monthlyRef.set({
  //             totalKey: currentTotal + amount,
  //           }, SetOptions(merge: true));

  //           // Update the last repeated date in the recurring transaction document
  //           await recurringTransactionDoc.reference.update({'lastRepeated': dateToRepeat});
  //         }
  //       }
  //     }

  //     // Update the monthly data for income and expense
  //     final income = await _fetchMonthlyData(
  //       userId: userId,
  //       month: _getMonthAbbreviation(today.month),
  //       collectionName: 'incomes',
  //       fieldName: 'Monthly_Income',
  //     );

  //     final expense = await _fetchMonthlyData(
  //       userId: userId,
  //       month: _getMonthAbbreviation(today.month),
  //       collectionName: 'expenses',
  //       fieldName: 'Monthly_Expense',
  //     );

  //     if (mounted) {
  //       await _fetchTodayExpenseIncome(); // refresh today's view
  //     }

  //     if (mounted) {
  //       setState(() {
  //         monthlyIncome = income;
  //         monthlyExpense = expense;
  //         isLoading = false;
  //       });
  //     }

  //     logger.i("Done to check recurring transactions");
  //   } catch (e) {
  //     logger.e("Failed to check recurring transactions: $e");

  //     if (mounted) {
  //       setState(() {
  //         isLoading = false;
  //       });
  //     }
  //   }
  // }