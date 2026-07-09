import 'package:drone_checklist/view/login_view.dart';
import 'package:drone_checklist/view/form_view.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // runApp(const MyApp());

  // Check login status to determine initial route
  final prefs = await SharedPreferences.getInstance();
  final String? username = prefs.getString('username');
  final bool isLoggedIn = username != null && username.isNotEmpty;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      // Selalu arahkan ke LoginView setiap kali aplikasi dibuka
      // home: const LoginView(),
      // Use persistence check to decide home screen
      home: isLoggedIn ? const FormView() : const LoginView(),
    );
  }

  ThemeData _buildLightTheme() {
    var baseTheme = ThemeData.light();
    return baseTheme.copyWith(
      textTheme: GoogleFonts.latoTextTheme(baseTheme.textTheme),
    );
  }
}
