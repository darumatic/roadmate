import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'services/startup_service.dart';
import 'theme/app_theme.dart';

class RoadMateApp extends ConsumerWidget {
  const RoadMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupProvider);

    return startup.when(
      loading: () => MaterialApp(
        title: 'RoadMate AU',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const _StartupScreen(),
      ),
      error: (error, _) => MaterialApp(
        title: 'RoadMate AU',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: _StartupErrorScreen(error: error),
      ),
      data: (_) => MaterialApp.router(
        title: 'RoadMate AU',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: appRouter,
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping, color: AppTheme.accent, size: 40),
              SizedBox(height: 18),
              Text(
                'RoadMate AU',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Know before you roll.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              SizedBox(height: 28),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_rounded,
                  color: AppTheme.accent,
                  size: 38,
                ),
                const SizedBox(height: 18),
                const Text(
                  'RoadMate could not start',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
