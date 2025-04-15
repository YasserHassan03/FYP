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
  final user = FirebaseAuth.instance.currentUser!; // User is guaranteed to be logged in here
  int _selectedIndex = 0; // Zen Corner is the default tab (first tab)

  // List of pages for the Bottom Navigation Bar
  final List<Widget> _pages = [
    ZenCorner(),
    LiveSensorData(),
    HistoricalSensorData(),
    SettingsPage(),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF74EBD5), // Soft blue-green
              Color(0xFFACB6E5), // Lavender
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: IndexedStack(index: _selectedIndex, children: _pages),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9), // Light background with opacity
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(30),
            topRight: Radius.circular(30),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Color(0xFF6C63FF),
          unselectedItemColor: Colors.grey[600],
          backgroundColor: Colors.transparent,
          elevation: 0,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(icon: Icon(Icons.spa), label: 'Zen Corner'),
            BottomNavigationBarItem(
              icon: Icon(Icons.graphic_eq),
              label: 'Live Sensor Data',
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
