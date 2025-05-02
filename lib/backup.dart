import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:fl_chart/fl_chart.dart';
import 'ai_page.dart';
import 'expenseRecord_page.dart';
import 'budgeting_page.dart';
import 'home_page.dart';

class DataVisualPage extends StatefulWidget {
  const DataVisualPage({super.key});

  @override
  State<DataVisualPage> createState() => _DataVisualPageState();
}

class _DataVisualPageState extends State<DataVisualPage> {
  final logger = Logger();

  bool isIncomeSelected = false; // Default to false (expenses)

  // The variables to store total expenses for each category based on different time periods
  Map<String, Map<String, double>> currentDailyTotals = {}; // Daily expenses by category
  Map<String, Map<String, double>> currentWeeklyTotals = {};  // Weekly expenses by category
  Map<String, Map<String, double>> currentMonthlyTotals = {}; // Monthly expenses by category

  // The variables to store total expenses for each category based on different time periods
  final Map<String, double> dailyExpenseTotals = {};
  final Map<String, double> weeklyExpenseTotals = {};
  final Map<String, double> monthlyExpenseTotals = {};

  final List<bool> _selectedFilters = [true, false, false]; 
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAndGroupExpenses();
  }

  // Fetch and group expenses by date, week, and month
  Future<void> _fetchAndGroupExpenses() async {
    setState(() {
      _isLoading = true;
    });

    final userId = FirebaseAuth.instance.currentUser!.uid;
    final monthsRef = FirebaseFirestore.instance
        .collection('expenses')
        .doc(userId)
        .collection('Months');

    final monthsSnapshot = await monthsRef.get();

    final currentDate = DateTime.now();
    final currentWeek = _getWeekNumber(currentDate);
    final currentMonth = currentDate.month;
    final currentYear = currentDate.year;

    // Clear previous totals
    currentDailyTotals.clear();
    currentWeeklyTotals.clear();
    currentMonthlyTotals.clear();

    dailyExpenseTotals.clear();
    weeklyExpenseTotals.clear();
    monthlyExpenseTotals.clear();

    for (final monthDoc in monthsSnapshot.docs) {
      final monthName = monthDoc.id;
      final monthData = monthDoc.data();
      final List<String> availableDates = List<String>.from(monthData['availableDates'] ?? []);

      for (final dateStr in availableDates) {
        final dateRef = monthsRef.doc(monthName).collection(dateStr);
        final expenseDocs = await dateRef.get();

        logger.i('Expenses for $dateStr:');
        for (final doc in expenseDocs.docs) {
          logger.i(doc.data());
        }

        final dateParts = dateStr.split('-');
        if (dateParts.length != 3) continue;

        final day = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final year = int.parse(dateParts[2]);
        final expenseDate = DateTime(year, month, day);

        // Calculate total expenses for the date
        final totalExpenseForDate = expenseDocs.docs.fold(0.0, (total, doc) {
          final data = doc.data();
          return total + (data['amount'] ?? 0).toDouble();
        });

        // Save totals
        dailyExpenseTotals[dateStr] = totalExpenseForDate;
        final weekKey = "$year-W${_getWeekNumber(expenseDate)}";
        weeklyExpenseTotals[weekKey] = (weeklyExpenseTotals[weekKey] ?? 0) + totalExpenseForDate;
        final monthKey = "$year-${month.toString().padLeft(2, '0')}";
        monthlyExpenseTotals[monthKey] = (monthlyExpenseTotals[monthKey] ?? 0) + totalExpenseForDate;

        // Check if current day/week/month
        if (_isSameDay(expenseDate, currentDate)) {
          _addToCategoryTotals(currentDailyTotals, dateStr, expenseDocs);
        }
        if (_isSameWeek(expenseDate, currentYear, currentWeek)) {
          _addToCategoryTotals(currentWeeklyTotals, "$year-W$currentWeek", expenseDocs);
        }
        if (_isSameMonth(expenseDate, currentYear, currentMonth)) {
          _addToCategoryTotals(currentMonthlyTotals, "$year-${month.toString().padLeft(2, '0')}", expenseDocs);
        }
      }
    }

    logger.i('Current Daily Totals (for Today): $currentDailyTotals');
    logger.i('Current Weekly Totals (for this week): $currentWeeklyTotals');
    logger.i('Current Monthly Totals (for this month): $currentMonthlyTotals');
    logger.i('All Daily Expense Totals: $dailyExpenseTotals');
    logger.i('All Weekly Expense Totals: $weeklyExpenseTotals');
    logger.i('All Monthly Expense Totals: $monthlyExpenseTotals');

    setState(() {
      _isLoading = false;
    });
  }

  // Helper function to add expenses to the appropriate category totals
  void _addToCategoryTotals(Map<String, Map<String, double>> totals, String key, QuerySnapshot expenseDocs) {
    totals.putIfAbsent(key, () => {}); // Ensure there is a map for this day/week/month

    for (final expenseDoc in expenseDocs.docs) {
      final data = expenseDoc.data() as Map<String, dynamic>;

      final String category = data['category'] ?? 'Unknown';
      final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

      // Add to category totals: now grouping by both date and category separately
      if (!totals[key]!.containsKey(category)) {
        totals[key]![category] = 0.0;
      }
      totals[key]![category] = totals[key]![category]! + amount; // Accumulate the amount for each category
    }
  }

  // Helper function to check if the date is the same day
  bool _isSameDay(DateTime date, DateTime currentDate) {
    return date.year == currentDate.year &&
        date.month == currentDate.month &&
        date.day == currentDate.day;
  }

  // Helper function to get week number of the year
  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirst = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirst + firstDayOfYear.weekday) / 7).ceil();
  }

  // Helper function to check if the date is in the same week as the current date
  bool _isSameWeek(DateTime date, int year, int week) {
    final weekNumber = _getWeekNumber(date);
    return year == date.year && week == weekNumber;
  }

  // Helper function to check if the date is in the same month as the current date
  bool _isSameMonth(DateTime date, int year, int month) {
    return year == date.year && month == date.month;
  }

  // Function to load filtered Expense Record based on selected filters(daily, weekly, monthly)
  Map<String, Map<String, double>> _getCurrentTotals() {
    if (_selectedFilters[0]) {
      return currentDailyTotals;
    } else if (_selectedFilters[1]) {
      return currentWeeklyTotals;
    } else {
      return currentMonthlyTotals;
    }
  }

  // Function to build the Pie Chart widget 
