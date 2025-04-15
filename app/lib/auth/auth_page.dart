import 'package:CalmPetitor/pages/register_page.dart';
import 'package:CalmPetitor/pages/login_page.dart';
import 'package:flutter/material.dart';

class Authpage extends StatefulWidget {
  const Authpage({Key? key}) : super(key: key);

  @override
  State<Authpage> createState() => _AuthpageState();
}

class _AuthpageState extends State<Authpage> {
  bool showLogin = true;
  void toggleView() {
    setState(() {
      showLogin = !showLogin;
    });

  }
  @override
  Widget build(BuildContext context) {
    if (showLogin) {
      return Loginpage(showRegisterPage: toggleView);
    } else {
      return Registerpage(showLoginPage:toggleView);
    }
  }
}
