import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'main.dart';
import 'ai_page.dart';
import 'budgeting_page.dart';
import 'expenseRecord_page.dart';
import 'dataVisual_page.dart';
import 'settings_page.dart'; 
import 'transaction_details_page.dart';

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
    triggerBudgetBackgroundTask();
    _fetchUsername();
    _fetchExpenseIncomeForCurrentMonth();  // Fetch both monthly expense and income
    _fetchExpensesSummary(); // Check and repeat transactions
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
        setState(() {
            monthlyExpense = value;
          });
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
    final formattedDate = DateFormat('dd-MM-yyyy').format(now); // e.g., 20-04-2025
    logger.i("Fetching today's expenses and incomes for user: ${user.uid}, Month: $formattedMonth, Date: $formattedDate");

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
      String docID = doc.id;

      logger.i("Fetched expense - Category: $category, Amount: $amount");

      todayFetchedExpenses.add({
        'docID': docID,
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
      String docID = doc.id;

      todayFetchedIncomes.add({
        'docID': docID,
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

  Future<void> _fetchExpensesSummary() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userId = user.uid;
    final today = DateTime.now();

    try {
      if (!mounted) return;
      setState(() {
        isLoading = true;
      });

      final currentMonth = _getMonthAbbreviation(today.month);

      // Update the monthly data for income and expense
      final income = await _fetchMonthlyData(
        userId: userId,
        month: currentMonth,
        collectionName: 'incomes',
        fieldName: 'Monthly_Income',
      );

      final expense = await _fetchMonthlyData(
        userId: userId,
        month: currentMonth,
        collectionName: 'expenses',
        fieldName: 'Monthly_Expense',
      );

      // Optionally refresh today's view
      if (mounted) {
        await _fetchTodayExpenseIncome();
      }

      if (mounted) {
        setState(() {
          monthlyIncome = income;
          monthlyExpense = expense;
          isLoading = false;
        });
      }

      logger.i("Updated monthly income and expense.");
    } catch (e) {
      logger.e("Failed to update monthly data: $e");

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
            transitionDuration: Duration.zero, 
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
          ? const Center(child: CircularProgressIndicator(color: Color.fromARGB(255, 165, 35, 226)))
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
                            toY: monthlyIncome, 
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
                            toY: monthlyExpense, 
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
  final logger = Logger();
  return SizedBox(
    height: 300,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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

          // Scrollable list
          Expanded(
            child: ListView.builder(
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final txn = transactions[index];
                return GestureDetector(
                  onTap: () {
                    final docId = txn['docID'];
                    if (docId != null) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => TransactionDetailsPage(
                            documentID: docId,
                            label: label,
                          ),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    } else {
                      logger.w("docID is null for this transaction.");
                    }
                  },
                  child: Padding(
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

