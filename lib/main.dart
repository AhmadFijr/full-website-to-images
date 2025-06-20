import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;
import 'dart:developer' as developer;

void main() {

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) { // Overrides build method
    return MaterialApp( // Corrected class name
      title: 'Web Screenshot App', // Corrected Text usage
      theme: ThemeData(
        primarySwatch: Colors.blue, // Corrected Colors usage
      ),
      home: const MyHomePage(title: 'Web Screenshot Tool'),
    );
  } // Corrected build method
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  
  final String title;
  
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}
  
class _MyHomePageState extends State<MyHomePage> {
  String? _currentOrigin; // لتخزين أصل (Origin) الموقع المستهدف
  final Set<String> _visitedUrls = {}; // مجموعة لتخزين عناوين URL التي تم زيارتها
  final List<String> _urlsToVisit = []; // قائمة لعناوين URL التي يجب زيارتها
  late final WebViewController _controller;
  late final TextEditingController _urlController; // Corrected TextEditingController usage

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000)) // Corrected Color usage
      ..setNavigationDelegate( // إضافة NavigationDelegate للتحكم في التنقل
        NavigationDelegate(
          onProgress: (int progress) {
            // يمكنك هنا إضافة مؤشر للتقدم
          },
          onPageStarted: (String url) {
            // يمكنك هنا إضافة منطق عند بدء تحميل الصفحة
          },
          onPageFinished: (String url) {
            // هذا هو المكان الذي سنقوم فيه باستخلاص الروابط ومتابعة الزحف
            _extractLinksAndContinue();
          },
          onWebResourceError: (WebResourceError error) {
            // معالجة أخطاء تحميل الموارد (مثل 404)
            developer.log('Web resource error: ${error.description} on ${error.url}');
            _processNextUrl(); // Corrected method call
 },
          onNavigationRequest: (NavigationRequest request) {
            // يمكنك التحكم هنا في ما إذا كان WebView يسمح بالتنقل إلى URL معين
            // حاليا نسمح بجميع التنقلات
            return NavigationDecision.navigate;
          },
        ),
      );
    _urlController = TextEditingController(); // Initialize _urlController here
  }

  void _loadUrl() {
    final String url = _urlController.text.trim(); // استخدام trim لإزالة المسافات البيضاء
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        _currentOrigin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'; // استخلاص الأصل
        _urlsToVisit.clear();
        _visitedUrls.clear();
        _urlsToVisit.add(url); // إضافة الـ URL الأولي إلى قائمة الزيارة
        _processNextUrl(); // بدء معالجة عناوين URL
      } else {
        // Corrected log message
        developer.log('Invalid URL: $url');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title), // Corrected Text usage
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row( // Corrected Row usage
              children: <Widget>[
                Expanded(
                  child: TextField(// Corrected class name and Expanded usage
                    controller: _urlController,
                    decoration: const InputDecoration(
                      hintText: 'أدخل عنوان URL للموقع',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8), // Corrected SizedBox usage
                ElevatedButton( // Corrected ElevatedButton usage
                  onPressed: _loadUrl,
                  child: const Text('ابدأ'), // Corrected Text usage
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
  
  void _processNextUrl() {
    if (_urlsToVisit.isNotEmpty) {
      final nextUrl = _urlsToVisit.removeAt(0); // جلب أول URL من القائمة
      if (!_visitedUrls.contains(nextUrl)) { // التحقق مما إذا كان قد تم زيارته بالفعل
        _visitedUrls.add(nextUrl); // إضافته إلى قائمة التي تم زيارتها
        developer.log('Visiting: $nextUrl');
        // ignore: unused_local_variable
        // تحميل الـ URL في WebView
        _controller.loadRequest(Uri.parse(nextUrl)); // Ensure this is the correct method call

        // **هنا سيتم إضافة منطق انتظار تحميل الصفحة واستخلاص الروابط والتقاط لقطة الشاشة لاحقًا**
        // حاليًا، نحن فقط نقوم بتحميل الصفحة

      } else {
        // إذا كان الـ URL قد تم زيارته، ننتقل إلى معالجة التالي
        _processNextUrl(); // Corrected method call
      }
    } else {
      developer.log('Finished crawling.'); // تم الانتهاء من الزحف
    }
  }
  void _extractLinksAndContinue() async {
    developer.log('Page finished loading. Extracting links...');

    // Extract HTML content
    final htmlString = await _controller.runJavaScriptReturningResult(
      'document.documentElement.outerHTML') as String; // Ensure this is the correct method call
    developer.log('HTML fetched. Length: ${htmlString.length}');

    // Parse HTML and extract links
    final document = parse(htmlString);
    final Iterable<dom.Element> anchorElements = document.querySelectorAll('a');

    developer.log('Found ${anchorElements.length} anchor elements.');

    for (final anchor in anchorElements) {
      final href = anchor.attributes['href']; // Extract href attribute

      if (href != null && href.isNotEmpty && !href.startsWith('#')) {
        // Resolve relative URLs and filter
        if (_visitedUrls.isNotEmpty) {
            final resolvedUrl = Uri.parse(_visitedUrls.last).resolveUri(Uri.parse(href)).toString();

            if (_currentOrigin != null && resolvedUrl.startsWith(_currentOrigin!) && !_visitedUrls.contains(resolvedUrl) && !_urlsToVisit.contains(resolvedUrl)) {
              _urlsToVisit.add(resolvedUrl); // Add to queue
              developer.log('Added to queue: $resolvedUrl');
            } else {
                 // developer.log('Ignoring URL: $resolvedUrl');
            }
        }
      }
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
