import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Display user information like name, email
            Text(user.displayName ?? 'No name'),
            Text(user.email!),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => signOut(context),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  void signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacementNamed(context, '/'); // Go back to AuthPage
  }
}
