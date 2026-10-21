import 'package:flutter/material.dart';

import '../controller.dart';
import 'home_page.dart';

const _seed = Color(0xFF3FB6A8);

class NearbyApp extends StatelessWidget {
  const NearbyApp({super.key, required this.controller});

  final NearbyController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'nearby',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(controller: controller),
    );
  }
}

ThemeData _theme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  visualDensity: VisualDensity.compact,
);
