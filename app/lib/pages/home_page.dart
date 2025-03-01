import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Live_sensor_data.dart';
import 'Zen_corner.dart';
import 'historical_sensor_data.dart';
import 'settings_page.dart';

class Homepage extends StatefulWidget {
  const Homepage({Key? key}) : super(key: key);

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  final user = FirebaseAuth.instance.currentUser!;
  int _selectedIndex = 0; // To track the selected tab

  // List of pages for the Bottom Navigation Bar
  final List<Widget> _pages = [
    LiveSensorData(),
    ZenCorner(),
    HistoricalSensorData(),
    SettingsPage(), // Add settings page to the list
  ];

  // Function to change the tab
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Gradient background
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF74EBD5), // Soft blue-green
              Color(0xFFACB6E5), // Lavender
            ], // Gradient colors
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: IndexedStack(
            index: _selectedIndex,
            children: _pages,
          ), // Using IndexedStack to preserve state when switching tabs
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9), // Light background with opacity for clarity
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30), // Rounded corners for a modern look
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2), // Softer shadow for depth
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed, // This ensures all labels are shown
          selectedItemColor: Color(0xFF6C63FF), // Soft purple for selected items
          unselectedItemColor: Colors.grey[600], // Soft grey for unselected items
          backgroundColor: Colors.transparent, // Transparent background for the nav bar
          elevation: 0, // Removes the default elevation to use our custom shadow
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.graphic_eq),
              label: 'Live Sensor Data',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.spa),
              label: 'Zen Corner',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history),
              label: 'Historical Data',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
