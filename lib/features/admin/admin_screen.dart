import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/admin_report.dart';
import '../../models/site.dart';
import '../../models/site_report.dart';
import '../../services/auth_service.dart';
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
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Sites'),
              Tab(icon: Icon(Icons.flag_outlined), text: 'Reports'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [_PendingSitesTab(), _ReportsTab()]),
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

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(recentAdminReportsProvider);
    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const LoadError(),
      data: (reports) {
        if (reports.isEmpty) {
          return const _EmptyAdminState(
            icon: Icons.flag_outlined,
            title: 'No reports',
            body: 'Recent community reports will appear here.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(recentAdminReportsProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, index) =>
                _ReportModerationCard(adminReport: reports[index]),
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
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: AppTheme.border),
                minimumSize: const Size.fromHeight(42),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove report'),
              onPressed: _busy ? null : _deleteReport,
            ),
          ],
        ),
      ),
    );
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
