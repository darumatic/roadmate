import '../models/enums.dart';

String statusDisplayLabel(SiteStatus status) => switch (status) {
  SiteStatus.open => 'Open/Working',
  _ => status.label,
};
