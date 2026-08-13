import 'package:flutter_test/flutter_test.dart';
import 'package:roadmate/services/notice_markup.dart';

void main() {
  group('parseNoticeMarkup', () {
    test('plain text passes through as one unstyled span', () {
      expect(parseNoticeMarkup('Fuel deal at BP Yass'), const [
        NoticeSpan('Fuel deal at BP Yass'),
      ]);
    });

    test('bold, italic and underline, in both spellings', () {
      expect(parseNoticeMarkup('<b>a</b><strong>b</strong>'), const [
        NoticeSpan('a', bold: true),
        NoticeSpan('b', bold: true),
      ]);
      expect(parseNoticeMarkup('<i>a</i><em>b</em>'), const [
        NoticeSpan('a', italic: true),
        NoticeSpan('b', italic: true),
      ]);
      expect(parseNoticeMarkup('<u>a</u>'), const [
        NoticeSpan('a', underline: true),
      ]);
    });

    test('nested styles combine on the inner run', () {
      expect(parseNoticeMarkup('<b>bold <i>both</i></b>'), const [
        NoticeSpan('bold ', bold: true),
        NoticeSpan('both', bold: true, italic: true),
      ]);
    });

    test('links carry their href, double- or single-quoted', () {
      expect(
        parseNoticeMarkup('See <a href="https://roadmate.club">the site</a>.'),
        const [
          NoticeSpan('See '),
          NoticeSpan('the site', linkUrl: 'https://roadmate.club'),
          NoticeSpan('.'),
        ],
      );
      expect(parseNoticeMarkup("<a href='http://example.com'>x</a>"), const [
        NoticeSpan('x', linkUrl: 'http://example.com'),
      ]);
    });

    test('only http/https links survive — everything else keeps its text', () {
      for (final href in [
        'javascript:alert(1)',
        'mailto:x@y.z',
        '/relative',
        '',
      ]) {
        expect(
          parseNoticeMarkup('<a href="$href">tap</a>'),
          const [NoticeSpan('tap')],
          reason: 'href="$href" must not become a link',
        );
      }
      expect(parseNoticeMarkup('<a>tap</a>'), const [NoticeSpan('tap')]);
    });

    test('font color applies within its tag', () {
      expect(parseNoticeMarkup('<font color="#F97316">hot</font> not'), const [
        NoticeSpan('hot', color: 0xFFF97316),
        NoticeSpan(' not'),
      ]);
    });

    test('a bad font colour is ignored, text kept', () {
      expect(parseNoticeMarkup('<font color="orange">hi</font>'), const [
        NoticeSpan('hi'),
      ]);
    });

    test('br becomes a newline, with or without the self-close', () {
      expect(parseNoticeMarkup('a<br>b<br/>c<br />d'), const [
        NoticeSpan('a\nb\nc\nd'),
      ]);
    });

    test('entities decode, including the amp-first trap', () {
      expect(
        plainTextOfNotice('Tom &amp; Jerry &lt;3 &quot;pies&quot;&nbsp;&#39;'),
        'Tom & Jerry <3 "pies" \'',
      );
      // "&amp;lt;" is the literal text "&lt;" — it must NOT double-decode.
      expect(plainTextOfNotice('&amp;lt;'), '&lt;');
    });

    test('unknown tags are stripped, their content kept', () {
      expect(
        parseNoticeMarkup('<marquee>hi</marquee> <script>x</script>'),
        const [NoticeSpan('hi x')],
      );
    });

    test('an unclosed tag styles through to the end', () {
      expect(parseNoticeMarkup('a <b>loud'), const [
        NoticeSpan('a '),
        NoticeSpan('loud', bold: true),
      ]);
    });

    test('stray close tags do nothing', () {
      expect(parseNoticeMarkup('a</b></a></font>b'), const [
        NoticeSpan('a'),
        NoticeSpan('b'),
      ]);
    });

    test('a literal < that opens no tag stays text', () {
      expect(parseNoticeMarkup('5 < 10 and 3<4'), const [
        NoticeSpan('5 < 10 and 3<4'),
      ]);
    });

    test('tag names are case-insensitive', () {
      expect(parseNoticeMarkup('<B>a</B><A HREF="https://x.io">b</A>'), const [
        NoticeSpan('a', bold: true),
        NoticeSpan('b', linkUrl: 'https://x.io'),
      ]);
    });
  });

  group('plainTextOfNotice / noticeHasMarkup', () {
    test('plain text is untouched and reads as markup-free', () {
      expect(plainTextOfNotice('Just words.'), 'Just words.');
      expect(noticeHasMarkup('Just words.'), isFalse);
      // A lone < is literal text, not markup.
      expect(noticeHasMarkup('5 < 10'), isFalse);
    });

    test('tags and entities both count as markup', () {
      expect(noticeHasMarkup('<b>hi</b>'), isTrue);
      expect(noticeHasMarkup('Tom &amp; Jerry'), isTrue);
      expect(
        plainTextOfNotice('<b>hi</b> <a href="https://x.io">go</a>'),
        'hi go',
      );
    });
  });

  group('parseHexColor', () {
    test('accepts #RRGGBB in either case', () {
      expect(parseHexColor('#F97316'), 0xFFF97316);
      expect(parseHexColor('#f97316'), 0xFFF97316);
      expect(parseHexColor('#000000'), 0xFF000000);
    });

    test('refuses everything else', () {
      for (final bad in [
        null,
        '',
        'F97316',
        '#F97',
        '#GGGGGG',
        '#F9731',
        '#F973161',
      ]) {
        expect(parseHexColor(bad), isNull, reason: '$bad must not parse');
      }
    });
  });

  group('prefersDarkForeground', () {
    test('light backgrounds take dark text, dark take light', () {
      expect(prefersDarkForeground(0xFFFFFFFF), isTrue); // white
      expect(prefersDarkForeground(0xFFFFEB3B), isTrue); // yellow
      expect(prefersDarkForeground(0xFF000000), isFalse); // black
      expect(prefersDarkForeground(0xFF2563EB), isFalse); // blue
      expect(prefersDarkForeground(0xFFDC2626), isFalse); // red
    });
  });
}
