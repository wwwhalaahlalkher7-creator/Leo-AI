import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/chat/chat_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LeoApp());
}

class LeoApp extends StatelessWidget {
  const LeoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0A101C);
    const foreground = Color(0xFFEAF0FA);
    return MaterialApp(
      title: 'Leo',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF9BB0FF),
          secondary: Color(0xFF9BB0FF),
          surface: Color(0xFF121C2B),
          onSurface: foreground,
          onPrimary: Color(0xFF101827),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: foreground),
          bodyMedium: TextStyle(color: foreground),
          titleLarge: TextStyle(color: foreground),
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: Color(0xFF8292AB)),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ChatPage(),
    );
  }
}
