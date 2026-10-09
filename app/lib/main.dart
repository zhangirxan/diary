import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api.dart';
import 'day_screen.dart';

Future<void> main() async {
  await initializeDateFormatting('ru');
  runApp(DiaryApp(api: DiaryApi()));
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key, required this.api});

  final DiaryApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Дневник смен',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: DayScreen(api: api),
    );
  }
}
