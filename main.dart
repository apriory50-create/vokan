import 'package:flutter/material.dart';
import 'screens.dart';

void main() => runApp(const TrainerApp());

class TrainerApp extends StatelessWidget {
  const TrainerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'English Trainer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const HomeScreen(),
      );
}
