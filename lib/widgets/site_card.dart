import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'status_badge.dart';
import 'status_labels.dart';

/// Card for a single site: shows details and the community actions — status
/// voting, Report activity, and favourite (star). All writes go through
/// [siteRepositoryProvider].
class SiteCard extends ConsumerWidget {
  const SiteCard({super.key, required this.site});

  final Site site;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouriteSiteIdsProvider).value ?? const {};
    final isFavourite = favouriteIds.contains(site.id);
    final reportsAsync = ref.watch(siteReportsProvider(site.id));
    final lastReportAt = site.lastReportAt;
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (lastReportAt != null) ...[
                    Text(
                      'reported ${_relativeTime(lastReportAt)}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isFavourite ? Icons.star : Icons.star_border,
                      color: isFavourite
                          ? AppTheme.accent
                          : AppTheme.textSecondary,
                    ),
                    onPressed: () => repo.toggleFavourite(site.id),
                    tooltip: isFavourite
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                  ),
                ],
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
                  'Reported ${statusDisplayLabel(status)} — thanks!',
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
          _RecentActivityReports(reportsAsync: reportsAsync),
        ],
      ),
    );
  }

  Future<void> _reportActivity(BuildContext context, repo) async {
    final report = await _showReportDialog(context);
    if (report != null) {
      await repo.report(
        site.id,
        report.activityType,
        activityNote: report.activityNote,
        reporterName: report.reporterName,
      );
      if (context.mounted) _snack(context, 'Report submitted — thanks!');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }
}

class _ActivityReportDraft {
  const _ActivityReportDraft({
    required this.activityType,
    this.activityNote,
    this.reporterName,
  });

  final ActivityReportType activityType;
  final String? activityNote;
  final String? reporterName;
}

/// Modal to capture an activity category plus optional note/name.
Future<_ActivityReportDraft?> _showReportDialog(BuildContext context) {
  return showDialog<_ActivityReportDraft>(
    context: context,
    builder: (context) => const _ReportDialog(),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _noteController = TextEditingController();
  final _nameController = TextEditingController();
  ActivityReportType _activityType = ActivityReportType.longQueue;

  @override
  void dispose() {
    _noteController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Report activity'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What is happening?',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in ActivityReportType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _activityType == type,
                    onSelected: (_) => setState(() => _activityType = type),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Comment (optional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Name (optional)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Names and comments are public.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: () {
            final note = _noteController.text.trim();
            final name = _nameController.text.trim();
            Navigator.pop(
              context,
              _ActivityReportDraft(
                activityType: _activityType,
                activityNote: note.isEmpty ? null : note,
                reporterName: name.isEmpty ? null : name,
              ),
            );
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _RecentActivityReports extends StatelessWidget {
  const _RecentActivityReports({required this.reportsAsync});

  final AsyncValue<List<SiteReport>> reportsAsync;

  @override
  Widget build(BuildContext context) {
    final reports = reportsAsync.value
        ?.where((report) => report.activityType != null)
        .take(5)
        .toList();
    if (reports == null || reports.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent reports',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final report in reports) ...[
            _ActivityReportTile(report: report),
            if (report != reports.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ActivityReportTile extends StatelessWidget {
  const _ActivityReportTile({required this.report});

  final SiteReport report;

  @override
  Widget build(BuildContext context) {
    final reporter = report.reporterName?.trim().isNotEmpty ?? false
        ? report.reporterName!.trim()
        : 'Anonymous';
    final note = report.activityNote?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  report.activityType!.label,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _relativeTime(report.createdAt),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 4),
          Text(
            reporter,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                statusDisplayLabel(status),
                maxLines: 1,
                style: TextStyle(
                  color: selected ? status.color : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
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
