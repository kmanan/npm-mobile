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
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}