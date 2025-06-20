import 'dart:async' show TimeoutException;
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

import 'models/interaction.dart';
import 'models/url_entry.dart';
import 'webview_manager.dart';

// Define typedef outside the class
typedef ScreenshotCallback = void Function(String path);

enum WaitType {
  delay,
  element,
  javascriptCondition,
  waitForNetworkIdle,
}

class Crawler {
  final Queue<UrlEntry> _urlsToVisit = Queue<UrlEntry>();
  final Set<UrlEntry> _visitedUrls = <UrlEntry>{};
  String? _currentOrigin;
  final WebViewManager webViewManager;
  int visitedCount = 0;
  int toVisitCount = 0;
  final int maxDepth;
  
  final Logger _logger;
  bool _isStopping = false;

  final void Function(int)? onVisitedCountChanged;
  final void Function(int)? onToVisitCountChanged;
  final void Function()? onCrawlCompleted;
  final void Function(String)? onPageStartedLoading;
  final int crawlPathLookback;
  final ScreenshotCallback? onScreenshotCaptured;

  UrlEntry? _currentProcessingEntry;

  Crawler({
    required Logger logger,
    required this.webViewManager,
    required this.maxDepth,
    required this.crawlPathLookback,
    this.onVisitedCountChanged,
    this.onToVisitCountChanged,
    this.onCrawlCompleted,
    this.onPageStartedLoading,
    this.onScreenshotCaptured,
  })  : _logger = logger;

  // Helper method for testing
  void addUrlToVisitQueueForTest(UrlEntry entry) => _urlsToVisit.add(entry);

  // Helper method for testing
  void addUrlToVisitedSetForTest(UrlEntry entry) => _visitedUrls.add(entry);

  // Helper method for testing
  Future<void> processNextUrlForTest() async => _processNextUrl();

  // TODO: Implement interaction logic
  List<Interaction> _getInteractionsForUrl(String url, String? htmlContent) {
    return [];
  }

  Future<void> startCrawl(String initialUrl) async {
    if (_isStopping) return;

    String cleanedUrl = initialUrl.trim();
    if (!cleanedUrl.startsWith('http://') && !cleanedUrl.startsWith('https://')) {
      cleanedUrl = 'https://$cleanedUrl';
    }

    try {
      Uri uri = Uri.parse(cleanedUrl);
      _currentOrigin = "${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}";
    } catch (e) {
      _logger.e("Error parsing initial URL: $e", error: e);
      return;
    }

    _urlsToVisit.clear();
    _visitedUrls.clear();
    visitedCount = 0;
    toVisitCount = 0;
    onVisitedCountChanged?.call(visitedCount);
    onToVisitCountChanged?.call(toVisitCount);

 _urlsToVisit.add(UrlEntry(url: cleanedUrl, depth: 0, crawlPath: []));
    _processNextUrl();
  }

  void _addToCrawlQueue(UrlEntry entry) {
    _urlsToVisit.add(entry);
    toVisitCount++;
    onToVisitCountChanged?.call(toVisitCount);
  }

  void stopCrawl() {
    _isStopping = true;
    _logger.i("Crawl stopping...");
    webViewManager.stopLoading();
  }

  void _processNextUrl() async {
    if (_isStopping) {
      _logger.i("Crawl process is stopping. Aborting _processNextUrl.");
      return;
    }
    
    if (_urlsToVisit.isEmpty) {
      _logger.i("Crawl completed.");
      onCrawlCompleted?.call();
      return;
    }

    UrlEntry nextEntry = _urlsToVisit.removeFirst();
    toVisitCount--;
    onToVisitCountChanged?.call(toVisitCount);

    if (_visitedUrls.any((entry) => entry.url == nextEntry.url)) {
      _logger.i("Skipping already visited URL: ${nextEntry.url}");
      return;
    }

    _visitedUrls.add(nextEntry);
    visitedCount++;
    onVisitedCountChanged?.call(visitedCount);
    _currentProcessingEntry = nextEntry;

    try {
      onPageStartedLoading?.call(nextEntry.url);
      await webViewManager.loadUrl(nextEntry.url).timeout(const Duration(seconds: 30));
    } on TimeoutException catch (e, stackTrace) {
      _logger.e("Timeout loading URL: ${nextEntry.url}", error: e, stackTrace: stackTrace);
      if (_currentProcessingEntry != null) _currentProcessingEntry!.status = UrlStatus.error;
      _onPageLoadError(nextEntry.url, "Timeout");
    } catch (e, stackTrace) {
      _logger.e("Error loading URL ${nextEntry.url}: $e", error: e, stackTrace: stackTrace);
      if (_currentProcessingEntry != null) _currentProcessingEntry!.status = UrlStatus.error;
       _onPageLoadError(nextEntry.url, e.toString());
    }
  }

