import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Homepage extends StatefulWidget{
  const Homepage({Key? key}) : super(key: key);

  @override
  State<Homepage> createState() => _HomepageState();

}

class _HomepageState extends State<Homepage> {

  final user = FirebaseAuth.instance.currentUser!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigoAccent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Signed in as: ' + user.email! , style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ElevatedButton(onPressed: (){FirebaseAuth.instance.signOut();}, child: Text('Sign Out'))
          ],
        ),
      ),
    );
  }
}