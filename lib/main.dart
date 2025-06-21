import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import 'package:myapp/webview_manager.dart'; // Import WebViewManager
import 'package:myapp/crawler.dart';


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
      home: DefaultTabController(
        length: 1, // Number of tabs
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Web Crawler Tool'),
            bottom: const TabBar(
              tabs: <Widget>[
                const Tab(text: 'Crawler'),
              ],
            ),
          ),
          body: const TabBarView(
            children: <Widget>[
              CrawlerTab(), // Content for the Crawler tab
            ],
          ),
        ),
      ),
    );
  }
}

class CrawlerTab extends StatefulWidget {
  const CrawlerTab({Key? key}) : super(key: key);

  @override
  CrawlerTabState createState() => CrawlerTabState();
}

class CrawlerTabState extends State<CrawlerTab> {
  late TextEditingController _urlController;
  late TextEditingController _maxDepthController;
  int _pagesVisitedCount = 0;
  int _urlsToVisitCount = 0;
  bool _isCrawling = false;
  String? _screenshotsDirectoryPath;
  late Crawler _crawler;
  late WebViewManager _webViewManager; // Declare WebViewManager
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: "example.com");
    _maxDepthController = TextEditingController(text: "1");
    _webViewManager = WebViewManager(logger: _logger); // Initialize WebViewManager
    _initScreenshotsDirectory();
  }

  Future<void> _initScreenshotsDirectory() async {
    try {
      final directory = await path_provider.getApplicationDocumentsDirectory();
      final screenshotsDirectory = Directory('${directory.path}/screenshots');

      if (!await screenshotsDirectory.exists()) {
        await screenshotsDirectory.create(recursive: true);
      }
      _screenshotsDirectoryPath = screenshotsDirectory.path;
      _logger.d('Screenshots will be saved in: $_screenshotsDirectoryPath');
    } catch (e) {
      _logger.e('Error initializing screenshots directory: $e');
    }
  }

  Future<void> _openScreenshotsFolder() async {
    if (_screenshotsDirectoryPath != null) {
      final Uri uri = Uri.directory(_screenshotsDirectoryPath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _logger.e('Could not launch folder: $_screenshotsDirectoryPath');
      }
    }
  }

  Future<void> startCrawl() async {
    if (_isCrawling) return;

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL.')),
      );
      return;
    }

    setState(() {
      _isCrawling = true;
      _pagesVisitedCount = 0;
      _urlsToVisitCount = 0;
    });

    try {
      final int maxDepth = int.tryParse(_maxDepthController.text) ?? 1;
      // Initialize crawler here before starting crawl
      _crawler = Crawler(
        logger: _logger,
        maxDepth: maxDepth,
        crawlPathLookback: 5, // Example value, adjust as needed
        webViewManager: _webViewManager, // Pass the initialized WebViewManager
        onVisitedCountChanged: (count) { // Correct parameter name
          if (mounted) {
            setState(() => _pagesVisitedCount = count);
          }
        },
        onToVisitCountChanged: (count) { // Correct parameter name
          if (mounted) {
            setState(() => _urlsToVisitCount = count);
          }
        },
        onCrawlCompleted: () {
           if (mounted) {
            setState(() {
              _isCrawling = false;
            });
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('Crawl Potentially Complete'),
                  content: const Text('The initial crawl process has finished.'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _openScreenshotsFolder();
                      },
                      child: const Text('OK'),
                    ),
                  ],
                );
              },
            );
          }
        },
         onPageStartedLoading: (url) {
          _logger.i('Page started loading: $url');
          // You can add UI updates here if needed
        },
        onScreenshotCaptured: (path) {
          _logger.i('Screenshot captured and saved to: $path');
          // You can add UI updates here if needed,
          // e.g., add the path to a list to display screenshots
        },
      );

      await _crawler.startCrawl(url);

    } catch (e, st) {
      _logger.e('Error during crawl: $e\n$st');
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

  Future<void> _takeScreenshot() async {
    _logger.d("Attempting to take screenshot...");
    try {
      // Add a small delay to allow the WebView to render
      await Future.delayed(const Duration(milliseconds: 500));

      final screenshot = await _webViewManager.takeScreenshot();

      if (screenshot != null) {
        _logger.d("Screenshot captured, ${screenshot.length} bytes.");
        // Here you would add the logic to save the screenshot,
        // similar to what was in the TestTab.
        // For now, we'll just log that it was captured.
        _logger.i("Screenshot captured successfully.");
         // Implement save logic similar to _saveScreenshot in crawler.dart if needed
      } else {
        _logger.w("takeScreenshot returned null.");
      }
    } catch (e, st) {
      _logger.e("Error taking screenshot: $e", error: e, stackTrace: st);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Column(
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
              SizedBox(
                width: 100, // Fixed width for depth input
                child: TextField(
                  controller: _maxDepthController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Depth',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isCrawling ? null : startCrawl,
                child: const Text('Start Crawl'),
              ),
               const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _takeScreenshot,
                child: const Text('Take Screenshot'),
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
          child: _webViewManager.buildWebView(), // Use WebViewManager's buildWebView
        ),
      ],
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _maxDepthController.dispose();
    // Consider adding dispose for _webViewManager if it has one
    super.dispose();
  }
}
