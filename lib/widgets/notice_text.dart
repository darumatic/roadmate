import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/announcement.dart';
import '../services/notice_markup.dart';

/// Where a notice's links and store buttons go in production: out of the app,
/// to the browser or the store. The widgets that use it take an `onOpenLink`
/// override so tests record the URL instead of reaching the url_launcher
/// plugin.
void launchExternalUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// A notice's message as text — shared by [AnnouncementBanner] and
/// [RateAppPopup], so both render markup identically.
///
/// Plain notices stay a single [Text]; rich ones ([Announcement.messageHtml],
/// the safe subset of `notice_markup.dart`) map each parsed [NoticeSpan] onto
/// [style], links underlined and wired to [onOpenLink].
class NoticeText extends StatefulWidget {
  const NoticeText({
    super.key,
    required this.announcement,
    required this.style,
    this.textAlign,
    this.onOpenLink,
  });

  final Announcement announcement;
  final TextStyle style;
  final TextAlign? textAlign;

  /// Where link taps go. Null (production) is [launchExternalUrl]; tests
  /// inject a recorder.
  final ValueChanged<String>? onOpenLink;

  @override
  State<NoticeText> createState() => _NoticeTextState();
}

class _NoticeTextState extends State<NoticeText> {
  /// Recognizers backing the current build's link spans — replaced wholesale
  /// each build and disposed with the state, as [TextSpan.recognizer] requires.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.announcement.messageHtml;
    if (html == null) {
      return Text(
        widget.announcement.message,
        style: widget.style,
        textAlign: widget.textAlign,
      );
    }
    _disposeRecognizers();
    final open = widget.onOpenLink ?? launchExternalUrl;
    final spans = <TextSpan>[];
    for (final span in parseNoticeMarkup(html)) {
      TapGestureRecognizer? recognizer;
      final link = span.linkUrl;
      if (link != null) {
        recognizer = TapGestureRecognizer()..onTap = () => open(link);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: span.text,
          recognizer: recognizer,
          style: TextStyle(
            // Every base style stays below w800, so bold steps up from it.
            fontWeight: span.bold ? FontWeight.w800 : null,
            fontStyle: span.italic ? FontStyle.italic : null,
            decoration: (span.underline || link != null)
                ? TextDecoration.underline
                : null,
            color: span.color != null ? Color(span.color!) : null,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      textAlign: widget.textAlign,
    );
  }
}
