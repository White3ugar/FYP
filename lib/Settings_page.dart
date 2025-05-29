import 'package:flutter/material.dart';
import 'home_page.dart'; // Import the HomePage
import 'settings_CategoriesManager.dart'; // Import the CategoriesManagerPage
import 'settings_UserSettings.dart'; // Import the UserSettingsPage

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  //Build a reusable settings tile widget
  Widget buildSettingsTile({
    required String title,
    required VoidCallback onTap,
    IconData icon = Icons.arrow_forward_ios,
    Color color = const Color.fromARGB(255, 165, 35, 226),
  }) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(color: color),
      ),
      trailing: Icon(icon, color: color),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 239, 179, 236), // solid background color
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 239, 179, 236), // solid background color
        title: const Text(
          "Settings",
          style: TextStyle(
            color:  Color.fromARGB(255, 165, 35, 226),
          ),
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
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          buildSettingsTile(
            title: "Categories Manager",
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const CategoriesManagerPage(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
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
          buildSettingsTile(
            title: "User Settings",
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const UserSettingsPage(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
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
          buildSettingsTile(
            title: "Notification Settings",
            onTap: () {
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
