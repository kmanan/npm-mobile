import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'services/subscription_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize subscription service (fast local check only, no network blocking)
  final subscriptionService = SubscriptionService();
  subscriptionService.initialize();

  runApp(const NginxProxyManagerApp());
}

class NginxProxyManagerApp extends StatelessWidget {
  const NginxProxyManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nginx Proxy Manager',
      debugShowCheckedModeBanner: false,
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
