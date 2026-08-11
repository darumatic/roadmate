import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../models/site_report.dart';
import '../services/auth_service.dart';
import '../services/providers.dart';
import '../services/ban_logic.dart';
import '../services/map_links.dart';
import '../services/rate_limit.dart';
import '../services/report_proximity.dart';
import '../services/site_repository.dart';
import '../services/status_logic.dart';
import '../services/username_logic.dart';
import '../theme/app_theme.dart';
import 'edit_site_dialog.dart';
import 'level_badge.dart';
import 'status_badge.dart';
import 'status_labels.dart';
import 'username_prompt.dart';

/// Card for a single site: shows details and the community actions — status
/// voting, Report activity, and favourite (star). All writes go through
/// [siteRepositoryProvider].
class SiteCard extends ConsumerWidget {
  const SiteCard({super.key, required this.site, this.highlighted = false});

  final Site site;

  /// Accent border marking the card the user tapped to get here (issue #10).
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouriteIds = ref.watch(favouriteSiteIdsProvider).value ?? const {};
    final isFavourite = favouriteIds.contains(site.id);
    final reportsAsync = ref.watch(siteReportsProvider(site.id));
    final lastReportAt = site.lastReportAt;
    final repo = ref.read(siteRepositoryProvider);
    final isAdmin =
        ref.watch(currentUserRoleProvider).value == AppUserRole.admin;
    // Keeps the profile stream hot so ensureSignatureName's synchronous read
    // is settled by the time a post button is tapped.
    ref.watch(signatureNameProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? AppTheme.accent
              : site.currentStatus.color.withValues(alpha: 0.4),
          width: highlighted ? 1.5 : 1,
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Admin-only: fix or fill the site's coordinates.
                      if (isAdmin)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.edit_location_alt_outlined,
                            color: site.lat == null
                                ? Colors.orangeAccent
                                : AppTheme.textSecondary,
                            size: 20,
                          ),
                          onPressed: () => _editSite(context, ref),
                          tooltip: site.lat == null
                              ? 'Edit site (admin) — location missing'
                              : 'Edit site (admin)',
                        ),
                      // Admin-only: remove the site entirely (issue #13).
                      if (isAdmin)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () => _confirmRemoveSite(context, ref),
                          tooltip: 'Remove site (admin)',
                        ),
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
            ],
          ),
          // The whole address row — leading bare directions icon and the
          // address itself — is one maps-app tap target.
          Tooltip(
            message: 'Open in Maps',
            child: InkWell(
              onTap: () => _openInMaps(context),
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_outlined,
                    size: 19,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
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
            ),
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
            onVote: (status) => _vote(context, ref, repo, status),
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
            onPressed: () => _reportActivity(context, ref, repo),
          ),
          _RecentActivityReports(reportsAsync: reportsAsync),
        ],
      ),
    );
  }

  /// Casts a status vote; a failed write surfaces as a snack, never a crash.
  /// The proximity gate's refusals arrive as exceptions from the repository —
  /// the OS location prompt (if one was needed) has already been shown by the
  /// time [LocationRequiredException] lands, so a snack is all that's left.
  ///
  /// Votes are signed: a user with no road name yet is asked to pick one
  /// first, and declining abandons the vote.
  Future<void> _vote(
    BuildContext context,
    WidgetRef ref,
    SiteRepository repo,
    SiteStatus status,
  ) async {
    final name = await ensureSignatureName(context, ref);
    if (name == null) {
      if (context.mounted) _snack(context, kRoadNameRequiredMessage);
      return;
    }
    if (!context.mounted) return;
    try {
      await repo.vote(site, status, reporterName: name);
      if (context.mounted) {
        _snack(context, 'Reported ${statusDisplayLabel(status)} — thanks!');
      }
    } on TooFarException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on LocationRequiredException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on BannedException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on RateLimitedException {
      if (!context.mounted) return;
      _snack(context, kRateLimitMessage);
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Could not submit — please try again.');
    }
  }

  Future<void> _reportActivity(
    BuildContext context,
    WidgetRef ref,
    SiteRepository repo,
  ) async {
    final name = await ensureSignatureName(context, ref);
    if (name == null) {
      if (context.mounted) _snack(context, kRoadNameRequiredMessage);
      return;
    }
    if (!context.mounted) return;
    final report = await _showReportDialog(context, signature: name);
    if (report == null || !context.mounted) return;
    await _submitReport(context, repo, report, name);
  }

  /// Submits an already-composed [report]. Split from [_reportActivity] so
  /// submission failures never cost the driver what they typed.
  Future<void> _submitReport(
    BuildContext context,
    SiteRepository repo,
    _ActivityReportDraft report,
    String reporterName,
  ) async {
    try {
      await repo.report(
        site,
        report.activityType,
        activityNote: report.activityNote,
        reporterName: reporterName,
      );
      if (context.mounted) _snack(context, 'Report submitted — thanks!');
    } on TooFarException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on LocationRequiredException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on BannedException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message);
    } on RateLimitedException {
      if (!context.mounted) return;
      _snack(context, kRateLimitMessage);
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'Could not submit — please try again.');
    }
  }

  /// Hands the site's location to the platform maps app (a Google Maps tab
  /// on web). Un-geocoded sites become an address search there instead.
  Future<void> _openInMaps(BuildContext context) async {
    try {
      if (await openSiteInMaps(site)) return;
    } catch (_) {
      // Fall through to the snack.
    }
    if (context.mounted) _snack(context, 'Could not open the maps app');
  }

  /// Admin: correct the site's name and/or coordinates. Community
  /// submissions may arrive badly named or without a pin (coordinates are
  /// optional), and geocoded seed positions are town-level — this is how
  /// both get fixed.
  Future<void> _editSite(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => EditSiteDialog(site: site),
    );
    if (saved == true && context.mounted) _snack(context, 'Site updated');
  }

  /// Warns before permanently deleting the site + its reports (issue #13).
  Future<void> _confirmRemoveSite(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Remove site?'),
        content: Text(
          'This permanently deletes "${site.name}" and all of its reports '
          'for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteSite(site.id);
      if (context.mounted) _snack(context, 'Site removed');
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not remove site: $e');
    }
  }

  void _snack(BuildContext context, String msg) {
    // Replace any showing snack — a cooldown explanation must not sit in a
    // queue behind the previous "thanks!" message.
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }
}

