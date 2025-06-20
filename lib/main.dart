import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'dart:developer' as developer;
import 'package:myapp/crawler.dart';
import 'package:myapp/webview_manager.dart'; // Import the abstract class

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Crawler App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MyHomePage(title: 'Web Crawler Tool'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

// Adapter class to connect InAppWebViewController with our abstract WebViewManager
class InAppWebViewManager implements WebViewManager {
  final InAppWebViewController _controller;

  InAppWebViewManager(this._controller);

  @override
  Future<String?> getHtmlContent() {
    return _controller.getHtml();
  }

  @override
  Future<void> loadUrl(String url) {
    return _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  @override
  Future<dynamic> runJavaScript(String script) {
    return _controller.evaluateJavascript(source: script);
  }

  @override
  Future<void> stopLoading() async {
    await _controller.stopLoading();
  }

  @override
  Future<Uint8List?> takeScreenshot() {
    return _controller.takeScreenshot();
  }

  Future<void> waitForNetworkIdle({Duration? timeout}) async {
    await Future.delayed(timeout ?? const Duration(milliseconds: 500));
  }

  // --- FIX: Implementations to satisfy the abstract class contract ---

  @override
  Widget buildWebView({Function(String p1)? onLoadStop}) {
    return Container();
  }

  @override
  void dispose() {
    // No operation needed.
  }

  // FIX: Corrected the getter's return type to match the abstract class.
  // The type is now Function(String)?, which means a nullable function
  // that takes a String as an argument.
  @override
  Function(String)? get onLoadStopCallback => null;
}

class _MyHomePageState extends State<MyHomePage> {
  late TextEditingController _urlController;
  late TextEditingController _maxDepthController;
  int _pagesVisitedCount = 0;
  int _urlsToVisitCount = 0;
  final List<String> _screenshotPaths = [];
  bool _isCrawling = false;

  late Crawler _crawler;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: "flutter.dev");
    _maxDepthController = TextEditingController(text: "1");
    _initScreenshotsDirectory();
  }

  Future<void> _initScreenshotsDirectory() async {
    try {
      final directory = await path_provider.getApplicationDocumentsDirectory();
      final screenshotsDirectory = Directory('${directory.path}/screenshots');

      if (!await screenshotsDirectory.exists()) {
        await screenshotsDirectory.create(recursive: true);
      }
      developer.log(
        'Screenshots will be saved in: ${screenshotsDirectory.path}',
      );
    } catch (e) {
      developer.log('Error initializing screenshots directory: $e');
    }
  }

  Future<void> startCrawl() async {
    if (_isCrawling) return;

    _screenshotPaths.clear();
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a URL.')));
      return;
    }

    setState(() {
      _isCrawling = true;
      _pagesVisitedCount = 0;
      _urlsToVisitCount = 0;
    });

    try {
      await _crawler.startCrawl(url);
      if (mounted) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Crawl Potentially Complete'),
              content: const Text('The initial crawl process has finished.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      }
    } catch (e, st) {
      developer.log('Error during crawl: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during crawl: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCrawling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'Enter website URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 0,
                  child: SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _maxDepthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Depth',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isCrawling ? null : startCrawl,
                  child: const Text('Start Crawl'),
                ),
              ],
            ),
          ),
          Visibility(
            visible: _isCrawling,
            child: const LinearProgressIndicator(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('Visited: $_pagesVisitedCount'),
                Text('To Visit: $_urlsToVisitCount'),
              ],
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri("about:blank")),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
              onWebViewCreated: (controller) {
                final logger = Logger();
                final webViewManager = InAppWebViewManager(controller);

                _crawler = Crawler(
                  logger: logger,
                  webViewManager: webViewManager,
                  maxDepth: int.tryParse(_maxDepthController.text) ?? -1,
                  crawlPathLookback: 10,
                  onVisitedCountChanged: (count) {
                    if (mounted) setState(() => _pagesVisitedCount = count);
                  },
                  onToVisitCountChanged: (count) {
                    if (mounted) setState(() => _urlsToVisitCount = count);
                  },
                  onCrawlCompleted: () {
                    if (mounted) {
                      setState(() => _isCrawling = false);
                    }
                  },
                  onScreenshotCaptured: (path) {
                    if (mounted) {
                      setState(() {
                        _screenshotPaths.add(path);
                      });
                    }
                  },
                );
              },
              onLoadStop: (controller, url) {
                if (url != null && _isCrawling) {
                  _crawler.onPageLoaded(url.toString(), 200);
                }
              },
              onReceivedError: (controller, request, error) {
                developer.log(
                  'Web resource error: ${error.description} on ${request.url}',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _maxDepthController.dispose();
    super.dispose();
  }
}
