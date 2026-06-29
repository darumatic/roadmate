import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class RoadMateApp extends StatelessWidget {
  const RoadMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RoadMate AU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