class _ActivityReportDraft {
  const _ActivityReportDraft({required this.activityType, this.activityNote});

  final ActivityReportType activityType;
  final String? activityNote;
}

/// Modal to capture an activity category plus optional note. The report is
/// signed with [signature] (the author's road name / display name), shown so
/// nobody posts without knowing what name lands next to it.
Future<_ActivityReportDraft?> _showReportDialog(
  BuildContext context, {
  required String signature,
}) {
  return showDialog<_ActivityReportDraft>(
    context: context,
    builder: (context) => _ReportDialog(signature: signature),
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.signature});

  final String signature;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _noteController = TextEditingController();
  ActivityReportType _activityType = ActivityReportType.longQueue;

  @override
  void dispose() {
    _noteController.dispose();
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
            Text(
              'Posting as ${widget.signature}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
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
            Navigator.pop(
              context,
              _ActivityReportDraft(
                activityType: _activityType,
                activityNote: note.isEmpty ? null : note,
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
    final reports = recentActivityReports(
      reportsAsync.value ?? const [],
    ).take(5).toList();
    if (reports.isEmpty) return const SizedBox.shrink();

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
          Row(
            children: [
              ReporterLevelIcon(reporterLevel: report.reporterLevel),
              Flexible(
                child: Text(
                  reporter,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
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
        // Only real statuses are votable — Unknown (issue #21) is derived, so
        // when it's current no button matches and all three render greyed.
        for (final status in SiteStatus.votable) ...[
          if (status != SiteStatus.votable.first) const SizedBox(width: 8),
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
    // Not votable — present only to keep the switch exhaustive.
    SiteStatus.unknown => Icons.help_outline,
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
    final d = direction.toLowerCase();
    final IconData icon;
    if (d.contains('north')) {
      icon = Icons.arrow_upward;
    } else if (d.contains('east')) {
      icon = Icons.arrow_forward;
    } else if (d.contains('west')) {
      icon = Icons.arrow_back;
    } else {
      icon = Icons.arrow_downward;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
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