  void _onPageLoadError(String url, String errorMessage) {
    _logger.e("Page failed to load: $url, Error: $errorMessage");
    _currentProcessingEntry = null;
  }

  void onPageLoaded(String loadedUrl, int? statusCode) async {
    if (_isStopping || _currentProcessingEntry == null) {
      if (_isStopping) _logger.i("Stopping crawl process in onPageLoaded.");
      return;
    }

    if (statusCode != null && (statusCode >= 400 || statusCode < 200)) {
      _logger.e('Page loaded with HTTP error status code: $loadedUrl (Status: $statusCode)');
      _currentProcessingEntry!.status = UrlStatus.error;
      _currentProcessingEntry!.errorMessage = 'HTTP Error: $statusCode';
      _currentProcessingEntry = null;
      _processNextUrl();
      return;
    }

    String? actualLoadedUrl = await webViewManager.runJavaScript("return window.location.href;");
    if (actualLoadedUrl != null && actualLoadedUrl != _currentProcessingEntry!.url) {
      _logger.i("Redirect detected: ${_currentProcessingEntry!.url} -> $actualLoadedUrl");
      _currentProcessingEntry = UrlEntry(
          url: actualLoadedUrl,
          depth: _currentProcessingEntry!.depth,
          parentUrl: _currentProcessingEntry!.parentUrl,
          crawlPath: List.from(_currentProcessingEntry!.crawlPath));
    }
    final finalUrl = actualLoadedUrl ?? loadedUrl;

    _logger.i("Page loaded in WebView: $finalUrl (Depth: ${_currentProcessingEntry!.depth})");
    _currentProcessingEntry!.status = UrlStatus.visited;

    await waitForPageContent(WaitType.delay, delay: const Duration(seconds: 2));

    String? htmlContent = await webViewManager.getHtmlContent();
    List<Interaction> interactions = _getInteractionsForUrl(finalUrl, htmlContent);
    if (interactions.isNotEmpty) {
      _logger.i("Executing interactions for $finalUrl");
      // for (var interaction in interactions) { 
      //   // ... use interaction object ...
      // }
      htmlContent = await webViewManager.getHtmlContent();
    }
    
    if (_isStopping) return;

    if (htmlContent != null) {
      dom.Document document = parse(htmlContent);
      await _extractLinks(document, finalUrl, _currentProcessingEntry!);
      await _captureScreenshot(document, finalUrl);
    } else {
       _logger.w("Could not get HTML content for $finalUrl. Skipping link extraction and screenshot.");
    }

    _currentProcessingEntry = null;
    _processNextUrl();
  }

  Future<void> _extractLinks(dom.Document document, String loadedUrl, UrlEntry currentEntry) async {
    if (maxDepth != -1 && currentEntry.depth >= maxDepth) {
      _logger.d("Max depth reached. Skipping link extraction for: $loadedUrl");
      return;
    }

    List<String> allDiscoveredLinks = extractLinks(document, loadedUrl);
    int linksAddedCount = 0;

    for (var rawLink in allDiscoveredLinks) {
      String? resolvedUrl;
      try {
        resolvedUrl = Uri.parse(loadedUrl).resolveUri(Uri.parse(rawLink)).toString();
      } catch (e, stackTrace) {
        _logger.e("Error resolving URL $rawLink from $loadedUrl: $e", error: e, stackTrace: stackTrace);
        continue;
      }

      if (!resolvedUrl.startsWith(_currentOrigin!)) {
        continue;
      }
      
      String normalizedUrl = Uri.parse(resolvedUrl).removeFragment().toString();

 if (!_visitedUrls.any((entry) => entry.url == normalizedUrl) && !_urlsToVisit.any((entry) => entry.url == normalizedUrl)) {
        UrlEntry newEntry = UrlEntry(
          url: normalizedUrl,
          depth: currentEntry.depth + 1,
          crawlPath: List.from(currentEntry.crawlPath)..add(currentEntry.url),
          parentUrl: loadedUrl,
        );
        _addToCrawlQueue(newEntry);
        linksAddedCount++;
      }
    }
    _logger.i("Finished link extraction for $loadedUrl. Added $linksAddedCount new links.");
  }

