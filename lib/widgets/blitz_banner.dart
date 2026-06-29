import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../models/site.dart';

/// Prominent "BLITZ DETECTED" banner shown on Home when one or more sites are
/// currently flagged as a blitz. Tapping jumps to the affected state.
class BlitzBanner extends StatelessWidget {
  const BlitzBanner({super.key, required this.blitzSites});

  final List<Site> blitzSites;

  @override
  Widget build(BuildContext context) {
    if (blitzSites.isEmpty) return const SizedBox.shrink();
    final colour = SiteStatus.blitz.color;
    final first = blitzSites.first;
    final more = blitzSites.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/state/${first.state.code}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colour.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colour),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BLITZ DETECTED',
                      style: TextStyle(
                        color: colour,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      more > 0
                          ? '${first.name} +$more more'
                          : '${first.name} — ${first.address}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colour),
            ],
          ),
        ),
      ),
    );
  }
}
