enum UrlStatus { pending, visiting, visited, error, looped }

class UrlEntry {
  final String url;
  UrlStatus status;
  final int depth;
  final String? parentUrl;
  final List<String> crawlPath;
  String? screenshotPath;
  String? errorMessage;

  UrlEntry({
    required this.url,
    this.status = UrlStatus.pending,
    required this.depth,
    this.parentUrl,
    required this.crawlPath,
    this.screenshotPath,
    this.errorMessage,

  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UrlEntry && runtimeType == other.runtimeType && url == other.url;

  @override
  int get hashCode => url.hashCode;
}