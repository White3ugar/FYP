import 'package:flutter/material.dart';
import 'home_page.dart'; // Import the HomePage
import 'Settings_CategoriesManager.dart'; // Import the CategoriesManagerPage

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back), // Back button icon
          onPressed: () {
            // Navigate back to HomePage and clear the page stack
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const HomePage(),
                transitionDuration: Duration.zero, // No animation
                reverseTransitionDuration: Duration.zero,
              ),
              (route) => false, // Removes all routes from the stack
            );
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Categories Manager
          ListTile(
            title: const Text("Categories Manager"),
            trailing: const Icon(Icons.arrow_forward_ios),
            // Inside SettingsPage
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const CategoriesManagerPage(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0); // from right to left
                    const end = Offset.zero;
                    const curve = Curves.easeInOut;

                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                    var offsetAnimation = animation.drive(tween);

                    return SlideTransition(position: offsetAnimation, child: child);
                  },
                ),
              );
            },
          ),
          
          // Users Settings
          ListTile(
            title: const Text("Users Settings"),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Add navigation to the Users Settings page
              // For now, show a placeholder message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Users Settings clicked")),
              );
            },
          ),
          
          // Notification Settings
          ListTile(
            title: const Text("Notification Settings"),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              // Add navigation or functionality for Notification Settings
              // For now, show a placeholder message
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Notification Settings clicked")),
              );
            },
          ),
        ],
      ),
    );
  }
}
