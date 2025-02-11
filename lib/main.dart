import 'package:app1/pages/profile_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'firebase_options.dart';
import 'package:app1/pages/auth_page.dart';
import 'package:app1/pages/add_recipe_page.dart';
import 'package:app1/pages/login_page.dart';
import 'package:app1/pages/register_page.dart';
import 'package:app1/pages/weekly_calendar_page.dart';
import 'package:app1/pages/shopping_list_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => AuthPage(),
        '/login': (context) => LoginPage(onTap: () {
          Navigator.pushReplacementNamed(context, '/register');
        }),
        '/register': (context) => RegisterPage(onTap: () {
          Navigator.pushReplacementNamed(context, '/login');
        }),
        '/navigation': (context) => MainScreen(),
        '/shopping_list': (context) => ShoppingListPage(selectedRecipes: {}),
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static List<Widget> _widgetOptions = <Widget>[
    WeeklyCalendarPage(),
    AddRecipePage(),
    ShoppingListPage(selectedRecipes: {}),
    ProfilePage()
  ];

void _onItemTapped(int index) {
    if (index == _widgetOptions.length - 1) {
      // Navigate to profile page
      Navigator.push(context, MaterialPageRoute(builder: (context) => ProfilePage()));
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add Recipe',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Shopping List',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        currentIndex: _selectedIndex,
        iconSize: 30,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed, 
        onTap: _onItemTapped,
      ),
    );
  }
}
