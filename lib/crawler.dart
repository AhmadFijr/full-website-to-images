import 'package:image/image.dart' as image;
import 'package:myapp/models/data_extraction_rule.dart';

import 'models/interaction.dart';
import 'models/url_entry.dart';
import 'webview_manager.dart';

import 'dart:async' show TimeoutException;
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// Define typedef outside the class
typedef ScreenshotCallback = void Function(String path);

/// Enum defining the types of waits that can be performed.
enum WaitType { delay, element, javascriptCondition, waitForNetworkIdle }

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

  final Map<String, List<Cookie>> _allCookies = {};
  // Callbacks
  final void Function(int)? onVisitedCountChanged;
  final void Function(int)? onToVisitCountChanged;
  final Map<String, List<Interaction>> _interactionRules = {
    'http://example.com/login': [
      Interaction(
        type: InteractionType.input,
        selector: '#username',
        value: 'testuser',
      ),
      Interaction(
        type: InteractionType.input,
        selector: '#password',
        value: 'testpassword',
      ),
      Interaction(type: InteractionType.click, selector: '#login-button'),
    ],
    // Example rule for a cookie consent button on any page
    // This is a simple example, real-world selectors might vary.
    '/': [
      Interaction(
        type: InteractionType.click,
        selector: '#cookie-consent-button',
      ),
    ],
  };
  final Map<String, List<DataExtractionRule>> _extractionRules = {};
  final void Function()? onCrawlCompleted;
  final void Function(String)? onPageStartedLoading;
  final ScreenshotCallback? onScreenshotCaptured;
  // Consider adding a callback for extracted data here, e.g.:
  // final void Function(String url, Map<String, dynamic> data)? onDataExtracted;
  final int crawlPathLookback;

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
  }) : _logger = logger;

  // Helper method for testing
  void addUrlToVisitQueueForTest(UrlEntry entry) => _urlsToVisit.add(entry);

  // Helper method for testing
  void addUrlToVisitedSetForTest(UrlEntry entry) => _visitedUrls.add(entry);

  // Helper method for testing
  Future<void> processNextUrlForTest() async => _processNextUrl();

  // Core Crawling Logic
  List<Interaction> _getInteractionsForUrl(String url, String? htmlContent) {
    if (_interactionRules.containsKey(url)) {
      _logger.i("Applying defined interactions for $url");
      return _interactionRules[url]!;
    }
    // Default to no interactions for other URLs
    _logger.d("No specific interactions defined for $url");
    return [];
  }

  Future<void> startCrawl(String initialUrl) async {
    if (_isStopping) return;

    String cleanedUrl = initialUrl.trim();
    if (!cleanedUrl.startsWith('http://') &&
        !cleanedUrl.startsWith('https://')) {
      cleanedUrl = 'https://$cleanedUrl';
    }

    try {
      Uri uri = Uri.parse(cleanedUrl);
      _currentOrigin =
          "${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}";
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

  // Private methods
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
      await webViewManager
          .loadUrl(nextEntry.url)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException catch (e, stackTrace) {
      _logger.e(
        "Timeout loading URL: ${nextEntry.url}",
        error: e,
        stackTrace: stackTrace,
      );
      if (_currentProcessingEntry != null) {
        _currentProcessingEntry!.status = UrlStatus.error;
      }
      _onPageLoadError(nextEntry.url, "Timeout");
    } catch (e, stackTrace) {
      _logger.e(
        "Error loading URL ${nextEntry.url}: $e",
        error: e,
        stackTrace: stackTrace,
      );
      if (_currentProcessingEntry != null) {
        _currentProcessingEntry!.status = UrlStatus.error;
      }
      _onPageLoadError(nextEntry.url, e.toString());
    }
  }

  void _onPageLoadError(String url, String errorMessage) {
    _logger.e("Page failed to load: $url, Error: $errorMessage");
    _currentProcessingEntry = null;
  }

  void onPageLoaded(String loadedUrl, int? statusCode) async {
    _logger.i("onPageLoaded triggered for $loadedUrl with status code $statusCode");

    if (_isStopping || _currentProcessingEntry == null) {
      if (_isStopping) _logger.i("Stopping crawl process in onPageLoaded.");
      return;
    }

    if (statusCode != null && (statusCode >= 400 || statusCode < 200)) {
      _logger.e(
        'Page loaded with HTTP error status code: $loadedUrl (Status: $statusCode)',
      );
      _currentProcessingEntry!.status = UrlStatus.error;
      _currentProcessingEntry!.errorMessage = 'HTTP Error: $statusCode';
      _currentProcessingEntry = null;
      _processNextUrl();
      return;
    }

    String? actualLoadedUrl = await webViewManager.runJavaScript(
      "return window.location.href;",
    );
    if (actualLoadedUrl != null &&
        actualLoadedUrl != _currentProcessingEntry!.url) {
      _logger.i(
        "Redirect detected: ${_currentProcessingEntry!.url} -> $actualLoadedUrl",
      );
      _currentProcessingEntry = UrlEntry(
        url: actualLoadedUrl,
        depth: _currentProcessingEntry!.depth,
        parentUrl: _currentProcessingEntry!.parentUrl,
        crawlPath: List.from(_currentProcessingEntry!.crawlPath),
      );
    }
    final finalUrl = actualLoadedUrl ?? loadedUrl;

    _logger.i(
      "Page loaded in WebView: $finalUrl (Depth: ${_currentProcessingEntry!.depth})",
    );
    _currentProcessingEntry!.status = UrlStatus.visited;

    // Get cookies for the loaded page
    try {
      final webUri = WebUri(finalUrl); // قم بإنشاء WebUri
      final cookies = await CookieManager.instance().getCookies(url: webUri); // استخدم WebUri هنا
      _logger.d("Retrieved ${cookies.length} cookies for $finalUrl");
      // Store cookies in the map
      for (var cookie in cookies) {
        final domain = cookie.domain;
        if (domain != null && domain.isNotEmpty) {
 _allCookies.putIfAbsent(domain, () => []).add(cookie);
        }
      }
    } catch (e) {
      _logger.e("Error getting cookies for $finalUrl: $e", error: e);
    }

    await waitForPageContent(WaitType.delay, delay: const Duration(seconds: 2));

    String? htmlContent = await webViewManager.getHtmlContent();
    List<Interaction> interactions = _getInteractionsForUrl(
      finalUrl,
      htmlContent,
    );
    if (interactions.isNotEmpty) {
      _logger.i("Executing interactions for $finalUrl");
      for (var interaction in interactions) {
        if (_isStopping) break; // Stop processing interactions if stopping

        // Wait for element if a selector is provided and not empty
        if (interaction.selector != null && interaction.selector!.isNotEmpty) {
          await waitForPageContent(
            WaitType.element,
            selector: interaction.selector,
          );
        }

        // Execute the interaction
        String? jsScript;
        if (interaction.type == InteractionType.click &&
            interaction.selector != null) {
          jsScript =
              "document.querySelector('${interaction.selector}').click();";
        } else if (interaction.type == InteractionType.input &&
            interaction.selector != null &&
            interaction.value != null) {
          // Escape single quotes in the value to avoid breaking the JS string
          final escapedValue = interaction.value!.replaceAll("'", "\\'");
          jsScript =
              "document.querySelector('${interaction.selector}').value = '$escapedValue';";
        }

        if (jsScript != null) {
          await webViewManager.runJavaScript(jsScript);
        }
      }
    }

    if (_isStopping) return;

    // Data Extraction Logic
    if (htmlContent != null) {
      // Redundant check, can be removed
      dom.Document document = parse(htmlContent);

      if (_extractionRules.containsKey(finalUrl)) {
        _logger.i("Extracting data for $finalUrl");
        final extractionRules = _extractionRules[finalUrl]!;
        final extractedData =
            <String, dynamic>{}; // Store data for the current URL

        for (var rule in extractionRules) {
          final elements = document.querySelectorAll(rule.selector);
          final extractedValues = <dynamic>[];
          for (var element in elements) {
            if (rule.dataType == 'string') {
              // Assuming 'string' means text content
              extractedValues.add(element.text.trim());
            } else if (rule.dataType.startsWith('attribute:') &&
                rule.attributeName != null) {
              // Assuming 'attribute:attributename'
              extractedValues.add(
                element.attributes[rule.attributeName]?.trim(),
              );
            }
          }
          extractedData[rule.selector] =
              extractedValues; // Store under selector for now
        }
        _logger.i("Extracted data for $finalUrl: $extractedData");
      }

      await _captureScreenshot(document, finalUrl);

      await _extractLinks(
        document,
        finalUrl,
        _currentProcessingEntry!,
      ); // Call _extractLinks after extraction
    } else {
      _logger.w(
        "Could not get HTML content for $finalUrl. Skipping link extraction and screenshot.",
      );
    }

    _currentProcessingEntry = null;
    _processNextUrl();
  }

  // Helper methods (sorted alphabetically or logically if needed)
  Future<void> _extractLinks(
    dom.Document document,
    String loadedUrl,
    UrlEntry currentEntry,
  ) async {
    if (maxDepth != -1 && currentEntry.depth >= maxDepth) {
      _logger.d("Max depth reached. Skipping link extraction for: $loadedUrl");
      return;
    }

    List<String> allDiscoveredLinks = extractLinks(document, loadedUrl);
    int linksAddedCount = 0;

    for (var rawLink in allDiscoveredLinks) {
      String? resolvedUrl;
      try {
        resolvedUrl =
            Uri.parse(loadedUrl).resolveUri(Uri.parse(rawLink)).toString();
      } catch (e, stackTrace) {
        _logger.e(
          "Error resolving URL $rawLink from $loadedUrl: $e",
          error: e,
          stackTrace: stackTrace,
        );
        continue;
      }

      if (!resolvedUrl.startsWith(_currentOrigin!)) {
        continue;
      }

      String normalizedUrl = Uri.parse(resolvedUrl).removeFragment().toString();

      if (!_visitedUrls.any((entry) => entry.url == normalizedUrl) &&
          !_urlsToVisit.any((entry) => entry.url == normalizedUrl)) {
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
    _logger.i(
      "Finished link extraction for $loadedUrl. Added $linksAddedCount new links.",
    );
  }

  Future<void> _captureScreenshot(
    dom.Document document,
    String loadedUrl,
  ) async {
    try {
      Uint8List? screenshotBytes = await webViewManager.takeScreenshot();
      if (screenshotBytes != null) {
        final String? filePath = await _saveScreenshot(
          screenshotBytes,
          loadedUrl,
        );
        if (filePath != null) {
          _currentProcessingEntry?.screenshotPath = filePath;
          _logger.i("Screenshot saved to: $filePath");
          onScreenshotCaptured?.call(filePath);
        }
      } else {
        _logger.w("No screenshot captured for $loadedUrl.");
      }
    } catch (e, stackTrace) {
      _logger.e(
        "Error capturing screenshot for $loadedUrl: $e",
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String?> _saveScreenshot(
    Uint8List imageBytes,
    String loadedUrl,
  ) async {
    try {
      String urlPath = Uri.parse(loadedUrl).path;
      String host = Uri.parse(loadedUrl).host;

      String sanitizedHost = host.replaceAll(RegExp(r'[^\w.-]'), '_');
      String sanitizedPath = urlPath.replaceAll(
        RegExp(r'[^a-zA-Z0-9_/-]'),
        '_',
      );

      sanitizedPath = sanitizedPath
          .replaceAll(RegExp(r'/+'), '/')
          .replaceAll(RegExp(r'^[/_]|[/_]$'), '')
          .replaceAll(RegExp(r'__+'), '_');

      Directory baseDir = await getApplicationDocumentsDirectory();
      String dirPath =
          '${baseDir.path}/screenshots/$sanitizedHost/$sanitizedPath';
      if (sanitizedPath.isEmpty) {
        dirPath = '${baseDir.path}/screenshots/$sanitizedHost';
      }

      _logger.d("Attempting to save screenshot to: $dirPath");
      Directory screenshotDirectory = Directory(dirPath);
      if (!await screenshotDirectory.exists()) {
        await screenshotDirectory.create(recursive: true);
      }

      String filename = 'screenshot.png';
      String filePath = '${screenshotDirectory.path}/$filename';
      final file = File(filePath);
      _logger.d("Writing screenshot file: $filePath");
      await file.writeAsBytes(imageBytes);
      return filePath;
    } catch (e, stackTrace) {
      _logger.e("Failed to save screenshot for $loadedUrl: $e", stackTrace: stackTrace);
      return null;
    }
  }

  /// Stitches a list of image parts (Uint8List) into a single image.
  /// Returns the combined image as Uint8List (PNG format) or null if stitching fails.
  Future<List<int>?> stitchImages(List<Uint8List> screenshotParts) async {
    // Remove the try-catch block within the loop if it's not needed for individual part processing errors.
    // If you intended error handling for decoding individual parts, the existing check `if (img != null)` is sufficient.

    final List<image.Image> decodedImages = [];
    
    for (final partBytes in screenshotParts) { // Removed redundant loop variable definition

      // Loop through screenshot parts
      final img = image.decodeImage(partBytes);
      if (img != null) {
        decodedImages.add(img);
      } else {
        // Log a warning for invalid image parts if logging is accessible here
        // or handle accordingly.
        _logger.w("Skipping invalid image part during stitching.");
      }
    }

    if (decodedImages.isEmpty) {
      _logger.w("No valid images to stitch.");
      return null;
    }

    int totalHeight = 0;
    int maxWidth = 0;

    for (var img in decodedImages) {
      totalHeight += img.height;
      if (img.width > maxWidth) {
        maxWidth = img.width;
      }
    }
    
    
    // Create a new image with calculated dimensions
    // Use a suitable background color, e.g., black
    // Updated constructor based on common usage in recent 'image' package versions
    final finalImage = image.Image(maxWidth, totalHeight);

    int currentHeight = 0;
    for (var img in decodedImages) {
      // Draw the image onto the final image at the correct position
      image.copyInto(finalImage, img, dstY: currentHeight);
      currentHeight += img.height;
    }

    // Encode the combined image as PNG
    final stitchedBytes = image.encodePng(finalImage);

    // Added image saving functionality
    try {
      // Get the application documents directory
      final directory = await getApplicationDocumentsDirectory();
      final imagesDirectory = Directory('${directory.path}/screenshots');

      // Create the screenshots directory if it doesn't exist
      if (!await imagesDirectory.exists()) {
        await imagesDirectory.create(recursive: true);
        _logger.i("Created screenshots directory: ${imagesDirectory.path}");
      }

      // Define the file path within the screenshots directory with a unique filename
      final filePath = '${imagesDirectory.path}/stitched_image_${DateTime.now().millisecondsSinceEpoch}.png';

      final File file = File(filePath);
      await file.writeAsBytes(stitchedBytes);
      _logger.i("Stitched image saved to: $filePath");
      return stitchedBytes; // Return the stitched image bytes
    } catch (e) {
      _logger.e("Error saving stitched image: $e");
    }
    _logger.i("Successfully stitched ${decodedImages.length} image parts.");
    return null;

  }

  Future<void> waitForPageContent(
    // Moved down as it's a helper
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
        // Existing logic for waiting for element
        if (selector == null) {
          _logger.w("WaitType.element requires a selector.");
          break;
        }
        _logger.i("Waiting for element with selector: $selector...");
        const timeout = Duration(seconds: 10);
        const interval = Duration(milliseconds: 200);
        final startTime = DateTime.now();
        bool elementFound = false;

        while (DateTime.now().difference(startTime) < timeout && !_isStopping) {
          final jsResult = await webViewManager.runJavaScript(
            "document.querySelector('$selector') !== null;",
          );
          if (jsResult == 'true') {
            elementFound = true;
            break;
          }
          await Future.delayed(interval);
        }
        _logger.i("Wait for element finished. Element found: $elementFound");
      case WaitType.javascriptCondition:
        if (javascriptCondition == null) {
          // Existing logic for waiting for JS condition
          _logger.w(
            "WaitType.javascriptCondition requires a javascriptCondition string.",
          );
          break;
        }
        _logger.i("Waiting for JavaScript condition: $javascriptCondition...");
        const timeout = Duration(seconds: 10);
        const interval = Duration(milliseconds: 200);
        final startTime = DateTime.now();

        while (DateTime.now().difference(startTime) < timeout && !_isStopping) {
          final jsResult = await webViewManager.runJavaScript(
            javascriptCondition,
          );
          if (jsResult == 'true') {
            break;
          }
          await Future.delayed(interval);
        }
        break;
      case WaitType.waitForNetworkIdle:
        try {
          _logger.i("Waiting for network idle... (Using fallback delay)");
          await Future.delayed(const Duration(seconds: 1)); // Fallback delay
          _logger.i("Network idle wait finished.");
        } catch (e, stackTrace) {
          _logger.w(
            "Error or timeout waiting for network idle: $e",
            error: e,
            stackTrace: stackTrace,
          );
        }
        break;
    }
  }

  List<String> extractLinks(dom.Document document, String baseUrl) {
    List<String> extractedLinks = [];
    List<dom.Element> elementsWithHref = document.querySelectorAll(
      '[href]',
    ); // Select elements with href attribute
    for (var element in elementsWithHref) {
      String? href = element.attributes['href']?.trim();
      if (href != null &&
          href.isNotEmpty &&
          !href.startsWith('#') &&
          !href.startsWith('javascript:') &&
          !href.startsWith('mailto:') &&
          !href.startsWith('tel:')) {
        try {
          extractedLinks.add(Uri.parse(baseUrl).resolve(href).toString());
        } catch (_) {
          _logger.w("Could not parse link from href: $href");
        }
      }
    }

    List<dom.Element> elementsWithSrc = document.querySelectorAll(
      '[src]',
    ); // Select elements with src attribute
    for (var element in elementsWithSrc) {
      String? src = element.attributes['src']?.trim();
      if (src != null && src.isNotEmpty) {
        try {
          extractedLinks.add(Uri.parse(baseUrl).resolve(src).toString());
        } catch (_) {
          _logger.w(
            "Could not parse link from src for ${element.localName}: $src",
          );
        }
      }
    }

    // Also check data-src for lazy-loaded images (elements with data-src)
    List<dom.Element> elementsWithDataSrc = document.querySelectorAll(
      '[data-src]',
    );
    for (var element in elementsWithDataSrc) {
      String? dataSrc = element.attributes['data-src']?.trim();
      if (dataSrc != null && dataSrc.isNotEmpty) {
        try {
          extractedLinks.add(Uri.parse(baseUrl).resolve(dataSrc).toString());
        } catch (_) {
          _logger.w(
            "Could not parse link from data-src for ${element.localName}: $dataSrc",
          );
        }
      }
    }

    return extractedLinks;
  }
}
