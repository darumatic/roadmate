import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The big screen heading every tab starts its scroll view with — one place
/// for the size/weight/padding four screens used to each declare.
class SliverScreenTitle extends StatelessWidget {
  const SliverScreenTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}
