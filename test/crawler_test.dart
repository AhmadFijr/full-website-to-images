// test/crawler_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:myapp/crawler.dart';
import 'package:mockito/annotations.dart';
import 'package:logger/logger.dart';
import 'package:mockito/mockito.dart';
import 'package:myapp/models/url_entry.dart';
import 'package:myapp/webview_manager.dart';
@GenerateNiceMocks([MockSpec<WebViewManager>(), MockSpec<Logger>()])
import 'crawler_test.mocks.dart';

void main() {
  // الكود هنا كما هو، وهو صحيح
  late MockWebViewManager mockWebViewManager;
  late MockLogger mockLogger;

  setUp(() {
    // Create new mock objects for each test to ensure isolation
    mockWebViewManager = MockWebViewManager();
    mockLogger = MockLogger();
    // Stub Logger methods to avoid errors if Crawler logs during initialization
  });

  // Test group for the Crawler class
  group('Crawler Initialization and Basic Start', () {
    test('should skip already visited URLs', () async {
      final crawler = Crawler(
        webViewManager: mockWebViewManager,
        logger: mockLogger,
        maxDepth: 1,
        crawlPathLookback: 5,
      );
      const testUrl = "https://google.com/";
      final visitedEntry = UrlEntry(url: testUrl, depth: 0, crawlPath: []);

      crawler.addUrlToVisitedSetForTest(visitedEntry);
      crawler.addUrlToVisitQueueForTest(visitedEntry);

      crawler.toVisitCount = 1;
      await crawler.processNextUrlForTest();

      // Verify that loadUrl was NOT called on the mock WebViewManager
      verifyNever(mockWebViewManager.loadUrl(argThat(isA<String>())));

      // Verify that visitedCount and toVisitCount are NOT changed
      expect(crawler.visitedCount, 0);
      expect(crawler.toVisitCount, 0);

      // Verify logger output indicating the URL was skipped
      verify(mockLogger.i("Skipping already visited URL: $testUrl")).called(1);
    });
  });
}