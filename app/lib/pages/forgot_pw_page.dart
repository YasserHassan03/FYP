import 'package:flutter/material.dart';

class forgotPasswordPage extends StatelessWidget {
  const forgotPasswordPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF74EBD5),
              Color(0xFFACB6E5),
            ], // Soft blue-green to lavender gradient
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_reset, size: 100, color: Colors.white),
              SizedBox(height: 20),
              // Main message
              Text(
                "Should've remembered your password 🤪",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              // Desperate email message
              Text(
                "If you're really desperate, email yh4021@ic.ac.uk",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 20),
              // Back to Login button
              GestureDetector(
                onTap: () {
                  Navigator.pop(context); // Go back to login
                },
                child: Text(
                  'Back to Login',
                  style: TextStyle(
                    color: Color(0xFF6C63FF),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
