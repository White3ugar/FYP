import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
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

  bool isIncomeSelected = false; // False for expenses, true for incomes

  // Variables to store totals by category for different time periods
  Map<String, Map<String, double>> currentDailyTotals = {}; // Daily totals by category
  Map<String, Map<String, double>> currentWeeklyTotals = {}; // Weekly totals by category
  Map<String, Map<String, double>> currentMonthlyTotals = {}; // Monthly totals by category

  // Variables to store total amounts for each time period
  final Map<String, double> dailyTotals = {};
  final Map<String, double> weeklyTotals = {};
  final Map<String, double> monthlyTotals = {};

  final List<bool> _selectedFilters = [true, false, false]; // Daily, Weekly, Monthly
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAndGroupData();
  }

  // Fetch and group data (expenses or incomes) by date, week, and month
  Future<void> _fetchAndGroupData() async {
    setState(() {
      _isLoading = true;
    });


    logger.i('Line 79: Transaction Selected: ${isIncomeSelected ? "Incomes" : "Expenses"}');
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final collectionName = isIncomeSelected ? 'incomes' : 'expenses';
    final monthsRef = FirebaseFirestore.instance
        .collection(collectionName)
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
    dailyTotals.clear();
    weeklyTotals.clear();
    monthlyTotals.clear();

    for (final monthDoc in monthsSnapshot.docs) {
      final monthName = monthDoc.id;
      final monthData = monthDoc.data();
      final List<String> availableDates = List<String>.from(monthData['availableDates'] ?? []);

      for (final dateStr in availableDates) {
        final dateRef = monthsRef.doc(monthName).collection(dateStr);
        final dataDocs = await dateRef.get();

        logger.i('Line 79: ${isIncomeSelected ? "Incomes" : "Expenses"} for $dateStr:');

        final dateParts = dateStr.split('-');
        if (dateParts.length != 3) continue;

        final day = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final year = int.parse(dateParts[2]);
        final dataDate = DateTime(year, month, day);

        // Calculate total amount for the current date(dateStr)
        final totalForDate = dataDocs.docs.fold(0.0, (total, doc) {
          final data = doc.data();
          return total + (data['amount'] ?? 0).toDouble();
        });

        // Save totals
        dailyTotals[dateStr] = totalForDate;
        final weekKey = "$year-W${_getWeekNumber(dataDate)}";
        weeklyTotals[weekKey] = (weeklyTotals[weekKey] ?? 0) + totalForDate;
        final monthKey = "$year-${month.toString().padLeft(2, '0')}";
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + totalForDate;

        // Check if current day/week/month
        if (_isSameDay(dataDate, currentDate)) {
          _addToCategoryTotals(currentDailyTotals, dateStr, dataDocs);
        }
        if (_isSameWeek(dataDate, currentYear, currentWeek)) {
          _addToCategoryTotals(currentWeeklyTotals, "$year-W$currentWeek", dataDocs);
        }
        if (_isSameMonth(dataDate, currentYear, currentMonth)) {
          _addToCategoryTotals(currentMonthlyTotals, "$year-${month.toString().padLeft(2, '0')}", dataDocs);
        }
      }
    }

    // logger.i('Current Daily Totals (for Today): $currentDailyTotals');
    // logger.i('Current Weekly Totals (for this week): $currentWeeklyTotals');
    // logger.i('Current Monthly Totals (for this month): $currentMonthlyTotals');
    // logger.i('All Daily Totals: $dailyTotals');
    // logger.i('All Weekly Totals: $weeklyTotals');
    // logger.i('All Monthly Totals: $monthlyTotals');

    setState(() {
      _isLoading = false;
    });
  }

  // Helper function to add data to the appropriate category totals
  void _addToCategoryTotals(Map<String, Map<String, double>> totals, String key, QuerySnapshot dataDocs) {
    totals.putIfAbsent(key, () => {});

    for (final dataDoc in dataDocs.docs) {
      final data = dataDoc.data() as Map<String, dynamic>;

      final String category = data['category'] ?? 'Unknown';
      final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

      totals[key]![category] = (totals[key]![category] ?? 0.0) + amount;
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

  // Helper function to check if the date is in the same week
  bool _isSameWeek(DateTime date, int year, int week) {
    final weekNumber = _getWeekNumber(date);
    return year == date.year && week == weekNumber;
  }

  // Helper function to check if the date is in the same month
  bool _isSameMonth(DateTime date, int year, int month) {
    return year == date.year && month == date.month;
  }

  // Function to load filtered data based on selected filters
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
  Widget _buildPieChart() {
    double screenHeight = MediaQuery.of(context).size.height;
    double loadIconHeight = screenHeight * 0.08;
    double chartHeight = screenHeight * 0.20;

    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.only(top: loadIconHeight),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final totals = _getCurrentTotals();

    // Group totals by category across all periods
    final Map<String, double> categoryTotals = {};

    for (final periodEntry in totals.entries) {
      final periodCategories = periodEntry.value;
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

  // Function to build the Line Graph widget
  Widget _buildLineGraph() {
    double screenHeight = MediaQuery.of(context).size.height;
    double chartHeight = screenHeight * 0.25;
    double loadIconHeight = screenHeight * 0.08;


    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.only(top: loadIconHeight),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final Map<String, double> totals;
    switch (_selectedFilters.indexWhere((element) => element)) {
      case 0:
        totals = dailyTotals;
        break;
      case 1:
        totals = weeklyTotals;
        break;
      case 2:
        totals = monthlyTotals;
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
              tooltipBorder: const BorderSide(
                color: Color.fromARGB(255, 165, 35, 226),
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
                Future.delayed(const Duration(seconds: 1), () {
                  response?.lineBarSpots?.clear();
                });
              }
            },
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: false,
            horizontalInterval: 10,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withOpacity(0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  // Formatting the Y-axis value properly
                  final valueToDisplay = value.toInt();
                  return Text(
                    valueToDisplay > 999
                        ? "${(valueToDisplay / 1000).toStringAsFixed(1)}K"
                        : valueToDisplay.toString(),
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
        final parts = key.split('-W');
        final year = int.parse(parts[0]);
        final week = int.parse(parts[1]);
        return _firstDateOfWeek(year, week);
      } else if (key.contains('-')) {
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
    try {
      if (key.contains('W')) {
        // Weekly format: e.g. 2025-W16 → 14–20 Apr
        final parts = key.split('-W');
        final year = int.parse(parts[0]);
        final week = int.parse(parts[1]);

        final firstDay = _firstDateOfWeek(year, week);
        final lastDay = firstDay.add(const Duration(days: 6));

        final dayFormatter = DateFormat('d');
        final monthFormatter = DateFormat('MMM');

        return "${dayFormatter.format(firstDay)}–${dayFormatter.format(lastDay)} ${monthFormatter.format(lastDay)}";
      } else if (key.contains('-')) {
        final parts = key.split('-');
        if (parts.length == 3) {
          // Daily format: e.g. 14-04-2025 → 14/04
          return "${parts[0]}/${parts[1]}";
        } else if (parts.length == 2) {
          // Monthly format: e.g. 2025-04 → Apr
          final month = int.parse(parts[1]);
          return DateFormat.MMM().format(DateTime(0, month));
        }
      }
    } catch (e) {
      logger.e("Failed to format key: $key");
    }

    return key;
  }

  double _calculateInterval(List<FlSpot> spots) {
    if (spots.isEmpty) return 10;
    final maxY = spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    if (maxY <= 10) return 2;
    if (maxY <= 50) return 10;
    if (maxY <= 100) return 20;
    if (maxY <= 1000) return 100;
    if (maxY <= 10000) return 1000;
    return 5000;
  }

  DateTime _firstDateOfWeek(int year, int week) {
    final firstDayOfYear = DateTime(year, 1, 1);
    final daysOffset = (firstDayOfYear.weekday - 1) % 7;
    return firstDayOfYear.add(Duration(days: (week - 1) * 7 - daysOffset));
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    double iconSize = screenWidth * 0.08;

    String chartTitle = "Category breakdown of current ${_selectedFilters.indexWhere((element) => element) == 0 ? 'day' : _selectedFilters.indexWhere((element) => element) == 1 ? 'week' : 'month'} ${isIncomeSelected ? 'income' : 'expense'}";
    String lineChartTitle = "Trends in ${isIncomeSelected ? 'income' : 'expense'} for ${_selectedFilters.indexWhere((element) => element) == 0 ? 'day' : _selectedFilters.indexWhere((element) => element) == 1 ? 'week' : 'month'}";

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
          centerTitle: true,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    isIncomeSelected = false;
                    _fetchAndGroupData(); // Refresh data for expenses
                  });
                },
                child: Image.asset(
                  "assets/icon/spending.png",
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  color: isIncomeSelected ? Colors.grey : null, // Dim when not selected
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    isIncomeSelected = true;
                    _fetchAndGroupData(); // Refresh data for incomes
                  });
                },
                child: Image.asset(
                  "assets/icon/income.png",
                  width: 40,
                  height: 40,
                  fit: BoxFit.contain,
                  color: isIncomeSelected ? null : Colors.grey, // Dim when not selected
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
                      _fetchAndGroupData(); // Refresh data on filter change
                    });
                  },
                  children: const [
                    Text("Daily"),
                    Text("Weekly"),
                    Text("Monthly"),
                  ],
                ),
              ),
              // Pie chart title
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 0, top: 30, bottom: 0),
                child: Text(
                  chartTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color:Color.fromARGB(255, 165, 35, 226)),
                ),
              ),
              // Pie chart
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: _buildPieChart(),
              ),
              // Line chart title
              Padding(
                padding: const EdgeInsets.only(left: 0, right: 0, top: 20, bottom: 10),
                child: Text(
                  lineChartTitle,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,color:Color.fromARGB(255, 165, 35, 226)),
                ),
              ),
              // Line chart
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: _buildLineGraph(),
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
              _buildNavIconWithCaption(context, "assets/icon/record-book.png", "Record", iconSize, const ExpenseRecordPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/budget.png", "Budget", iconSize, const BudgetPage()),
              SizedBox(width: iconSpacing),
              _buildNavIconWithCaption(context, "assets/icon/dataVisual.png", "Graphs", iconSize, const DataVisualPage(), textColor: Colors.deepPurple),
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