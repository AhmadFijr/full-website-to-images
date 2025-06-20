import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Screenshot App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
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
  late final WebViewController _controller;
  String? _currentOrigin; // لتخزين أصل (Origin) الموقع المستهدف
  final Set<String> _visitedUrls = {}; // مجموعة لتخزين عناوين URL التي تم زيارتها
  final List<String> _urlsToVisit = []; // قائمة لعناوين URL التي يجب زيارتها

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
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
            _extractLinksAndContinue(); // استدعاء دالة استخلاص الروابط
          },
          onWebResourceError: (WebResourceError error) {
            // معالجة أخطاء تحميل الموارد (مثل 404)
            print('Web resource error: ${error.description} on ${error.url}');
            _processNextUrl(); // المتابعة إلى الـ URL التالي حتى لو حدث خطأ
          },
          onNavigationRequest: (NavigationRequest request) {
            // يمكنك التحكم هنا في ما إذا كان WebView يسمح بالتنقل إلى URL معين
            // حاليًا نسمح بجميع التنقلات
            return NavigationDecision.navigate;
          },
        ),
      );
  }



  void _loadUrl() {
    final String url = _urlController.text.trim(); // استخدام trim لإزالة المسافات البيضاء
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        _currentOrigin = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}'; // استخلاص الأصل
        _urlsToVisit.clear(); // مسح القوائم في حالة بدء عملية جديدة
        _visitedUrls.clear();
        _urlsToVisit.add(url); // إضافة الـ URL الأولي إلى قائمة الزيارة
        _processNextUrl(); // بدء معالجة عناوين URL
      } else {
        // يمكن إضافة معالجة للأخطاء هنا إذا كان الـ URL غير صالح
        print('Invalid URL: $url');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
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
                ElevatedButton(
                  onPressed: _loadUrl,
                  child: const Text('ابدأ'),
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
        print('Visiting: $nextUrl'); // طباعة الـ URL الذي يتم زيارته

        // تحميل الـ URL في WebView
        _controller.loadRequest(Uri.parse(nextUrl));

        // **هنا سيتم إضافة منطق انتظار تحميل الصفحة واستخلاص الروابط والتقاط لقطة الشاشة لاحقًا**
        // حاليًا، نحن فقط نقوم بتحميل الصفحة

      } else {
        // إذا كان الـ URL قد تم زيارته، ننتقل إلى معالجة التالي
        _processNextUrl();
      }
    } else {
      print('Finished crawling.'); // تم الانتهاء من الزحف
      // **هنا يمكن إضافة منطق لإعلام المستخدم بالانتهاء**
    }
  }

  void _extractLinksAndContinue() async {
    print('Page finished loading. Extracting links...');
    // استخلاص كود HTML للصفحة
    final html = await _controller.runJavaScriptReturningResult(
        'document.documentElement.outerHTML') as String;
    print('HTML fetched. Length: ${html.length}');

    // **هنا يمكنك إضافة منطق لتحليل HTML واستخلاص الروابط**
    // يمكنك استخدام مكتبة مثل `html` لتحليل الـ HTML.

    // **بعد استخلاص الروابط، قم بإضافتها إلى _urlsToVisit وتأكد من أنها ضمن _currentOrigin ولم تتم زيارتها من قبل**

    // بعد معالجة الصفحة واستخلاص الروابط، انتقل إلى الـ URL التالي في قائمة الانتظار
    _processNextUrl();
  }

 final TextEditingController _urlController = TextEditingController();
}

