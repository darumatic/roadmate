import 'site_report.dart';

class AdminReport {
  const AdminReport({
    required this.report,
    required this.siteId,
    required this.siteName,
  });

  final SiteReport report;
  final String siteId;
  final String siteName;
}
