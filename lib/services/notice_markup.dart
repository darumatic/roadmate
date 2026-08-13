/// The safe HTML subset an admin notice may use, parsed to flat spans.
///
/// Rich notices (`messageHtml` on `announcements/current`) accept exactly:
/// `<b>`/`<strong>`, `<i>`/`<em>`, `<u>`, `<a href="https://…">`, `<br>` and
/// `<font color="#RRGGBB">`, plus the entities `&amp; &lt; &gt; &quot; &#39;
/// &apos; &nbsp;`. Everything else — unknown tags, `javascript:` hrefs, bad
/// colours — is stripped while its inner text is kept, so a typo degrades to
/// plain words rather than leaking markup at the user.
///
/// Parsing is done here, Flutter-free, into [NoticeSpan]s; the banner widget
/// turns those into `TextSpan`s. That split keeps every parsing rule
/// unit-testable without a widget pump (same philosophy as `status_logic.dart`)
/// and means the renderer can never be handed markup it doesn't understand.
///
/// A deliberately tiny hand-rolled scanner, not an HTML package: the input is
/// admin-written, capped at a few hundred chars, and rendered inside a slim
/// one-strip banner — arbitrary HTML layout has no meaning there.
library;

/// One run of identically-styled text. Flat — nesting is already resolved.
class NoticeSpan {
  const NoticeSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
    this.linkUrl,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// ARGB (always fully opaque) from a `<font color="#RRGGBB">`, or null to
  /// inherit the banner foreground.
  final int? color;

  /// Absolute http/https URL this run links to, or null for plain text.
  final String? linkUrl;

  @override
  bool operator ==(Object other) =>
      other is NoticeSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color &&
      other.linkUrl == linkUrl;

  @override
  int get hashCode =>
      Object.hash(text, bold, italic, underline, color, linkUrl);

  @override
  String toString() =>
      'NoticeSpan("$text"'
      '${bold ? ' bold' : ''}'
      '${italic ? ' italic' : ''}'
      '${underline ? ' underline' : ''}'
      '${color != null ? ' color:#${color!.toRadixString(16)}' : ''}'
      '${linkUrl != null ? ' link:$linkUrl' : ''})';
}

/// `<name attrs>` / `</name>` / `<br/>`. Attribute values may not contain `>`
/// — fine for hrefs and hex colours, and an unmatchable `<` falls back to
/// literal text below.
final RegExp _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>');

final RegExp _href = RegExp(
  '''href\\s*=\\s*(?:"([^"]*)"|'([^']*)')''',
  caseSensitive: false,
);

final RegExp _fontColor = RegExp(
  '''color\\s*=\\s*(?:"([^"]*)"|'([^']*)')''',
  caseSensitive: false,
);

List<NoticeSpan> parseNoticeMarkup(String source) {
  final spans = <NoticeSpan>[];
  final buffer = StringBuffer();
  var bold = 0, italic = 0, underline = 0;
  // Sentinel-free stacks: an <a> with a refused href still pushes null so its
  // </a> pops the right entry and nesting stays balanced.
  final links = <String?>[];
  final colors = <int?>[];

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      NoticeSpan(
        buffer.toString(),
        bold: bold > 0,
        italic: italic > 0,
        underline: underline > 0,
        color: colors.isEmpty ? null : colors.last,
        linkUrl: links.isEmpty ? null : links.last,
      ),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < source.length) {
    if (source[i] == '<') {
      final match = _tag.matchAsPrefix(source, i);
      if (match != null) {
        final closing = match[1] == '/';
        final name = match[2]!.toLowerCase();
        final attrs = match[3]!;
        switch (name) {
          case 'b' || 'strong':
            flush();
            bold = _step(bold, closing);
          case 'i' || 'em':
            flush();
            italic = _step(italic, closing);
          case 'u':
            flush();
            underline = _step(underline, closing);
          case 'a':
            flush();
            if (closing) {
              if (links.isNotEmpty) links.removeLast();
            } else {
              links.add(_safeHref(attrs));
            }
          case 'font':
            flush();
            if (closing) {
              if (colors.isNotEmpty) colors.removeLast();
            } else {
              final raw = _fontColor.firstMatch(attrs);
              colors.add(parseHexColor(raw == null ? null : raw[1] ?? raw[2]));
            }
          case 'br':
            if (!closing) buffer.write('\n');
          default:
            break; // unknown tag: stripped, inner text flows through
        }
        i = match.end;
        continue;
      }
    }
    if (source[i] == '&') {
      final decoded = _entity(source, i);
      if (decoded != null) {
        buffer.write(decoded.$1);
        i += decoded.$2;
        continue;
      }
    }
    buffer.write(source[i]);
    i++;
  }
  flush();
  return spans;
}

/// The notice with all markup resolved away — what old clients (which render
/// `message` verbatim) should see, and what the length cap measures.
String plainTextOfNotice(String source) =>
    parseNoticeMarkup(source).map((span) => span.text).join();

/// Whether [source] uses any markup or entities at all. When it doesn't, the
/// notice is published exactly as before — no `messageHtml` field — so a plain
/// message stays byte-identical to the pre-rich era.
bool noticeHasMarkup(String source) => plainTextOfNotice(source) != source;

/// `#RRGGBB` (either case) to opaque ARGB, or null for anything else. The
/// format mirrors the `matches('#[0-9a-fA-F]{6}')` check in firestore.rules.
int? parseHexColor(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? null : 0xFF000000 | value;
}

/// True when [argb] is light enough that black text reads better than white —
/// how the banner picks its foreground for a custom background colour.
bool prefersDarkForeground(int argb) {
  final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
  return (0.299 * r) + (0.587 * g) + (0.114 * b) > 150;
}

/// Open bumps a style's nesting depth, close lowers it; a stray close tag
/// cannot push the depth negative.
int _step(int depth, bool closing) =>
    closing ? (depth > 0 ? depth - 1 : 0) : depth + 1;

/// The href when it is an absolute http/https URL; null refuses everything
/// else (`javascript:`, relative paths, mailto) so a link can only ever open
/// a web page.
String? _safeHref(String attrs) {
  final match = _href.firstMatch(attrs);
  final raw = (match == null ? null : match[1] ?? match[2])?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return raw;
}

const Map<String, String> _entities = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#39;': "'",
  '&apos;': "'",
  '&nbsp;': ' ',
};

/// The decoded character and consumed length when [source] holds a known
/// entity at [at]; null leaves the `&` as literal text.
(String, int)? _entity(String source, int at) {
  for (final entry in _entities.entries) {
    if (source.startsWith(entry.key, at)) {
      return (entry.value, entry.key.length);
    }
  }
  return null;
}
