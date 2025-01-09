import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const NginxProxyManagerApp());
}

class NginxProxyManagerApp extends StatelessWidget {
  const NginxProxyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nginx Proxy Manager',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          background: Colors.black,
          surface: Colors.black,
          primary: Colors.white,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
