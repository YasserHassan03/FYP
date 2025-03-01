import 'package:app/auth/auth_page.dart';
import 'package:app/pages/home_page.dart';
import 'package:app/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';



class MainPage extends StatelessWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(stream: FirebaseAuth.instance.authStateChanges() , builder: (context,snapshot){
        if(snapshot.hasData){
          return Homepage();
        } else {
          return Authpage();
        }
      }),
    );

  } 
}