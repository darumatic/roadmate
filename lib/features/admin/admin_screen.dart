import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/admin_report.dart';
import '../../models/site.dart';
import '../../models/site_report.dart';
import '../../models/user_ban.dart';
import '../../services/auth_service.dart';
import '../../services/ban_logic.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_panel.dart';
import '../../widgets/load_error.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(currentUserRoleProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Admin'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: roleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const LoadError(),
          data: (role) {
            if (role == AppUserRole.admin) return const _AdminTabs();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const AccountPanel(),
                const SizedBox(height: 12),
                _AccessMessage(role: role),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminTabs extends StatelessWidget {
  const _AdminTabs();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            tabs: [
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Sites'),
              Tab(icon: Icon(Icons.how_to_vote_outlined), text: 'Reports'),
              Tab(icon: Icon(Icons.bolt_outlined), text: 'Activity'),
              Tab(icon: Icon(Icons.block_outlined), text: 'Bans'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PendingSitesTab(),
                // Status votes (open/blitz/closed).
                _ReportFeedTab(
                  filter: _isStatusVote,
                  emptyIcon: Icons.how_to_vote_outlined,
                  emptyTitle: 'No status votes',
                  emptyBody: 'Recent open/blitz/closed votes will appear here.',
                ),
                // Activity reports (long queue, delays, police present, etc.).
                _ReportFeedTab(
                  filter: _isActivityReport,
                  emptyIcon: Icons.bolt_outlined,
                  emptyTitle: 'No activity reports',
                  emptyBody:
                      'Recent long queue / delays / police reports will '
                      'appear here.',
                ),
                _BansTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessMessage extends StatelessWidget {
  const _AccessMessage({required this.role});

  final AppUserRole role;

  @override
  Widget build(BuildContext context) {
    final title = role == AppUserRole.anonymous
        ? 'Admin sign-in required'
        : 'Admin access required';
    final body = role == AppUserRole.anonymous
        ? 'Sign in with an approved admin account to review submitted sites and reports.'
        : 'This account can use RoadMate normally, but it is not on the admin list.';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingSitesTab extends ConsumerWidget {
  const _PendingSitesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingSitesProvider);
    return pendingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const LoadError(),
      data: (sites) {
        if (sites.isEmpty) {
          return const _EmptyAdminState(
            icon: Icons.fact_check_outlined,
            title: 'No pending sites',
            body: 'Submitted sites waiting for approval will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(pendingSitesProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: sites.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) => _PendingSiteCard(site: sites[index]),
          ),
        );
      },
    );
  }
}

class _PendingSiteCard extends ConsumerStatefulWidget {
  const _PendingSiteCard({required this.site});

  final Site site;

  @override
  ConsumerState<_PendingSiteCard> createState() => _PendingSiteCardState();
}

class _PendingSiteCardState extends ConsumerState<_PendingSiteCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(site.type.icon, color: AppTheme.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${site.state.code} • ${site.type.label}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _MetaLine(icon: Icons.place_outlined, text: site.address),
            if (site.suburb.isNotEmpty)
              _MetaLine(icon: Icons.location_city_outlined, text: site.suburb),
            if (site.direction != null)
              _MetaLine(icon: Icons.swap_vert_rounded, text: site.direction!),
            if (site.createdBy != null)
              _MetaLine(icon: Icons.person_outline, text: site.createdBy!),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    onPressed: _busy ? null : () => _moderate(approve: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textSecondary,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    onPressed: _busy ? null : () => _moderate(approve: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moderate({required bool approve}) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      if (approve) {
        await repo.approveSite(widget.site.id);
      } else {
        await repo.rejectSite(widget.site.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'Site approved' : 'Site rejected')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update site: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

bool _isStatusVote(SiteReport report) => report.status != null;

bool _isActivityReport(SiteReport report) => report.isActivityReport;

/// A filtered view over [recentAdminReportsProvider]. Both the Reports (status
/// votes) and Activity (activity reports) tabs share this — a report is one kind
/// or the other, so each tab just keeps the matching subset.
class _ReportFeedTab extends ConsumerWidget {
  const _ReportFeedTab({
    required this.filter,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
  });

  final bool Function(SiteReport report) filter;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(recentAdminReportsProvider);
    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const LoadError(),
      data: (reports) {
        final matches = reports.where((entry) => filter(entry.report)).toList();
        if (matches.isEmpty) {
          return _EmptyAdminState(
            icon: emptyIcon,
            title: emptyTitle,
            body: emptyBody,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(recentAdminReportsProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: matches.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) =>
                _ReportModerationCard(adminReport: matches[index]),
          ),
        );
      },
    );
  }
}

class _ReportModerationCard extends ConsumerStatefulWidget {
  const _ReportModerationCard({required this.adminReport});

  final AdminReport adminReport;

  @override
  ConsumerState<_ReportModerationCard> createState() =>
      _ReportModerationCardState();
}

class _ReportModerationCardState extends ConsumerState<_ReportModerationCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final adminReport = widget.adminReport;
    final report = adminReport.report;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.flag_outlined,
                  color: AppTheme.accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _reportTitle(report),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminReport.siteName,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
            if (report.activityNote?.trim().isNotEmpty ?? false) ...[
              const SizedBox(height: 10),
              Text(
                report.activityNote!.trim(),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _MetaLine(icon: Icons.person_outline, text: report.uid ?? 'No uid'),
            const SizedBox(height: 12),
            Row(
              children: [
                // Status votes are immutable (their counters live on the site
                // doc) — only activity reports get an Edit action.
                if (report.isActivityReport) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.border),
                        minimumSize: const Size.fromHeight(42),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      onPressed: _busy ? null : _editReport,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: AppTheme.border),
                      minimumSize: const Size.fromHeight(42),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Remove report'),
                    onPressed: _busy ? null : _deleteReport,
                  ),
                ),
              ],
            ),
            // Spam control: the ban acts on the poster, so it needs the uid a
            // report carries. Very old reports were written without one and
            // simply can't be traced back to an account.
            if (report.uid != null && report.uid!.isNotEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: AppTheme.border),
                  minimumSize: const Size.fromHeight(42),
                ),
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('Ban this user'),
                onPressed: _busy ? null : () => _banUser(report.uid!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editReport() async {
    final report = widget.adminReport.report;
    final edit = await showDialog<({ActivityReportType type, String note})>(
      context: context,
      builder: (_) => EditActivityReportDialog(
        initialType: report.activityType ?? ActivityReportType.other,
        initialNote: report.activityNote ?? '',
      ),
    );
    if (edit == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final adminReport = widget.adminReport;
      await ref
          .read(adminRepositoryProvider)
          .updateActivityReport(
            adminReport.siteId,
            adminReport.report.id,
            activityType: edit.type,
            activityNote: edit.note,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update report: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _banUser(String uid) async {
    final choice = await showBanUserDialog(context, uid: uid);
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .banUser(uid, duration: choice.duration, reason: choice.reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User banned (${choice.duration.label})')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not ban user: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteReport() async {
    setState(() => _busy = true);
    try {
      final adminReport = widget.adminReport;
      await ref
          .read(adminRepositoryProvider)
          .deleteReport(adminReport.siteId, adminReport.report.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report removed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove report: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Every ban, active or lapsed, with a one-tap lift. Expired 1-day bans stay
/// listed (greyed) so an admin can see who has already served one — a repeat
/// offender is exactly who gets the permanent ban next.
class _BansTab extends ConsumerWidget {
  const _BansTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bansAsync = ref.watch(bansProvider);
    return bansAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const LoadError(),
      data: (bans) {
        if (bans.isEmpty) {
          return const _EmptyAdminState(
            icon: Icons.block_outlined,
            title: 'Nobody is banned',
            body: 'Ban a spammer from their report in the Reports or '
                'Activity tab, and they will show up here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(bansProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: bans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) => _BanCard(ban: bans[index]),
          ),
        );
      },
    );
  }
}

class _BanCard extends ConsumerStatefulWidget {
  const _BanCard({required this.ban});

  final UserBan ban;

  @override
  ConsumerState<_BanCard> createState() => _BanCardState();
}

class _BanCardState extends ConsumerState<_BanCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final ban = widget.ban;
    final active = ban.isActiveAt(DateTime.now());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.block : Icons.block_outlined,
                  color: active ? Colors.redAccent : AppTheme.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _banHeadline(ban, active),
                    style: TextStyle(
                      color: active
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            _MetaLine(icon: Icons.person_outline, text: ban.uid),
            if (ban.reason?.trim().isNotEmpty ?? false)
              _MetaLine(
                icon: Icons.notes_outlined,
                text: ban.reason!.trim(),
              ),
            if (ban.createdAt != null)
              _MetaLine(
                icon: Icons.schedule,
                text: 'Banned ${_relativeTime(ban.createdAt!)}',
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.border),
                minimumSize: const Size.fromHeight(42),
              ),
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              label: Text(active ? 'Lift ban' : 'Remove record'),
              onPressed: _busy ? null : _unban,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unban() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).unbanUser(widget.ban.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ban lifted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not lift ban: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _banHeadline(UserBan ban, bool active) {
  if (!active) return 'Ban expired';
  if (ban.isPermanent) return 'Banned forever';
  return 'Banned until ${banExpiryLabel(ban.until!)}';
}

/// The admin's choice from [showBanUserDialog].
typedef BanChoice = ({BanDuration duration, String reason});

/// Asks how long to ban [uid] for, with an optional reason. Returns null when
/// the admin backs out. The caller performs the write.
Future<BanChoice?> showBanUserDialog(
  BuildContext context, {
  required String uid,
}) {
  return showDialog<BanChoice>(
    context: context,
    builder: (_) => _BanUserDialog(uid: uid),
  );
}

class _BanUserDialog extends StatefulWidget {
  const _BanUserDialog({required this.uid});

  final String uid;

  @override
  State<_BanUserDialog> createState() => _BanUserDialogState();
}

class _BanUserDialogState extends State<_BanUserDialog> {
  BanDuration _duration = BanDuration.oneDay;
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ban user'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.uid,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          for (final duration in BanDuration.values)
            RadioListTile<BanDuration>(
              value: duration,
              // ignore: deprecated_member_use
              groupValue: _duration,
              contentPadding: EdgeInsets.zero,
              title: Text(duration.label),
              // ignore: deprecated_member_use
              onChanged: (value) {
                if (value != null) setState(() => _duration = value);
              },
            ),
          const SizedBox(height: 4),
          TextField(
            controller: _reason,
            maxLength: kBanReasonMaxLength, // matches isValidBan in the rules
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Optional — for your own records',
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'They can still read the app, but cannot vote, report, add sites '
            'or save favourites until the ban lifts.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(
            context,
          ).pop((duration: _duration, reason: _reason.text)),
          child: const Text('Ban'),
        ),
      ],
    );
  }
}

/// Edit form for an activity report: type + note (the only fields the
/// security rules let an admin change). Pops with the chosen values, or null
/// on cancel; the caller performs the actual update.
class EditActivityReportDialog extends StatefulWidget {
  const EditActivityReportDialog({
    super.key,
    required this.initialType,
    required this.initialNote,
  });

  final ActivityReportType initialType;
  final String initialNote;

  @override
  State<EditActivityReportDialog> createState() =>
      _EditActivityReportDialogState();
}

class _EditActivityReportDialogState extends State<EditActivityReportDialog> {
  late ActivityReportType _type = widget.initialType;
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit activity report'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<ActivityReportType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Activity'),
            items: [
              for (final type in ActivityReportType.values)
                DropdownMenuItem(value: type, child: Text(type.label)),
            ],
            onChanged: (type) {
              if (type != null) setState(() => _type = type);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 500, // matches the activityNote limit in firestore.rules
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Optional details',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop((type: _type, note: _note.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAdminState extends StatelessWidget {
  const _EmptyAdminState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.accent, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

String _reportTitle(SiteReport report) {
  if (report.status != null) return 'Status: ${report.status!.label}';
  if (report.activityType != null) return report.activityType!.label;
  return 'Report';
}

String _relativeTime(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
