import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class WebViewManager {
  InAppWebViewController? _controller;
  final Function(String)? onLoadStopCallback;
  final Logger _logger;

  WebViewManager({required Logger logger, this.onLoadStopCallback})
    : _logger = logger;

  Widget buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri("about:blank")),
      initialSettings: InAppWebViewSettings(
        isInspectable: true, // Useful for debugging
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        _setupSessionManagement();
      },
      onLoadStop: (controller, url) async {
        if (onLoadStopCallback != null && url != null) {
          onLoadStopCallback!(url.toString());

          // Read and inject simulation tools script
          String simulationToolsScript = await _loadSimulationToolsScript();
          if (simulationToolsScript.isNotEmpty) {
            try {
              _logger.i("Simulation tools script injected successfully.");
              await _controller?.evaluateJavascript(
                source: simulationToolsScript,
              );
            } catch (e, st) {
              _logger.e(
                "Error injecting simulation tools script:",
                error: e,
                stackTrace: st,
              );
            }
          }
        }
      },
      onReceivedError: (controller, request, error) {
        _logger.e('Error loading ${request.url}: ${error.description}');
      },
    );
  }

  Future<void> loadUrl(String url) async {
    if (_controller != null) {
      await _controller!.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    }
  }

  Future<String?> getHtmlContent() async {
    if (_controller != null) {
      return await _controller!.getHtml();
    }
    return null;
  }

  Future<dynamic> runJavaScript(String script) async {
    if (_controller != null) {
      return await _controller!.evaluateJavascript(source: script);
    }
    return null;
  }

  Future<Uint8List?> takeScreenshot() async {
    _logger.d("Attempting to take screenshot...");
    if (_controller != null) {
      final screenshot = await _controller!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.PNG,
        ),
      );
      if (screenshot == null) {
        _logger.w("Screenshot capture returned null.");
      }
      if (screenshot != null) {
        _logger.d("Screenshot taken successfully.");
        try {
          final directory = await getApplicationDocumentsDirectory();
          final screenshotsDir = Directory(
            p.join(directory.path, 'screenshots'),
          );
          if (!await screenshotsDir.exists()) {
            await screenshotsDir.create(recursive: true);
          }
          final filePath = p.join(
            screenshotsDir.path,
            'screenshot_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          await File(filePath).writeAsBytes(screenshot);
          _logger.i("Screenshot saved to: $filePath");
        } catch (e, st) {
          _logger.e("Error saving screenshot:", error: e, stackTrace: st);
        }
      }
      return screenshot;
    }
    return null;
  }

  Future<void> stopLoading() async {
    await _controller?.stopLoading();
  }

  Future<void> _setupSessionManagement() async {
    // Initial setup for CookieManager and WebStorageManager
    try {
      // final cookieManager = CookieManager.instance(); // Removed as it's unused
      // final webStorageManager = WebStorageManager.instance(); // Removed as it's unused

      // Example: Delete all cookies
      // await cookieManager.deleteAllCookies();

      // Example: Delete all web storage data
      // await webStorageManager.deleteAllData();

      _logger.i("InAppWebView session management initialized.");
    } catch (e, st) {
      _logger.e(
        "Error setting up session management:",
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<String> _loadSimulationToolsScript() async {
    try {
      return await rootBundle.loadString('assets/simulation_tools.js');
    } catch (e) {
      _logger.e('Error loading assets/simulation_tools.js:', error: e);
      return ''; // Handle the error as appropriate
    }
  }

  // You might want to add dispose method to clean up resources
  void dispose() {
    _controller = null;
  }
}