Widget _buildExpensePieChart() {
  double screenHeight = MediaQuery.of(context).size.height;
  double loadIconHeight = screenHeight * 0.08;
  double chartHeight = screenHeight * 0.20; 

  if (_isLoading) {
    return Padding(
      padding: EdgeInsets.only(top: loadIconHeight),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  final totals = _getCurrentTotals(); // Now Map<String, Map<String, double>>

  // Group totals by category across all periods
  final Map<String, double> categoryTotals = {};

  for (final periodEntry in totals.entries) {
    final periodCategories = periodEntry.value; // Map<String, double>

    periodCategories.forEach((category, amount) {
      categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
    });
  }

  final categories = categoryTotals.keys.toList();
  final values = categoryTotals.values.toList();

  if (categories.isEmpty) {
    return const Center(child: Text('No data available.'));
  }

  return SizedBox(
    height: chartHeight,
    child: PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 0,
        sections: List.generate(categories.length, (index) {
          const double fontSize = 16;
          const double radius = 80;

          return PieChartSectionData(
            color: _getColorForIndex(index),
            value: values[index],
            title: '${categories[index]}\n${values[index].toStringAsFixed(0)}',
            radius: radius,
            titleStyle: const TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: categories.length == 1 ? 0.5 : 0.55,
          );
        }),
      ),
    ),
  );
}

  Color _getColorForIndex(int index) {
    const List<Color> colors = [
      Color(0xff845ec2),
      Color(0xffd65db1),
      Color(0xffff6f91),
      Color(0xffff9671),
      Color(0xfff9f871),
      Color(0xff2c73d2),
      Color(0xff0089ba),
      Color(0xff008e9b),
      Color(0xff008f7a),
    ];
    return colors[index % colors.length];
  }

  Widget _buildExpenseLineGraph() {
  double screenHeight = MediaQuery.of(context).size.height;
  double chartHeight = screenHeight * 0.25;

  if (_isLoading) {
    return const Center(child: CircularProgressIndicator());
  }

  final Map<String, double> totals;
  switch (_selectedFilters.indexWhere((element) => element)) {
    case 0:
      totals = dailyExpenseTotals;
      break;
    case 1:
      totals = weeklyExpenseTotals;
      break;
    case 2:
      totals = monthlyExpenseTotals;
      break;
    default:
      totals = {};
  }

  if (totals.isEmpty) {
    return const Center(child: Text('No data available.'));
  }

  final sortedKeys = totals.keys.toList()
    ..sort((a, b) {
      DateTime dateA = _parseDate(a);
      DateTime dateB = _parseDate(b);
      return dateA.compareTo(dateB);
    });

  final spots = sortedKeys.asMap().entries.map((entry) {
    final index = entry.key.toDouble();
    final key = entry.value;
    return FlSpot(index, totals[key]!);
  }).toList();

  return SizedBox(
    height: chartHeight,
    child: LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: Colors.white,
            tooltipBorder: BorderSide(
              color: const Color.fromARGB(255, 165, 35, 226),
              width: 1,
            ),
            tooltipRoundedRadius: 8,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipMargin: 8,
            tooltipPadding: const EdgeInsets.all(8),          
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                final index = touchedSpot.x.toInt();
                final key = (index >= 0 && index < sortedKeys.length) ? sortedKeys[index] : '';
                return LineTooltipItem(
                  '${_formatKey(key)}\n${touchedSpot.y.toStringAsFixed(0)}',
                  const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
          touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
            if (event is FlTapUpEvent || event is FlPanEndEvent) {
              // After user taps or drags and releases, dismiss tooltip after delay
              Future.delayed(const Duration(seconds: 1), () {
                // Force refresh or remove touch indicators
                response?.lineBarSpots?.clear();
              });
            }
          },
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 10,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                int idx = value.toInt();
                if (idx >= 0 && idx < sortedKeys.length) {
                  final key = sortedKeys[idx];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _formatKey(key),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: _calculateInterval(spots),
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(color: Colors.black26),
            bottom: BorderSide(color: Colors.black26),
          ),
        ),
        minX: 0,
        maxX: spots.isNotEmpty ? (spots.length - 1).toDouble() : 0,
        minY: 0,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: const Color.fromARGB(255, 165, 35, 226),
            barWidth: 3,
            isStrokeCapRound: true,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color.fromARGB(255, 165, 35, 226).withOpacity(0.3),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: const Color.fromARGB(255, 165, 35, 226),
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  DateTime _parseDate(String key) {
    try {
      if (key.contains('W')) {
        // It's a weekly format like 2025-W16
        final parts = key.split('-W');
        final year = int.parse(parts[0]);
        final week = int.parse(parts[1]);
        return _firstDateOfWeek(year, week);
      } else if (key.contains('-')) {
        // Monthly or Daily (e.g., 20-04-2025 or 2025-04)
        final parts = key.split('-');
        if (parts.length == 3) {
          return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else if (parts.length == 2) {
          return DateTime(int.parse(parts[0]), int.parse(parts[1]));
        }
      }
    } catch (e) {
      logger.e("Failed to parse date: $key");
    }
    return DateTime.now();
  }

  String _formatKey(String key) {
    if (key.contains('W')) {
      return key.split('-').last; // Just show "W16"
    } else if (key.contains('-')) {
      final parts = key.split('-');
      if (parts.length == 3) {
        return "${parts[0]}/${parts[1]}"; // "20/04"
      } else if (parts.length == 2) {
        return "${parts[1]}"; // Just "04" (Month)
      }
    }
    return key;
  }

  double _calculateInterval(List<FlSpot> spots) {
    if (spots.isEmpty) return 10;
    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    if (maxY <= 10) return 2;
    if (maxY <= 50) return 10;
    if (maxY <= 100) return 20;
    return 50;
  }

  DateTime _firstDateOfWeek(int year, int week) {
    final firstDayOfYear = DateTime(year, 1, 1);
    final daysOffset = (firstDayOfYear.weekday - 1) % 7;
    return firstDayOfYear.add(Duration(days: (week - 1) * 7 - daysOffset));
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = screenWidth * 0.08; 

    return Scaffold(
      appBar: AppBar(
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
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                });
              },
              children: const [
                Text("Daily"),
                Text("Weekly"),
                Text("Monthly"),
              ],
            ),
          ),
          // This is where the Pie Chart will be added
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: _buildExpensePieChart(), // Build the Pie Chart based on the selected filter
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: _buildExpenseLineGraph(), // New Line Chart
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomAppBar(context, iconSize),
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
              _buildNavIconWithCaption(context, "assets/icon/dataVisual.png", "Graphs", iconSize, const DataVisualPage(),fontWeight: FontWeight.w900),
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
            fontWeight: fontWeight, // 👈 apply custom font weight
          ),
        ),
      ],
    );
  }
}