  Future<void> _captureScreenshot(dom.Document document, String loadedUrl) async {
      try {
        Uint8List? screenshotBytes = await webViewManager.takeScreenshot();
        if (screenshotBytes != null) {
            final String? filePath = await _saveScreenshot(screenshotBytes, loadedUrl);
            if(filePath != null) {
               _currentProcessingEntry?.screenshotPath = filePath;
               _logger.i("Screenshot saved to: $filePath");
               onScreenshotCaptured?.call(filePath);
            }
        } else {
           _logger.w("No screenshot captured for $loadedUrl.");
        }
      } catch(e, stackTrace) {
          _logger.e("Error capturing screenshot for $loadedUrl: $e", error: e, stackTrace: stackTrace);
      }
  }

  Future<String?> _saveScreenshot(Uint8List imageBytes, String loadedUrl) async {
     try {
      String urlPath = Uri.parse(loadedUrl).path;
      String host = Uri.parse(loadedUrl).host;

      String sanitizedHost = host.replaceAll(RegExp(r'[^\w.-]'), '_');
      String sanitizedPath = urlPath.replaceAll(RegExp(r'[^a-zA-Z0-9_/-]'), '_');

      sanitizedPath = sanitizedPath
          .replaceAll(RegExp(r'/+'), '/')
          .replaceAll(RegExp(r'^[/_]|[/_]$'), '')
          .replaceAll(RegExp(r'__+'), '_');

      Directory baseDir = await getApplicationDocumentsDirectory();
      String dirPath = '${baseDir.path}/screenshots/$sanitizedHost/$sanitizedPath';
      if (sanitizedPath.isEmpty) {
        dirPath = '${baseDir.path}/screenshots/$sanitizedHost';
      }
      
      Directory screenshotDirectory = Directory(dirPath);
      if (!await screenshotDirectory.exists()) {
        await screenshotDirectory.create(recursive: true);
      }

      String filename = 'screenshot.png';
      String filePath = '${screenshotDirectory.path}/$filename';
      final file = File(filePath);
      await file.writeAsBytes(imageBytes);
      return filePath;
     } catch (e, stackTrace) {
        _logger.e("Failed to save screenshot for $loadedUrl", error: e, stackTrace: stackTrace);
        return null;
     }
  }

  Future<void> waitForPageContent(
    WaitType waitType, {
    Duration? delay,
    String? selector,
    String? javascriptCondition,
  }) async {
    switch (waitType) {
      case WaitType.delay:
        if (delay != null) {
          _logger.i("Waiting for ${delay.inSeconds} seconds...");
          await Future.delayed(delay);
          _logger.i("Wait completed.");
        }
        break;
      case WaitType.element:
        if (selector != null) {
          _logger.w("WaitType.element is not yet implemented.");
        }
        break;
      case WaitType.javascriptCondition:
        if (javascriptCondition != null) {
          _logger.w("WaitType.javascriptCondition is not yet implemented.");
        }
        break;
      case WaitType.waitForNetworkIdle:
        try {
          _logger.i("Waiting for network idle... (Using fallback delay)");
          await Future.delayed(const Duration(seconds: 1)); // Fallback delay
          _logger.i("Network idle wait finished.");
        } catch (e, stackTrace) {
          _logger.w("Error or timeout waiting for network idle: $e", error: e, stackTrace: stackTrace);
        }
        break;
    }
  }

  List<String> extractLinks(dom.Document document, String baseUrl) {
    List<String> extractedLinks = [];
    List<dom.Element> anchors = document.querySelectorAll('a');
    for (var anchor in anchors) {
      String? href = anchor.attributes['href']?.trim();
      if (href != null &&
          href.isNotEmpty &&
          !href.startsWith('#') &&
          !href.startsWith('javascript:') &&
          !href.startsWith('mailto:') &&
          !href.startsWith('tel:')) {
        try {
          extractedLinks.add(Uri.parse(baseUrl).resolve(href).toString());
        } catch (_) {
          _logger.w("Could not parse link: $href");
        }
      }
    }
    return extractedLinks;
 }
}