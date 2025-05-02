import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'main.dart';
import 'ai_page.dart';
import 'budgeting_page.dart';
import 'expenseRecord_page.dart';
import 'dataVisual_page.dart';
import 'Settings_page.dart'; 
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger logger = Logger();

  // PageController for the charts
  // This controller is used to switch between different charts
  final PageController _chartPageController = PageController();
  int _currentChartPage = 0;

  // PageController for the transactions
  // This controller is used to switch between different transaction lists
  final PageController _pageController = PageController();
  int _currentPage = 0; // Variable to track the current page
  

  String? username;
  bool isLoading = true;
  double monthlyExpense = 0.0;  // Variable to hold the monthly expense
  double monthlyIncome = 0.0;   // Variable to hold the monthly income
  double todayExpense = 0.0;  // Variable to hold today's expense
  double todayIncome = 0.0; // Variable to hold today's income
  //List<Map<String, dynamic>> todayExpenseList = [];
  List<Map<String, dynamic>> fetchedExpenses = []; // List to hold fetched expenses
  List<Map<String, dynamic>> fetchedIncomes = []; // List to hold fetched incomes

  @override
  void initState() {
    super.initState();
    _fetchUsername();
    _fetchExpenseIncomeForCurrentMonth();  // Fetch both monthly expense and income
    checkAndRepeatTransactions(); // Check and repeat transactions
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Fetch Username for the current user
  Future<void> _fetchUsername() async {
    try {
      QuerySnapshot querySnapshot = await _firestore.collection('users').get();

      for (var doc in querySnapshot.docs) {
        if (doc["email"] == _auth.currentUser?.email) {
          if (!mounted) return;
          if (mounted) {
            setState(() {
              username = doc["username"];
            });
          }
          return;
        }
      }
      if (!mounted) return;
      if (mounted) {
        setState(() {
          username = "Missing Username";
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (mounted) {
        setState(() {
          username = "Error Fetching Username";
        });
      }
    }
  }

  // Unified function to fetch both monthly expense and income
  Future<void> _fetchExpenseIncomeForCurrentMonth() async {
    String userId = _auth.currentUser!.uid;
    DateTime currentDate = DateTime.now();
    String currentMonth = _getMonthAbbreviation(currentDate.month);

    // Fetching both monthly expense and income in parallel
    await Future.wait([
      _fetchMonthlyData(
        userId: userId,
        month: currentMonth,
        collectionName: 'expenses',
        fieldName: 'Monthly_Expense',
      ).then((value) {
        if (!mounted) return;
        if (mounted) {
          setState(() {
            monthlyExpense = value;
          });
        }
      }),
      _fetchMonthlyData(
        userId: userId,
        month: currentMonth,
        collectionName: 'incomes',
        fieldName: 'Monthly_Income',
      ).then((value) {
        if (!mounted) return;
        if (mounted) {
          setState(() {
            monthlyIncome = value;
          });
        }
      }),
    ]);
    if (!mounted) return;
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  // Generalized function for fetching monthly data (expense or income)
  Future<double> _fetchMonthlyData({
    required String userId,
    required String month,            // e.g., "Apr"
    required String collectionName,  // "expenses" or "incomes"
    required String fieldName,       // "Monthly_Expense" or "Monthly_Income"
  }) async {
    try {
      DocumentReference monthRef = _firestore
          .collection(collectionName)  // e.g., 'expenses'
          .doc(userId)                 // userId document
          .collection('Months')        // Months subcollection
          .doc(month);                // e.g., 'Apr'

      DocumentSnapshot snapshot = await monthRef.get();

      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

        if (data.containsKey(fieldName)) {
          logger.i("home_page: $fieldName for $month: ${data[fieldName]}");
          return (data[fieldName] as num).toDouble();
        }
      }
    } catch (e) {
      logger.e("Error fetching $fieldName for $month: $e");
    }

    return 0.0; // Return 0 if not found or error
  }

  // Fetch today's expense and income
  Future<void> _fetchTodayExpenseIncome() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final formattedMonth = DateFormat('MMM').format(now); // e.g., Apr
    final formattedDate = DateFormat('d-MM-yyyy').format(now); // e.g., 20-04-2025

    double expenseTotal = 0.0;
    double incomeTotal = 0.0;
    List<Map<String, dynamic>> todayFetchedExpenses = []; // List to hold today's fetched expenses
    List<Map<String, dynamic>> todayFetchedIncomes = []; // List to hold today's fetched incomes

    // Fetch expenses
    final expenseSnapshot = await FirebaseFirestore.instance
        .collection('expenses')
        .doc(user.uid)
        .collection('Months')
        .doc(formattedMonth)
        .collection(formattedDate)
        .get();

    // Add the category and amount to the list "todayFetchedExpenses"
    for (var doc in expenseSnapshot.docs) {
      double amount = (doc['amount'] as num).toDouble();
      String category = doc['category'] ?? 'Unknown';
      todayFetchedExpenses.add({
        'category': category,
        'amount': amount,
      });
      expenseTotal += amount;
    }

    // Fetch incomes
    final incomeSnapshot = await FirebaseFirestore.instance
        .collection('incomes')
        .doc(user.uid)
        .collection('Months')
        .doc(formattedMonth)
        .collection(formattedDate)
        .get();

    // Add the category and amount to the list "todayFetchedIncomes"
    for (var doc in incomeSnapshot.docs) {
      double amount = (doc['amount'] as num).toDouble();
      String category = doc['category'] ?? 'Unknown';
      todayFetchedIncomes.add({
        'category': category,
        'amount': amount,
      });
      incomeTotal += amount;
    }

    if (mounted){
      setState(() {
        todayExpense = expenseTotal;
        todayIncome = incomeTotal;
        // todayExpenseList = todayFetchedExpenses;
        fetchedExpenses = todayFetchedExpenses;
        fetchedIncomes = todayFetchedIncomes;
      });
    }  
  }

    // Helper function to get month name abbreviation
  String _getMonthAbbreviation(int monthNumber) {
    const monthAbbreviations = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return monthAbbreviations[monthNumber - 1];
  }

  // Function to check and repeat transactions
  // This function checks for recurring transactions and creates new ones if needed
  Future<void> checkAndRepeatTransactions() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final today = DateTime.now();
    final oriDate = today;

    try {
      if (!mounted) return;
      setState(() {
        isLoading = true;
      });

      // Get recurring transactions for both income and expense
      final incomeRecurringSnapshot = await _firestore
          .collection('incomes')
          .doc(userId)
          .collection('Recurring')
          .get();

      final expenseRecurringSnapshot = await _firestore
          .collection('expenses')
          .doc(userId)
          .collection('Recurring')
          .get();

      // Combine both snapshots
      final combinedRecurringDocs = [
        ...incomeRecurringSnapshot.docs
            .map((doc) => {'doc': doc, 'type': 'incomes'}),
        ...expenseRecurringSnapshot.docs
            .map((doc) => {'doc': doc, 'type': 'expenses'}),
      ];

      for (var entry in combinedRecurringDocs) {
        final recurringTransactionDoc = entry['doc'] as QueryDocumentSnapshot; // Document reference
        final recurringTransactionDataFields = recurringTransactionDoc.data() as Map<String, dynamic>?; // Data map

        if (recurringTransactionDataFields == null) continue; // skip if data is null

        final repeatType = recurringTransactionDataFields['repeat'];
        final lastRepeated = recurringTransactionDataFields['lastRepeated'];
        final description = recurringTransactionDataFields['description'];
        final List<String> selectedBudgetPlans = recurringTransactionDataFields['budgetPlans'] != null
            ? List<String>.from(recurringTransactionDataFields['budgetPlans'])
            : [];

        if (repeatType == 'None' || repeatType == null || lastRepeated == null) {
          continue;
        }

        final lastRepeatedDate = (lastRepeated is Timestamp)
            ? lastRepeated.toDate()
            : DateTime.tryParse(lastRepeated.toString()) ?? today;

        // Calculate the total number of days since the last repeated date
        int daysDifference = today.difference(lastRepeatedDate).inDays;

        // Loop over the days to repeat transactions for each missed day
        for (int i = 1; i <= daysDifference; i++) {
          final dateToRepeat = lastRepeatedDate.add(Duration(days: i));

          // Determine if the transaction should repeat on this day
          bool shouldRepeat = false;
          if (repeatType == 'Daily') {
            shouldRepeat = true;
          } else if (repeatType == 'Weekly') {
            shouldRepeat = dateToRepeat.difference(lastRepeatedDate).inDays >= 7;
          } else if (repeatType == 'Monthly') {
            shouldRepeat = dateToRepeat.month != lastRepeatedDate.month ||
                dateToRepeat.year != lastRepeatedDate.year;
          } 
          
          if (shouldRepeat) {
            final amount = (recurringTransactionDataFields['amount'] ?? 0).toDouble();
            final category = recurringTransactionDataFields['category'];

            final collectionPath = recurringTransactionDoc.reference.path.contains('incomes') ? 'incomes' : 'expenses';
            logger.i("home_page Line 292: Collection path is $collectionPath");
            final monthAbbr = _getMonthAbbreviation(today.month);

            final newTransaction = {
              'userId': userId,
              'amount': amount,
              'repeat': repeatType,
              'category': category,
              'description': description,
              'date': dateToRepeat,
              'lastRepeated': oriDate,
            };

            if (collectionPath == 'expenses') {
              newTransaction['budgetPlans'] = selectedBudgetPlans;
            }

            final userDocRef = _firestore.collection(collectionPath).doc(userId); // Reference to the user's document for the collection expenses or incomes
            final dateCollectionRef = userDocRef
                .collection('Months')
                .doc(monthAbbr)
                .collection("${dateToRepeat.day.toString().padLeft(2, '0')}-${dateToRepeat.month.toString().padLeft(2, '0')}-${dateToRepeat.year}");

            await dateCollectionRef.add(newTransaction);

            final monthlyRef = userDocRef.collection('Months').doc(monthAbbr);
            final monthlySnapshot = await monthlyRef.get();

            String totalKey = collectionPath == 'incomes' ? 'Monthly_Income' : 'Monthly_Expense';
            double currentTotal = 0;
            if (monthlySnapshot.exists) {
              final monthlyData = monthlySnapshot.data() ?? {};
              currentTotal = (monthlyData[totalKey] ?? 0).toDouble();
            }

            // Update the monthly total for income or expense
            await monthlyRef.set({
              totalKey: currentTotal + amount,
            }, SetOptions(merge: true));

            // Update the last repeated date in the recurring transaction document
            await recurringTransactionDoc.reference.update({'lastRepeated': dateToRepeat});
          }
        }
      }

      // Update the monthly data for income and expense
      final income = await _fetchMonthlyData(
        userId: userId,
        month: _getMonthAbbreviation(today.month),
        collectionName: 'incomes',
        fieldName: 'Monthly_Income',
      );

      final expense = await _fetchMonthlyData(
        userId: userId,
        month: _getMonthAbbreviation(today.month),
        collectionName: 'expenses',
        fieldName: 'Monthly_Expense',
      );

      if (mounted) {
        await _fetchTodayExpenseIncome(); // refresh today's view
      }

      if (mounted) {
        setState(() {
          monthlyIncome = income;
          monthlyExpense = expense;
          isLoading = false;
        });
      }

      logger.i("Done to check recurring transactions");
    } catch (e) {
      logger.e("Failed to check recurring transactions: $e");

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Logout function
  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    logger.i("User logged out successfully.");
    if (mounted) {
      Future.delayed(Duration.zero, () {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
            transitionDuration: Duration.zero, // No animation
            reverseTransitionDuration: Duration.zero,
          ),
          (route) => false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double iconSize = screenWidth * 0.08;

    final List<Map<String, dynamic>> todayExpenses = fetchedExpenses;
    final List<Map<String, dynamic>> todayIncomes = fetchedIncomes;

    return Scaffold(
      appBar: AppBar(
        title: isLoading ? null : Text(
          "Good Day! $username",
          style: const TextStyle(
            color: Color.fromARGB(255, 165, 35, 226),
            fontSize: 23,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 239, 179, 236),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SettingsPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                //  Top Light Pink Section (Charts Section)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: const Color.fromARGB(255, 239, 179, 236),
                    height: screenHeight * 0.33,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _chartPageController,
                            onPageChanged: (index) {
                              setState(() {
                                _currentChartPage = index;
                              });
                            },
                            children: [
                              _buildPieChartSection(),
                              _buildBarChartSection(),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 35), // move dots up
                          child: SmoothPageIndicator(
                            controller: _chartPageController,
                            count: 2,
                            effect: const WormEffect(
                              dotColor: Colors.white,
                              activeDotColor: Color.fromARGB(255, 165, 35, 226),
                              dotHeight: 10,
                              dotWidth: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom purple Gradient Section (Current day transactions)
                Positioned(
                  top: screenHeight * 0.33-40, //Adjust to start right after the yellow section
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
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: (index) =>
                                setState(() => _currentPage = index),
                            children: [
                              _buildTransactionList(todayExpenses, 'Expenses'),
                              _buildTransactionList(todayIncomes, 'Incomes'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SmoothPageIndicator(
                          controller: _pageController,
                          count: 2,
                          effect: const WormEffect(
                            dotColor: Colors.grey,
                            activeDotColor: Colors.purple,
                            dotHeight: 10,
                            dotWidth: 10,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomAppBar(context, iconSize),
    );
  }

  Widget _buildPieChartSection() {
    return Column(
      children: [
        Center(
          child: Text(
            '${DateFormat('MMMM').format(DateTime.now())} Review',
            style: const TextStyle(
              color: Color.fromARGB(255, 165, 35, 226),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 150,
              width: 150,
              child: PieChart(
                PieChartData(
                  sections: [
                    // Expense Section (Red)
                    PieChartSectionData(
                      color: const Color.fromARGB(255, 236, 99, 89),
                      value: monthlyExpense,
                      title: 'Spent',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    // Remaining Income Section (Green)
                    PieChartSectionData(
                      color: const Color.fromARGB(255, 107, 223, 111),
                      value: (monthlyIncome - monthlyExpense).clamp(0, double.infinity),
                      title: 'Left',
                      radius: 50,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  sectionsSpace: 2,
                  centerSpaceRadius: 25,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Left: RM${(monthlyIncome - monthlyExpense).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(255, 165, 35, 226)
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Spent: RM${monthlyExpense.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(255, 165, 35, 226)
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBarChartSection() {
    return Column(
      children: [
        Center(
          child: Text(
            '${DateFormat('MMMM').format(DateTime.now())} Overview',
            style: const TextStyle(
              color: Color.fromARGB(255, 165, 35, 226),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bar Chart
              SizedBox(
                height: 140,
                width: 160,
                child: BarChart(
                  BarChartData(
                    barGroups: [
                      // Left bar to represent Income
                      BarChartGroupData(
                        x: 0,
                        barRods: [
                          BarChartRodData(
                            toY: monthlyIncome, // Now it's the Income on the left
                            color: const Color.fromARGB(255, 107, 223, 111),
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                      //  Right bar to represent Expense
                      BarChartGroupData(
                        x: 1,
                        barRods: [
                          BarChartRodData(
                            toY: monthlyExpense, // Now it's the Expense on the right
                            color: const Color.fromARGB(255, 236, 99, 89),
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, _) {
                            switch (value.toInt()) {
                              case 0:
                                return const Text('Income',  style: TextStyle(fontWeight: FontWeight.w500,color: Color.fromARGB(255, 165, 35, 226))); // label 'Income'
                              case 1:
                                return const Text('Expense',  style: TextStyle(fontWeight: FontWeight.w500,color: Color.fromARGB(255, 165, 35, 226))); // label 'expense'
                              default:
                                return const Text('');
                            }
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    maxY: (monthlyIncome > monthlyExpense
                            ? monthlyIncome
                            : monthlyExpense) +
                        20,
                  ),
                ),
              ),

              const SizedBox(width: 20),

              // Caption Section 
              Expanded(
                child: Column( 
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 35),
                    Text(
                      'Income: RM${monthlyIncome.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 165, 35, 226)
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Expense: RM${monthlyExpense.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 165, 35, 226)
                      ),
                    ),                    
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _buildTransactionList(List<Map<String, dynamic>> transactions, String label) {
  return SizedBox(
    height: 300, // Set a height constraint so the ListView knows its bounds
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Text with Background
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(45),
            ),
            child: Text(
              '${DateFormat('dd MMM').format(DateTime.now()).toUpperCase()} - $label',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 165, 35, 226),
              ),
            ),
          ),
          const SizedBox(height: 15),

          // Scrollable list of transactions
          Expanded(
            child: ListView.builder(
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final txn = transactions[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(45),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          txn['category'],
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color.fromARGB(255, 165, 35, 226),
                          ),
                        ),
                        Text(
                          'RM${txn['amount'].toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: label == 'Expenses' ? Colors.redAccent : Colors.green,
                          ),
                        ),
                      ],
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
    FontWeight fontWeight = FontWeight.w400, // 👈 customizable font weight
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
          color: const Color.fromARGB(255, 165, 35, 226),
          fontWeight: fontWeight,
        ),
      ),
    ],
  );
}

