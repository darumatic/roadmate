/// Compact "how long ago" label — "just now", "5m ago", "3h ago", "2d ago".
///
/// The one implementation for every surface (site cards, Recently Active,
/// admin feed, approach prompts). It used to exist as four byte-identical
/// copies, three of which hardcoded `DateTime.now()` and so could never be
/// tested under a fixed clock; [now] is injectable for exactly that.
String relativeTime(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
