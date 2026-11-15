import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/monitor_provider.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MonitorProvider()),
      ],
      child: const LanMonitorApp(),
    ),
  );
}

class LanMonitorApp extends StatelessWidget {
  const LanMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Monitor',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system, // Automatically matches iOS system dark/light mode
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0284C7),
          surface: Colors.white,
          onSurface: Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
        fontFamily: '.SF Pro Text',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          surface: Color(0xFF1E293B),
          onSurface: Color(0xFFF8FAFC),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Color(0xFFF8FAFC),
          elevation: 0,
        ),
        fontFamily: '.SF Pro Text',
      ),
      home: const DashboardScreen(),
    );
  }
}
