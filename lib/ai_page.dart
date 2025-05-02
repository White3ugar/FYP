import 'package:flutter/material.dart';
import 'home_page.dart';
import 'budgeting_page.dart';
import 'expenseRecord_page.dart';
import 'dataVisual_page.dart'; 

class AIPage extends StatelessWidget {
  const AIPage({super.key});

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double iconSize = screenWidth * 0.08; // Adjust size as needed

    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Page"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Clear page stack and return to HomePage
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
                transitionDuration: Duration.zero, // Remove transition animation
                reverseTransitionDuration: Duration.zero, // Remove back animation
              ),
              (route) => false,
            );
          },
        ),
      ),
      body: const Center(
        child: Text(
          "AI Page",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      bottomNavigationBar: _buildBottomAppBar(context, iconSize),
    );
  }

  // Bottom App Bar
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
              _buildNavIconWithCaption(context, "assets/icon/chatbot.png", "AI", iconSize, const AIPage(),fontWeight: FontWeight.w900),
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
