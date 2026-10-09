import 'package:http/http.dart' as http;

/// News articles about the current situation, via Google News RSS.
/// Free, no key. Titles + source + link only — articles open in the
/// browser.
class NewsArticle {
  final String title;
  final String source;
  final String url;
  final String published;

  const NewsArticle({
    required this.title,
    required this.source,
    required this.url,
    required this.published,
  });
}

class NewsService {
  static const _timeout = Duration(seconds: 15);
  static final Map<String, List<NewsArticle>> _cache = {};
  static final Map<String, DateTime> _fetched = {};
  static const _cacheTtl = Duration(minutes: 30);

  /// Top articles for [query] (e.g. "Hurricane Isaias"), newest first.
  static Future<List<NewsArticle>> forQuery(String query,
      {int max = 8}) async {
    final key = query.toLowerCase();
    final f = _fetched[key];
    if (_cache.containsKey(key) &&
        f != null &&
        DateTime.now().difference(f) < _cacheTtl) {
      return _cache[key]!;
    }
    try {
      final articles = await _fetch(query, max);
      _cache[key] = articles;
      _fetched[key] = DateTime.now();
      return articles;
    } catch (_) {
      return _cache[key] ?? [];
    }
  }

  static Future<List<NewsArticle>> _fetch(
      String query, int max) async {
    final uri = Uri.parse(
        'https://news.google.com/rss/search'
        '?q=${Uri.encodeComponent(query)}&hl=en-US&gl=US&ceid=US:en');
    final r = await http.get(uri, headers: {
      'User-Agent': 'Mozilla/5.0',
    }).timeout(_timeout);
    if (r.statusCode != 200) return [];

    // Minimal RSS parsing — no XML dependency for three fields.
    final articles = <NewsArticle>[];
    final itemRe =
        RegExp(r'<item>(.*?)</item>', dotAll: true);
    final titleRe =
        RegExp(r'<title>(.*?)</title>', dotAll: true);
    final linkRe = RegExp(r'<link>(.*?)</link>', dotAll: true);
    final sourceRe =
        RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true);
    final dateRe =
        RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true);
    for (final m in itemRe.allMatches(r.body)) {
      if (articles.length >= max) break;
      final item = m.group(1)!;
      final title =
          _clean(titleRe.firstMatch(item)?.group(1) ?? '');
      final link =
          _clean(linkRe.firstMatch(item)?.group(1) ?? '');
      if (title.isEmpty || link.isEmpty) continue;
      articles.add(NewsArticle(
        title: title,
        source:
            _clean(sourceRe.firstMatch(item)?.group(1) ?? ''),
        url: link,
        published:
            _clean(dateRe.firstMatch(item)?.group(1) ?? ''),
      ));
    }
    return articles;
  }

  static String _clean(String s) => s
      .replaceAll('<![CDATA[', '')
      .replaceAll(']]>', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
