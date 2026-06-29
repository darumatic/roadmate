import '../models/enums.dart';

String statusDisplayLabel(SiteStatus status) => switch (status) {
  SiteStatus.open => 'OPEN/WORKING',
  _ => status.label.toUpperCase(),
};
