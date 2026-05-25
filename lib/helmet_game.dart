import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SimpleFullInAppWebViewPage extends StatefulWidget {
  const SimpleFullInAppWebViewPage({super.key});

  @override
  State<SimpleFullInAppWebViewPage> createState() =>
      _SimpleFullInAppWebViewPageState();
}

class _SimpleFullInAppWebViewPageState
    extends State<SimpleFullInAppWebViewPage> {
  InAppWebViewController? _webViewController;
  double _progress = 0.0;
  String _title = '';
  bool _canGoBack = false;
  bool _canGoForward = false;

  final String _initialUrl = 'https://legion-cards-of-rome.netlify.app/';

  // Базовые настройки webview
  final InAppWebViewSettings _settings = InAppWebViewSettings(
    // Общие
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
    useOnLoadResource: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,

    // Жесты/скролл
    supportZoom: true,
    builtInZoomControls: true,
    displayZoomControls: false,
    verticalScrollBarEnabled: true,
    horizontalScrollBarEnabled: false,

    // Куки и хранение данных
    clearCache: false,
    incognito: false,
    cacheEnabled: true,
    sharedCookiesEnabled: true,
    thirdPartyCookiesEnabled: true,

    // JS диалоги
    javaScriptCanOpenWindowsAutomatically: true,

    // Защита
    useOnDownloadStart: true,
  );

  @override
  void initState() {
    super.initState();
    // Для Android WebView инициализация (рекомендуется)
    if (Platform.isAndroid) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(

        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
                initialSettings: _settings,

                // Колбэки жизненного цикла
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                },
                onLoadStart: (controller, url) {
                  setState(() {
                    _title = 'Loading...';
                  });
                },
                onLoadStop: (controller, url) async {
                  _updateNavState();
                  final t = await controller.getTitle();
                  setState(() {
                    _title = t ?? '';
                  });
                },
                onReceivedError: (controller, request, error) {
                  debugPrint('WebView error: $error');
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    _progress = progress / 100.0;
                  });
                },

                // Перехват URL (например, для телефонов/mailto/кастомных схем)
                shouldOverrideUrlLoading: (controller, action) async {
                  final uri = action.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final scheme = uri.scheme.toLowerCase();

                  // Позволяем обычные http/https
                  if (scheme == 'http' || scheme == 'https') {
                    return NavigationActionPolicy.ALLOW;
                  }

                  // Пример: блокируем/обрабатываем все нестандартные схемы
                  debugPrint('Intercepted scheme: $scheme, url: $uri');

                  // Здесь можно открыть через url_launcher, если надо.
                  // launchUrl(uri, mode: LaunchMode.externalApplication);

                  return NavigationActionPolicy.CANCEL;
                },

                // Загрузка ресурсов (если нужно логировать)
                onLoadResource: (controller, resource) {
                  // debugPrint('Resource: ${resource.url}');
                },

                // Открытие новых окон (target="_blank")
                onCreateWindow: (controller, createWindowAction) async {
                  // Простой вариант — открывать в этом же webview:
                  final url = createWindowAction.request.url;
                  if (url != null) {
                    controller.loadUrl(urlRequest: URLRequest(url: url));
                  }
                  return true;
                },

                // JS → Flutter через console.log / console.error
                onConsoleMessage: (controller, consoleMessage) {
                  debugPrint(
                      'JS console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
                },

                // Загрузка файлов (Android, если надо)
                onDownloadStartRequest: (controller, downloadStartRequest) {
                  debugPrint('Download requested: ${downloadStartRequest.url}');
                  // Тут можно вызвать свой загрузчик или url_launcher.
                },
              ),
            ),


          ],
        ),
      ),
    );
  }

  Future<void> _updateNavState() async {
    if (_webViewController == null) return;
    final canBack = await _webViewController!.canGoBack();
    final canFwd = await _webViewController!.canGoForward();
    setState(() {
      _canGoBack = canBack;
      _canGoForward = canFwd;
    });
  }
}