import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Loginpage extends StatefulWidget {
  const Loginpage({Key? key}) : super(key: key);

  @override
  State<Loginpage> createState() => _LoginpageState();
}

class _LoginpageState extends State<Loginpage> {

  final _emailController = TextEditingController();
  final  _passwordController = TextEditingController();

  Future signIn() async{
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigoAccent,
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.self_improvement_sharp, size: 100, color: Colors.white),
              //HELLO
              SizedBox(height: 10),
              Text('Hello Again', style: TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              Text('Lets check on your nerves!', style: TextStyle(fontSize: 20, color: Colors.white)),
              SizedBox(height: 20),
              //username or email
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _emailController,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter Your Email',
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              //password                   
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    textAlign: TextAlign.center,
                    obscureText: true,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Enter Your Password',
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              //login button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal:25),
                child: GestureDetector(
                  onTap: signIn,
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Center(
                      child: Text('Sign In',style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('New User?', style: TextStyle(fontSize: 20, color: Colors.white)),
                  Text(' Register Here', style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold))
                ],
              ),
              //register button
            ],
          ),
        ),
      ),
    );
  }
}
