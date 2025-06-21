import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:logger/logger.dart';


class TestTab extends StatefulWidget {


  const TestTab({Key? key}) : super(key: key);

  @override
  TestTabState createState() => TestTabState();
}

class TestTabState extends State<TestTab> {
  final TextEditingController _urlController = TextEditingController();
  InAppWebViewController? _webViewController;
  final Logger _logger = Logger();
  String? _screenshotDirectoryPath;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Enter URL',
            ),
          ),
          const SizedBox(height: 16.0),
          ElevatedButton(
            onPressed: () async {
              if (_webViewController != null) {
                    await _takeScreenshot(); 
                } 
                else {
                _logger.d('WebView controller is not available.');
              }
            },
            child: const Text('Take Screenshot'),
          ),
          const SizedBox(height: 16.0),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri("about:blank")),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _takeScreenshot() async {
    if (_webViewController != null) {
 _logger.d("Attempting to take screenshot...");
      await Future.delayed(Duration(milliseconds: 500)); // Add a small delay
      final screenshot = await _webViewController!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(compressFormat: CompressFormat.PNG),
      );
      if (screenshot != null) {
 _logger.d("Screenshot taken successfully. Attempting to save...");
        try {

          if (_screenshotDirectoryPath == null) {
            final directory = await getApplicationDocumentsDirectory();
            _screenshotDirectoryPath = p.join(directory.path, 'screenshots');
            final screenshotsDir = Directory(_screenshotDirectoryPath!);
             if (!await screenshotsDir.exists()) {
              await screenshotsDir.create(recursive: true);
            }
 _logger.d('Screenshot directory initialized: $_screenshotDirectoryPath');
          }
           final filePath = p.join(_screenshotDirectoryPath!, 'test_screenshot_${DateTime.now().millisecondsSinceEpoch}.png');
          await File(filePath).writeAsBytes(screenshot);
 _logger.d("Screenshot saved to: $filePath");
        } catch (e) {
 _logger.e("Error saving screenshot: $e");
 }
      } else if (screenshot == null) {
 _logger.w("Screenshot capture returned null.");
      } else if (screenshot.isEmpty) {
 _logger.w("Screenshot capture returned empty byte data.");
      } else {
 _logger.d("Screenshot capture failed.");
      }
    }
  }
}