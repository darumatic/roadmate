import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';

/// Card for a single site: shows details and the community actions — status
/// voting (OPEN/BLITZ/CLOSE), Report activity, and favourite (star). All writes go
/// through [siteRepositoryProvider].
class SiteCard extends ConsumerWidget {
  const SiteCard({super.key, required this.site});

  final Site site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouriteSiteIdsProvider).value ?? const {};
    final isFavourite = favouriteIds.contains(site.id);
    final repo = ref.read(siteRepositoryProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: site.currentStatus.color.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (site.direction != null) ...[
            _DirectionTag(site.direction!),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  site.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFavourite ? Icons.star : Icons.star_border,
                  color: isFavourite ? AppTheme.accent : AppTheme.textSecondary,
                ),
                onPressed: () => repo.toggleFavourite(site.id),
                tooltip: isFavourite
                    ? 'Remove from favourites'
                    : 'Add to favourites',
              ),
            ],
          ),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  site.address,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _TypeChip(site.type),
              const Spacer(),
              StatusBadge(site.currentStatus),
            ],
          ),
          if (site.note != null) ...[
            const SizedBox(height: 8),
            Text(
              site.note!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _VoteRow(
            current: site.currentStatus,
            onVote: (status) async {
              await repo.vote(site.id, status);
              if (context.mounted) {
                _snack(
                  context,
                  'Reported ${status.label.toUpperCase()} — thanks!',
                );
              }
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
            ),
            icon: const Icon(Icons.flag_outlined, size: 16),
            label: const Text('Report activity'),
            onPressed: () => _reportActivity(context, repo),
          ),
        ],
      ),
    );
  }

  Future<void> _reportActivity(BuildContext context, repo) async {
    final note = await showReportDialog(context);
    if (note != null && note.trim().isNotEmpty) {
      await repo.report(site.id, note.trim());
      if (context.mounted) _snack(context, 'Report submitted — thanks!');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

/// Modal to capture a free-text activity report. Returns null if cancelled.
Future<String?> showReportDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Report activity'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. Trucks being pulled over, long queue...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Submit'),
        ),
      ],
    ),
  );
}

class _VoteRow extends StatelessWidget {
  const _VoteRow({required this.current, required this.onVote});

  final SiteStatus current;
  final ValueChanged<SiteStatus> onVote;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final status in SiteStatus.values) ...[
          if (status != SiteStatus.values.first) const SizedBox(width: 8),
          Expanded(
            child: _VoteButton(
              status: status,
              selected: current == status,
              onTap: () => onVote(status),
            ),
          ),
        ],
      ],
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final SiteStatus status;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon => switch (status) {
    SiteStatus.open => Icons.check_circle_outline,
    SiteStatus.blitz => Icons.warning_amber_rounded,
    SiteStatus.closed => Icons.cancel_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? status.color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: status.color.withValues(alpha: selected ? 1 : 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              _icon,
              size: 18,
              color: selected ? status.color : AppTheme.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              status.label.toUpperCase(),
              style: TextStyle(
                color: selected ? status.color : AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.type);
  final SiteType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(
            type.label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DirectionTag extends StatelessWidget {
  const _DirectionTag(this.direction);
  final String direction;

  @override
  Widget build(BuildContext context) {
    final isNorth = direction.toLowerCase().contains('north');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isNorth ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            direction[0].toUpperCase() + direction.substring(1),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
