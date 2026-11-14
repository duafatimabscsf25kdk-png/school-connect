import 'package:flutter/material.dart';
import 'db.dart';
import 'mesh.dart';
import 'util.dart';
import 'screens/auth.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Db.i.init();
  await Mesh.i.loadIdentity();
  runApp(const SchoolConnectApp());
}

class SchoolConnectApp extends StatefulWidget {
  const SchoolConnectApp({super.key});
  @override
  State<SchoolConnectApp> createState() => _AppState();
}

class _AppState extends State<SchoolConnectApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Mesh.i.loggedIn) Mesh.i.start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && Mesh.i.loggedIn && !Mesh.i.running) {
      Mesh.i.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Mesh.i,
      builder: (context, _) => MaterialApp(
        title: 'School Connect',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: kGreen2, primary: kGreen2),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: kAccent, foregroundColor: Colors.white),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
          textTheme: const TextTheme(
              bodyLarge: TextStyle(fontSize: 17),
              bodyMedium: TextStyle(fontSize: 16),
              titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(Mesh.i.largeText ? 1.25 : 1.0)),
          child: child!,
        ),
        home: Mesh.i.loggedIn ? const HomeScreen() : const WelcomeScreen(),
      ),
    );
  }
}
