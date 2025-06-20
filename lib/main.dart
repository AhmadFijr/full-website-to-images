import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart'
    as path_provider; // Use an alias
import 'dart:developer' as developer;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Screenshot App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Web Screenshot Tool'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _currentOrigin; // لتخزين أصل (Origin) الموقع المستهدف
  final Set<String> _visitedUrls =
      {}; // مجموعة لتخزين عناوين URL التي تم زيارتها
  final List<String> _urlsToVisit = []; // قائمة لعناوين URL التي يجب زيارتها
  int _pagesVisitedCount = 0;
  int _urlsToVisitCount = 0;
  late final InAppWebViewController _controller;
  String? _screenshotsDirectory;
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _initScreenshotsDirectory();
  }

  // void _initScreenshotsDirectory() async {
  //   final directory = await path_provider.getApplicationDocumentsDirectory();
  //   final screenshotsDir = Directory(_screenshotsDirectory!);
  //   if (!await screenshotsDir.exists()) {
  //     await screenshotsDir.create(recursive: true);
  //   }
  //   developer.log('Screenshots will be saved in: $_screenshotsDirectory');
  // }

  void _initScreenshotsDirectory() async {
    try {
      final directory = await path_provider.getApplicationDocumentsDirectory();
      if (directory.path.isNotEmpty) {
        _screenshotsDirectory = '${directory.path}/screenshots';
        final screenshotsDir = Directory(_screenshotsDirectory!);
        if (!await screenshotsDir.exists()) {
          await screenshotsDir.create(recursive: true);
        }
        developer.log('Screenshots will be saved in: $_screenshotsDirectory');
      } else {
        developer.log('Application documents directory is not available.');
      }
    } catch (e) {
      developer.log('Error initializing screenshots directory: $e');
    }
  }

  void _loadUrl() {
    final String url = _urlController.text.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        _currentOrigin =
            '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        _urlsToVisit.clear();
        _visitedUrls.clear();
        _urlsToVisit.add(url);
        _processNextUrl();
      } else {
        developer.log('Invalid URL: $url');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'أدخل عنوان URL للموقع',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _loadUrl, child: const Text('ابدأ')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text('Pages Visited: $_pagesVisitedCount'),
                Text('URLs to Visit: $_urlsToVisitCount'),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri("about:blank"),
              ), // Initial blank page
              initialSettings: InAppWebViewSettings(
                // Use InAppWebViewSettings
                javaScriptCanOpenWindowsAutomatically: true,
                javaScriptEnabled: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller; // Initialize the controller here
              },
              onProgressChanged: (controller, progress) {},
              onReceivedError: (controller, request, error) {
                developer.log(
                  'Web resource error: ${error.description} on ${request.url}',
                );
                _processNextUrl(); // Continue to the next URL even if an error occurs
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                // Allow all navigation requests for now
                return NavigationActionPolicy.ALLOW;
              },
              onLoadStop: (controller, url) {
                _extractLinksAndContinue();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _processNextUrl() {
    if (_urlsToVisit.isNotEmpty) {
      final nextUrl = _urlsToVisit.removeAt(0);

      if (!_visitedUrls.contains(nextUrl)) {
        setState(() {
          _visitedUrls.add(nextUrl);
          _pagesVisitedCount++;
          _urlsToVisitCount = _urlsToVisit.length;
        });
        developer.log('Visiting: $nextUrl');

        _controller.loadUrl(urlRequest: URLRequest(url: WebUri(nextUrl)));
      } else {
        _processNextUrl();
      }
    } else {
      developer.log('Finished crawling.');
    }
  }

  void _extractLinksAndContinue() async {
    developer.log('Page finished loading. Extracting links...');

    try {
      // Extract HTML content
      final htmlString =
          await _controller.evaluateJavascript(
                source: 'document.documentElement.outerHTML',
              )
              as String;

      // Parse HTML and extract links
      final document = parse(htmlString);
      final Iterable<dom.Element> anchorElements = document.querySelectorAll(
        'a',
      );

      developer.log('Found ${anchorElements.length} anchor elements.');

      // Optional: Interact with the page using JavaScript (example)
      try {
        // Example: Get the number of buttons
        final numberOfButtons = await _controller.evaluateJavascript(
          source: 'document.querySelectorAll("button").length',
        );
        developer.log('Number of buttons on the page: $numberOfButtons');
      } catch (e) {
        developer.log('Error executing JavaScript: $e');
      }

      // Example: Attempt to click on the first link
      try {
        await _controller.evaluateJavascript(
          source: 'document.querySelector("a")?.click();',
        );
        developer.log('Attempted to click on the first link.');
      } catch (e) {
        developer.log('Error executing JavaScript click: $e');
      }

      // Example: Scroll to the bottom
      try {
        await _controller.evaluateJavascript(
          source: 'window.scrollTo(0, document.body.scrollHeight);',
        );
        developer.log('Scrolled to the bottom of the page.');
      } catch (e) {
        developer.log('Error executing JavaScript scroll: $e');
      }

      for (final anchor in anchorElements) {
        final href = anchor.attributes['href']; // Extract href attribute

        if (href != null && href.isNotEmpty && !href.startsWith('#')) {
          // Resolve relative URLs and filter
          if (_visitedUrls.isNotEmpty) {
            final resolvedUrl =
                Uri.parse(
                  _visitedUrls.last,
                ).resolveUri(Uri.parse(href)).toString();

            if (_currentOrigin != null &&
                resolvedUrl.startsWith(_currentOrigin!) &&
                !_visitedUrls.contains(resolvedUrl) &&
                !_urlsToVisit.contains(resolvedUrl)) {
              setState(() {
                _urlsToVisit.add(resolvedUrl); // Add to queue
              });
              developer.log('Added to queue: $resolvedUrl');
            } else {
              // developer.log('Ignoring URL: $resolvedUrl');
            }
          }
        }
      }

      setState(() {
        _urlsToVisitCount = _urlsToVisit.length;
      });

      // Capture screenshot
      if (_screenshotsDirectory != null) {
        try {
          final Uint8List? bytes = await _controller.takeScreenshot();
          if (bytes != null) {
            String fileName;
            final pageTitle =
                await _controller.evaluateJavascript(source: 'document.title')
                    as String?;

            if (pageTitle != null && pageTitle.isNotEmpty) {
              final cleanedTitle =
                  pageTitle.replaceAll(RegExp(r'[^ws.-]'), '').trim();
              fileName =
                  '${cleanedTitle.isEmpty ? "untitled" : cleanedTitle}.png';
            } else {
              final currentUrl = _visitedUrls.last;
              final urlPath = Uri.parse(currentUrl).path;
              final cleanedPath =
                  urlPath.replaceAll(RegExp(r'[\/]'), '_').trim();
              fileName =
                  '${(cleanedPath.isEmpty || cleanedPath == "_") ? "homepage" : cleanedPath}.png';
            }

            int counter = 1;
            String finalFileName = fileName;
            while (await File(
              '$_screenshotsDirectory/$finalFileName',
            ).exists()) {
              final baseName = fileName.substring(0, fileName.lastIndexOf('.'));
              final extension = fileName.substring(fileName.lastIndexOf('.'));
              finalFileName = '${baseName}_$counter$extension';
              counter++;
            }
            final filePath = '$_screenshotsDirectory/$finalFileName';

            final file = File(filePath);
            await file.writeAsBytes(bytes);

            developer.log('Screenshot saved to: $filePath');
          } else {
            developer.log('Failed to capture screenshot: bytes are null');
          }
        } catch (e) {
          developer.log('Error capturing or saving screenshot: $e');
        }
      } else {
        developer.log('Screenshots directory not initialized.');
      }
    } catch (e) {
      developer.log('Error during link extraction or screenshot: $e');
    }

    // Continue to the next URL in the queue
    _processNextUrl();
  }

  @override
  void dispose() {
    _urlController.dispose(); // Dispose the controller
    super.dispose();
  }
}
