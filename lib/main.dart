import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:appsflyer_sdk/appsflyer_sdk.dart' as appsflyer_core;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
    MethodChannel,
    SystemChrome,
    SystemUiOverlayStyle,
    MethodCall,
    VoidCallback;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz_zone;

import 'helmet_game.dart';
import 'helmet_push.dart';
import 'loader_harena.dart';

// ============================================================================
// Константы
// ============================================================================

const String romeLoadedOnceKey = 'loaded_once';
const String romeStatEndpoint = 'https://data.legionrome.top/stat';
const String romeCachedFcmKey = 'cached_fcm';
const String romeCachedDeepKey = 'cached_deep_push_uri';

const Set<String> romeBankSchemes = {
  'td',
  'rbc',
  'cibc',
  'scotiabank',
  'bmo',
  'bmodigitalbanking',
  'desjardins',
  'tangerine',
  'nationalbank',
  'simplii',
  'dominotoronto',
};

const Set<String> romeBankDomains = {
  'td.com',
  'tdcanadatrust.com',
  'easyweb.td.com',
  'rbc.com',
  'royalbank.com',
  'online.royalbank.com',
  'cibc.com',
  'cibc.ca',
  'online.cibc.com',
  'scotiabank.com',
  'scotiaonline.scotiabank.com',
  'bmo.com',
  'bmo.ca',
  'bmodigitalbanking.com',
  'desjardins.com',
  'tangerine.ca',
  'nbc.ca',
  'nationalbank.ca',
  'simplii.com',
  'simplii.ca',
  'dominotoronto.com',
  'dominobank.com',
};

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class RomeLoggerService {
  static final RomeLoggerService RomeSharedInstance =
  RomeLoggerService._RomeInternalConstructor();

  RomeLoggerService._RomeInternalConstructor();

  factory RomeLoggerService() => RomeSharedInstance;

  final Connectivity RomeConnectivity = Connectivity();

  void RomeLogInfo(Object message) => print('[I] $message');
  void RomeLogWarn(Object message) => print('[W] $message');
  void RomeLogError(Object message) => print('[E] $message');
}

class RomeNetworkService {
  final RomeLoggerService RomeLogger = RomeLoggerService();

  Future<void> RomePostJson(
      String url,
      Map<String, dynamic> data,
      ) async {
    try {
      await http.post(
        Uri.parse(url),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
    } catch (error) {
      RomeLogger.RomeLogError('postJson error: $error');
    }
  }
}

// ============================================================================
// Утилита: одновременное сохранение JSON в localStorage и SharedPreferences
// ============================================================================

Future<void> RomeSaveJsonToLocalStorageAndPrefs({
  required InAppWebViewController? controller,
  required String key,
  required Map<String, dynamic> data,
}) async {
  final String jsonString = jsonEncode(data);

  if (controller != null) {
    try {
      await controller.evaluateJavascript(
        source: "localStorage.setItem('$key', JSON.stringify($jsonString));",
      );
    } catch (e, st) {
      RomeLoggerService().RomeLogError(
          'RomeSaveJsonToLocalStorageAndPrefs localStorage error: $e\n$st');
    }
  }

  try {
    final SharedPreferences romePrefs = await SharedPreferences.getInstance();
    await romePrefs.setString(key, jsonString);
  } catch (e, st) {
    RomeLoggerService().RomeLogError(
        'RomeSaveJsonToLocalStorageAndPrefs prefs error: $e\n$st');
  }
}

// ============================================================================
// Профиль устройства
// ============================================================================

class RomeDeviceProfile {
  String? RomeDeviceId;
  String? RomeSessionId = '';
  String? RomePlatformName;
  String? RomeOsVersion;
  String? RomeAppVersion;
  String? RomeLanguageCode;
  String? RomeTimezoneName;
  bool RomePushEnabled = false;

  bool RomeSafeAreaEnabled = false;
  String? RomeSafeAreaColor;

  bool romeSafeCasher = false;

  String? RomeBaseUserAgent;

  Map<String, dynamic>? RomeLastPushData;

  Map<String, dynamic>? RomeSavels;

  Future<void> RomeInitialize() async {
    final DeviceInfoPlugin romeDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo romeAndroidInfo =
      await romeDeviceInfoPlugin.androidInfo;
      RomeDeviceId = romeAndroidInfo.id;
      RomePlatformName = 'android';
      RomeOsVersion = romeAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo romeIosInfo = await romeDeviceInfoPlugin.iosInfo;
      RomeDeviceId = romeIosInfo.identifierForVendor;
      RomePlatformName = 'ios';
      RomeOsVersion = romeIosInfo.systemVersion;
    }

    final PackageInfo romePackageInfo = await PackageInfo.fromPlatform();
    RomeAppVersion = romePackageInfo.version;
    RomeLanguageCode = Platform.localeName.split('_').first;
    RomeTimezoneName = tz_zone.local.name;
    RomeSessionId = 'test-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> RomeToMap({String? fcmToken}) => <String, dynamic>{
    'fcm_token': fcmToken ?? 'missing_token',
    'device_id': RomeDeviceId ?? 'missing_id',
    'app_name': 'legionrome',
    'instance_id': RomeSessionId ?? 'missing_session',
    'platform': RomePlatformName ?? 'missing_system',
    'os_version': RomeOsVersion ?? 'missing_build',
    'app_version': "1.4.1" ?? 'missing_app',
    'language': RomeLanguageCode ?? 'en',
    'timezone': RomeTimezoneName ?? 'UTC',
    'push_enabled': RomePushEnabled,
    'safe_area_native': RomeSafeAreaEnabled,
    'useragent': RomeBaseUserAgent ?? 'unknown_useragent',
    'savels': RomeSavels ?? <String, dynamic>{},
    'fpscashier': romeSafeCasher,
  };
}

// ============================================================================
// AppsFlyer Spy
// ============================================================================

class RomeAnalyticsSpyService {
  appsflyer_core.AppsFlyerOptions? RomeAppsFlyerOptions;
  appsflyer_core.AppsflyerSdk? RomeAppsFlyerSdk;

  String RomeAppsFlyerUid = '';
  String RomeAppsFlyerData = '';

  Map<String, dynamic>? RomeAppsFlyerOneLinkData;

  void RomeStartTracking({VoidCallback? onUpdate}) {
    final appsflyer_core.AppsFlyerOptions romeConfig =
    appsflyer_core.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6771730453',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    RomeAppsFlyerOptions = romeConfig;
    RomeAppsFlyerSdk = appsflyer_core.AppsflyerSdk(romeConfig);

    RomeAppsFlyerSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    RomeAppsFlyerSdk?.startSDK(
      onSuccess: () =>
          RomeLoggerService().RomeLogInfo('RetroCarAnalyticsSpy started'),
      onError: (int code, String msg) => RomeLoggerService()
          .RomeLogError('RetroCarAnalyticsSpy error $code: $msg'),
    );

    RomeAppsFlyerSdk?.onInstallConversionData((dynamic value) {
      RomeAppsFlyerData = value.toString();
      onUpdate?.call();
    });

    RomeAppsFlyerSdk?.getAppsFlyerUID().then((dynamic value) {
      RomeAppsFlyerUid = value.toString();
      onUpdate?.call();
    });
  }

  void RomeSetOneLinkData(Map<String, dynamic> data) {
    RomeAppsFlyerOneLinkData = data;
    RomeLoggerService()
        .RomeLogInfo('RomeAnalyticsSpyService: OneLink data updated: $data');
  }
}

// ============================================================================
// FCM фон
// ============================================================================

@pragma('vm:entry-point')
Future<void> RomeFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  RomeLoggerService().RomeLogInfo('bg-fcm: ${message.messageId}');
  RomeLoggerService().RomeLogInfo('bg-data: ${message.data}');

  final dynamic romeLink = message.data['uri'];
  if (romeLink != null) {
    try {
      final SharedPreferences romePrefs = await SharedPreferences.getInstance();
      await romePrefs.setString(
        romeCachedDeepKey,
        romeLink.toString(),
      );
    } catch (e) {
      RomeLoggerService().RomeLogError('bg-fcm save deep failed: $e');
    }
  }
}

// ============================================================================
// FCM Bridge — токен
// ============================================================================

class RomeFcmBridge {
  final RomeLoggerService RomeLogger = RomeLoggerService();

  static const MethodChannel _romeTokenChannel =
  MethodChannel('com.example.fcm/token');

  String? RomeToken;
  final List<void Function(String)> RomeTokenWaiters =
  <void Function(String)>[];

  String? get RomeFcmToken => RomeToken;

  Timer? _romeRequestTimer;
  int _romeRequestAttempts = 0;
  final int _romeMaxAttempts = 10;

  RomeFcmBridge() {
    _romeTokenChannel.setMethodCallHandler((MethodCall romeCall) async {
      if (romeCall.method == 'setToken') {
        final String romeTokenString = romeCall.arguments as String;
        RomeLogger.RomeLogInfo(
            'RomeFcmBridge: got token from native channel = $romeTokenString');
        if (romeTokenString.isNotEmpty) {
          RomeSetToken(romeTokenString);
        }
      }
    });

    RomeRestoreToken();
    _romeRequestNativeToken();
    _romeStartRequestTimer();
  }

  Future<void> _romeRequestNativeToken() async {
    try {
      RomeLogger.RomeLogInfo('RomeFcmBridge: request native getToken()');
      final String? token =
      await _romeTokenChannel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        RomeLogger.RomeLogInfo(
            'RomeFcmBridge: native getToken() returns $token');
        RomeSetToken(token);
      } else {
        RomeLogger.RomeLogWarn(
            'RomeFcmBridge: native getToken() returned empty');
      }
    } catch (e) {
      RomeLogger.RomeLogWarn('RomeFcmBridge: getToken invoke error: $e');
    }
  }

  void _romeStartRequestTimer() {
    _romeRequestTimer?.cancel();
    _romeRequestAttempts = 0;

    _romeRequestTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      if ((RomeToken ?? '').isNotEmpty) {
        RomeLogger.RomeLogInfo(
            'RomeFcmBridge: token already set, stop request timer');
        t.cancel();
        return;
      }

      if (_romeRequestAttempts >= _romeMaxAttempts) {
        RomeLogger.RomeLogWarn(
            'RomeFcmBridge: max getToken attempts reached, stop timer');
        t.cancel();
        return;
      }

      _romeRequestAttempts++;
      RomeLogger.RomeLogInfo(
          'RomeFcmBridge: retry getToken() attempt #$_romeRequestAttempts');
      await _romeRequestNativeToken();
    });
  }

  Future<void> RomeRestoreToken() async {
    try {
      final SharedPreferences romePrefs = await SharedPreferences.getInstance();
      final String? romeCachedToken =
      romePrefs.getString(romeCachedFcmKey);
      if (romeCachedToken != null && romeCachedToken.isNotEmpty) {
        RomeLogger.RomeLogInfo(
            'RomeFcmBridge: restored cached token = $romeCachedToken');
        RomeSetToken(romeCachedToken, notify: false);
      }
    } catch (e) {
      RomeLogger.RomeLogError('RomeRestoreToken error: $e');
    }
  }

  Future<void> RomePersistToken(String newToken) async {
    try {
      final SharedPreferences romePrefs = await SharedPreferences.getInstance();
      await romePrefs.setString(romeCachedFcmKey, newToken);
    } catch (e) {
      RomeLogger.RomeLogError('RomePersistToken error: $e');
    }
  }

  void RomeSetToken(
      String newToken, {
        bool notify = true,
      }) {
    RomeToken = newToken;
    RomePersistToken(newToken);

    if (notify) {
      for (final void Function(String) romeCallback
      in List<void Function(String)>.from(RomeTokenWaiters)) {
        try {
          romeCallback(newToken);
        } catch (error) {
          RomeLogger.RomeLogWarn('fcm waiter error: $error');
        }
      }
      RomeTokenWaiters.clear();
    }
  }

  Future<void> RomeWaitForToken(
      Function(String token) romeOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((RomeToken ?? '').isNotEmpty) {
        romeOnToken(RomeToken!);
        return;
      }

      RomeTokenWaiters.add(romeOnToken);
    } catch (error) {
      RomeLogger.RomeLogError('RomeWaitForToken error: $error');
    }
  }

  void dispose() {
    _romeRequestTimer?.cancel();
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class RomeHall extends StatefulWidget {
  const RomeHall({Key? key}) : super(key: key);

  @override
  State<RomeHall> createState() => _RomeHallState();
}

class _RomeHallState extends State<RomeHall> {
  final RomeFcmBridge RomeFcmBridgeInstance = RomeFcmBridge();
  bool RomeNavigatedOnce = false;
  Timer? RomeFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    RomeFcmBridgeInstance.RomeWaitForToken((String romeToken) {
      RomeGoToHarbor(romeToken);
    });

    RomeFallbackTimer = Timer(
      const Duration(seconds: 8),
          () => RomeGoToHarbor(''),
    );
  }

  void RomeGoToHarbor(String romeSignal) {
    if (RomeNavigatedOnce) return;
    RomeNavigatedOnce = true;
    RomeFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext context) => RomeHarbor(RomeSignal: romeSignal),
      ),
    );
  }

  @override
  void dispose() {
    RomeFallbackTimer?.cancel();
    RomeFcmBridgeInstance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ArenaScreen(),
        ),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class RomeBosunViewModel {
  final RomeDeviceProfile RomeDeviceProfileInstance;
  final RomeAnalyticsSpyService RomeAnalyticsSpyInstance;

  RomeBosunViewModel({
    required this.RomeDeviceProfileInstance,
    required this.RomeAnalyticsSpyInstance,
  });

  Map<String, dynamic> RomeDeviceMap(String? fcmToken) =>
      RomeDeviceProfileInstance.RomeToMap(fcmToken: fcmToken);

  Map<String, dynamic> RomeAppsFlyerPayload(
      String? token, {
        String? deepLink,
      }) {
    final Map<String, dynamic> onelinkData =
        RomeAnalyticsSpyInstance.RomeAppsFlyerOneLinkData ??
            <String, dynamic>{};

    return <String, dynamic>{
      'content': <String, dynamic>{
        'af_data': RomeAnalyticsSpyInstance.RomeAppsFlyerData,
        'af_id': RomeAnalyticsSpyInstance.RomeAppsFlyerUid,
        'fb_app_name': 'legionrome',
        'app_name': 'legionrome',
        'onelink': onelinkData,
        'bundle_identifier': 'com.legioncardsofrome.cardofrome.legioncardsofrome',
        'app_version': '1.4.1',
        'apple_id': '6771730453',
        'fcm_token': token ?? 'no_token',
        'device_id': RomeDeviceProfileInstance.RomeDeviceId ?? 'no_device',
        'instance_id':
        RomeDeviceProfileInstance.RomeSessionId ?? 'no_instance',
        'platform': RomeDeviceProfileInstance.RomePlatformName ?? 'no_type',
        'os_version': RomeDeviceProfileInstance.RomeOsVersion ?? 'no_os',
        'language': RomeDeviceProfileInstance.RomeLanguageCode ?? 'en',
        'timezone': RomeDeviceProfileInstance.RomeTimezoneName ?? 'UTC',
        'push_enabled': RomeDeviceProfileInstance.RomePushEnabled,
        'useruid': RomeAnalyticsSpyInstance.RomeAppsFlyerUid,
        'safearea': RomeDeviceProfileInstance.RomeSafeAreaEnabled,
        'safearea_color':
        RomeDeviceProfileInstance.RomeSafeAreaColor ?? '',
        'useragent':
        RomeDeviceProfileInstance.RomeBaseUserAgent ?? 'unknown_useragent',
        'push':
        RomeDeviceProfileInstance.RomeLastPushData ?? <String, dynamic>{},
        'deep': deepLink,
        'fpscashier': RomeDeviceProfileInstance.romeSafeCasher,
      },
    };
  }
}

class RomeCourierService {
  final RomeBosunViewModel RomeBosun;
  final InAppWebViewController? Function() RomeGetWebViewController;

  RomeCourierService({
    required this.RomeBosun,
    required this.RomeGetWebViewController,
  });

  Future<InAppWebViewController?> _romeWaitForController({
    Duration timeout = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 200),
  }) async {
    final RomeLoggerService logger = RomeLoggerService();
    final DateTime start = DateTime.now();

    while (DateTime.now().difference(start) < timeout) {
      final InAppWebViewController? c = RomeGetWebViewController();
      if (c != null) {
        return c;
      }
      await Future<void>.delayed(interval);
    }

    logger.RomeLogWarn('_romeWaitForController: timeout, controller is still null');
    return null;
  }

  Future<void> RomePutDeviceToLocalStorage(String? token) async {
    final InAppWebViewController? romeController = await _romeWaitForController();
    if (romeController == null) return;

    final Map<String, dynamic> romeMap = RomeBosun.RomeDeviceMap(token);
    RomeLoggerService().RomeLogInfo("applocal (${jsonEncode(romeMap)});");

    await RomeSaveJsonToLocalStorageAndPrefs(
      controller: romeController,
      key: 'app_data',
      data: romeMap,
    );
  }

  Future<void> RomeSendRawToPage(
      String? token, {
        String? deepLink,
      }) async {
    final InAppWebViewController? romeController = await _romeWaitForController();
    if (romeController == null) return;

    final Map<String, dynamic> romePayload =
    RomeBosun.RomeAppsFlyerPayload(token, deepLink: deepLink);

    final String romeJsonString = jsonEncode(romePayload);

    RomeLoggerService().RomeLogInfo('SendRawData: $romeJsonString');

    final String jsSafeJson = jsonEncode(romeJsonString);
    final String jsCode = 'sendRawData($jsSafeJson);';

    try {
      await romeController.evaluateJavascript(source: jsCode);
    } catch (e, st) {
      RomeLoggerService()
          .RomeLogError('RomeSendRawToPage evaluateJavascript error: $e\n$st');
    }
  }
}

// ============================================================================
// Статистика
// ============================================================================

Future<String> RomeResolveFinalUrl(
    String startUrl, {
      int maxHops = 10,
    }) async {
  final HttpClient romeHttpClient = HttpClient();

  try {
    Uri romeCurrentUri = Uri.parse(startUrl);

    for (int romeIndex = 0; romeIndex < maxHops; romeIndex++) {
      final HttpClientRequest romeRequest =
      await romeHttpClient.getUrl(romeCurrentUri);
      romeRequest.followRedirects = false;
      final HttpClientResponse romeResponse = await romeRequest.close();

      if (romeResponse.isRedirect) {
        final String? romeLocationHeader =
        romeResponse.headers.value(HttpHeaders.locationHeader);
        if (romeLocationHeader == null || romeLocationHeader.isEmpty) {
          break;
        }

        final Uri romeNextUri = Uri.parse(romeLocationHeader);
        romeCurrentUri = romeNextUri.hasScheme
            ? romeNextUri
            : romeCurrentUri.resolveUri(romeNextUri);
        continue;
      }

      return romeCurrentUri.toString();
    }

    return romeCurrentUri.toString();
  } catch (error) {
    print('goldenLuxuryResolveFinalUrl error: $error');
    return startUrl;
  } finally {
    romeHttpClient.close(force: true);
  }
}

Future<void> RomePostStat({
  required String event,
  required int timeStart,
  required String url,
  required int timeFinish,
  required String appSid,
  int? firstPageLoadTs,
}) async {
  try {
    final String romeResolvedUrl = await RomeResolveFinalUrl(url);

    final Map<String, dynamic> romePayload = <String, dynamic>{
      'event': event,
      'timestart': timeStart,
      'timefinsh': timeFinish,
      'url': romeResolvedUrl,
      'appleID': '6771730453',
      'open_count': '$appSid/$timeStart',
    };

    print('goldenLuxuryStat $romePayload');

    final http.Response romeResponse = await http.post(
      Uri.parse('$romeStatEndpoint/$appSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(romePayload),
    );

    print(
        'goldenLuxuryStat resp=${romeResponse.statusCode} body=${romeResponse.body}');
  } catch (error) {
    print('goldenLuxuryPostStat error: $error');
  }
}

// ============================================================================
// Банковские утилиты
// ============================================================================

bool RomeIsBankScheme(Uri uri) {
  final String scheme = uri.scheme.toLowerCase();
  return romeBankSchemes.contains(scheme);
}

bool RomeIsBankDomain(Uri uri) {
  final String host = uri.host.toLowerCase();
  if (host.isEmpty) return false;

  for (final String bank in romeBankDomains) {
    final String bankHost = bank.toLowerCase();
    if (host == bankHost || host.endsWith('.$bankHost')) {
      return true;
    }
  }
  return false;
}

Future<bool> RomeOpenBank(Uri uri) async {
  try {
    if (RomeIsBankScheme(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        RomeIsBankDomain(uri)) {
      final bool ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      return ok;
    }
  } catch (e) {
    print('RomeOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class RomeHarbor extends StatefulWidget {
  final String? RomeSignal;

  const RomeHarbor({super.key, required this.RomeSignal});

  @override
  State<RomeHarbor> createState() => _RomeHarborState();
}

class _RomeHarborState extends State<RomeHarbor> with WidgetsBindingObserver {
  InAppWebViewController? RomeWebViewController;

  InAppWebViewController? RomePopupWebViewController;
  bool _romeIsPopupVisible = false;
  String? _romePopupUrl;
  CreateWindowAction? _romePopupCreateAction;

  bool _romePopupCanGoBack = false;
  String? _romePopupCurrentUrl;

  bool _romeIsOpeningExternalNewTab = false;
  final Set<String> _romeHandledNewTabUrls = <String>{};

  Timer? _romeParentInstallTimer;
  Timer? _romePopupInstallTimer;

  final String RomeHomeUrl = 'https://data.legionrome.top/';

  int RomeWebViewKeyCounter = 0;
  DateTime? RomeSleepAt;
  bool RomeVeilVisible = false;
  double RomeWarmProgress = 0.0;
  late Timer RomeWarmTimer;
  final int RomeWarmSeconds = 6;
  bool RomeCoverVisible = true;

  bool RomeLoadedOnceSent = false;
  int? RomeFirstPageTimestamp;

  RomeCourierService? RomeCourier;
  RomeBosunViewModel? RomeBosunInstance;

  String RomeCurrentUrl = '';
  int RomeStartLoadTimestamp = 0;

  final RomeDeviceProfile RomeDeviceProfileInstance = RomeDeviceProfile();
  final RomeAnalyticsSpyService RomeAnalyticsSpyInstance =
  RomeAnalyticsSpyService();

  final Set<String> RomeSpecialSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> RomeExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  String? RomeDeepLinkFromPush;

  String? _romeBaseUserAgent;
  String _romeCurrentUserAgent = "";
  String? _romeCurrentUrl;

  String? _romeServerUserAgent;

  bool _romeSafeAreaEnabled = false;
  Color _romeSafeAreaBackgroundColor = const Color(0xFF000000);

  bool _romeStartupSendRawDone = false;

  String? _romePendingLoadedJs;

  bool _romeLoadedJsExecutedOnce = false;

  bool _romeIsInGoogleAuth = false;

  List<String> _romeButtonWhitelist = <String>[];
  bool _romeShowBackButton = false;

  bool _romeBackButtonHiddenAfterTap = false;

  bool _romeIsCurrentlyOnGoogle = false;

  static const MethodChannel _romeAppsFlyerDeepLinkChannel =
  MethodChannel('appsflyer_deeplink_channel');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RomeFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;
    _romeCurrentUrl = RomeHomeUrl;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          RomeCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        RomeVeilVisible = true;
      });
    });

    _romeBindPushChannelFromAppDelegate();
    _romeBindAppsFlyerDeepLinkChannel();
    RomeBootHarbor();
  }

  bool _romeIsAboutBlankUrl(String? value) {
    final String u = (value ?? '').trim().toLowerCase();
    return u.isEmpty || u == 'about:blank' || u.startsWith('about:blank');
  }

  bool _romeIsAboutBlankUri(Uri? uri) => _romeIsAboutBlankUrl(uri?.toString());

  void _romeBindAppsFlyerDeepLinkChannel() {
    _romeAppsFlyerDeepLinkChannel.setMethodCallHandler(
          (MethodCall call) async {
        if (call.method == 'onDeepLink') {
          try {
            final dynamic args = call.arguments;

            Map<String, dynamic> payload;

            print(" Data Deepl link ${args.toString()}");
            if (args is Map) {
              payload = Map<String, dynamic>.from(args as Map);
            } else if (args is String) {
              payload = jsonDecode(args) as Map<String, dynamic>;
            } else {
              payload = <String, dynamic>{'raw': args.toString()};
            }

            RomeLoggerService().RomeLogInfo(
              'AppsFlyer onDeepLink from iOS: $payload',
            );

            final dynamic raw = payload['raw'];
            if (raw is Map) {
              final Map<String, dynamic> normalized =
              Map<String, dynamic>.from(raw as Map);

              print("One Link Data $normalized");
              RomeAnalyticsSpyInstance.RomeSetOneLinkData(normalized);
            } else {
              RomeAnalyticsSpyInstance.RomeSetOneLinkData(payload);
            }
          } catch (e, st) {
            RomeLoggerService()
                .RomeLogError('Error in onDeepLink handler: $e\n$st');
          }
        }
      },
    );
  }

  void _romeBindPushChannelFromAppDelegate() {
    const MethodChannel pushChannel = MethodChannel('com.example.fcm/push');

    pushChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'setPushData') {
        try {
          Map<String, dynamic> pushData;
          if (call.arguments is Map) {
            pushData = Map<String, dynamic>.from(call.arguments);
            print("Get Push Data $pushData");
          } else if (call.arguments is String) {
            pushData =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
          } else {
            pushData = <String, dynamic>{'raw': call.arguments.toString()};
          }

          RomeLoggerService()
              .RomeLogInfo('Got push data from AppDelegate: $pushData');

          RomeDeviceProfileInstance.RomeLastPushData = pushData;

          final dynamic uriRaw = pushData['uri'] ?? pushData['deep_link'];
          if (uriRaw != null && uriRaw.toString().isNotEmpty) {
            final String u = uriRaw.toString();
            RomeDeepLinkFromPush = u;
            await RomeSaveCachedDeep(u);
          }
        } catch (e, st) {
          RomeLoggerService()
              .RomeLogError('setPushData handler error: $e\n$st');
        }
      }
    });
  }

  bool _romeIsGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google.com') ||
        full.contains('accounts.google.') ||
        full.contains('googleusercontent.com') ||
        full.contains('gstatic.com');
  }

  Future<void> _romeApplyGoogleUserAgent() async {
    if (RomeWebViewController == null) return;

    const String googleUa = 'random';

    if (_romeCurrentUserAgent == googleUa) {
      RomeLoggerService()
          .RomeLogInfo('[UA] Already set to "random" for Google, skip');
      return;
    }

    RomeLoggerService()
        .RomeLogInfo('[UA] Applying GOOGLE User-Agent: $googleUa');

    try {
      await RomeWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      _romeCurrentUserAgent = googleUa;
      _romeIsCurrentlyOnGoogle = true;
      print('[UA] GOOGLE WEBVIEW USER AGENT: $_romeCurrentUserAgent');
    } catch (e) {
      RomeLoggerService()
          .RomeLogError('Error setting Google User-Agent: $e');
    }
  }

  Future<void> _romeApplyGoogleUserAgentForPopup() async {
    if (RomePopupWebViewController == null) return;

    const String googleUa = 'random';

    RomeLoggerService()
        .RomeLogInfo('[UA] Applying GOOGLE User-Agent to POPUP: $googleUa');

    try {
      await RomePopupWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: googleUa),
      );
      print('[UA] GOOGLE POPUP USER AGENT: $googleUa');
    } catch (e) {
      RomeLoggerService()
          .RomeLogError('Error setting Google User-Agent for popup: $e');
    }
  }

  Future<void> _romeUpdateUserAgentFromServerPayload(
      Map<dynamic, dynamic> root) async {
    String? fullua;
    String? uatail;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['fullua'] != null &&
          content['fullua'].toString().trim().isNotEmpty) {
        fullua = content['fullua'].toString().trim();
      }
      if (content['uatail'] != null &&
          content['uatail'].toString().trim().isNotEmpty) {
        uatail = content['uatail'].toString().trim();
      }
    }

    if (fullua == null &&
        root['fullua'] != null &&
        root['fullua'].toString().trim().isNotEmpty) {
      fullua = root['fullua'].toString().trim();
    }
    if (uatail == null &&
        root['uatail'] != null &&
        root['uatail'].toString().trim().isNotEmpty) {
      uatail = root['uatail'].toString().trim();
    }

    if (uatail == null) {
      final dynamic adata = root['adata'];
      if (adata is Map &&
          adata['uatail'] != null &&
          adata['uatail'].toString().trim().isNotEmpty) {
        uatail = adata['uatail'].toString().trim();
      }
    }

    await _romeApplyUserAgent(fullua: fullua, uatail: uatail);
  }

  Future<void> _romeApplyUserAgent({String? fullua, String? uatail}) async {
    if (RomeWebViewController == null) return;

    if (_romeBaseUserAgent == null || _romeBaseUserAgent!.trim().isEmpty) {
      try {
        final ua = await RomeWebViewController!.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _romeBaseUserAgent = ua.trim();
          _romeCurrentUserAgent = _romeBaseUserAgent!;
          RomeDeviceProfileInstance.RomeBaseUserAgent = _romeBaseUserAgent;
          RomeLoggerService()
              .RomeLogInfo('Base User-Agent detected: $_romeBaseUserAgent');
        }
      } catch (e) {
        RomeLoggerService()
            .RomeLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_romeBaseUserAgent == null || _romeBaseUserAgent!.trim().isEmpty) {
      RomeLoggerService()
          .RomeLogWarn('Base User-Agent is still null/empty, skip UA update');
      return;
    }

    RomeLoggerService().RomeLogInfo(
        'Server UA payload: fullua="$fullua", uatail="$uatail", base="$_romeBaseUserAgent"');

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_romeBaseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = "${_romeBaseUserAgent!}";
    }

    _romeServerUserAgent = newUa;
    RomeLoggerService()
        .RomeLogInfo('Server UA calculated and stored: $_romeServerUserAgent');
  }

  Future<void> _romeApplyNormalUserAgentIfNeeded() async {
    if (RomeWebViewController == null) return;

    if (_romeIsCurrentlyOnGoogle) {
      RomeLoggerService().RomeLogInfo(
          '[UA] Currently on Google page, keeping "random" UA');
      return;
    }

    final String targetUa = _romeServerUserAgent ?? _romeBaseUserAgent ?? 'random';

    if (targetUa == _romeCurrentUserAgent) {
      RomeLoggerService()
          .RomeLogInfo('Normal UA unchanged, keeping: $_romeCurrentUserAgent');
      return;
    }

    RomeLoggerService()
        .RomeLogInfo('Applying NORMAL WebView User-Agent: $targetUa');

    try {
      await RomeWebViewController!.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _romeCurrentUserAgent = targetUa;
      print('[UA] NORMAL WEBVIEW USER AGENT: $_romeCurrentUserAgent');
    } catch (e) {
      RomeLoggerService()
          .RomeLogError('Error while setting normal User-Agent "$targetUa": $e');
    }
  }

  Future<void> _romeSwitchUserAgentForUrl(Uri? uri) async {
    if (uri == null) return;

    if (_romeIsGoogleUrl(uri)) {
      _romeIsCurrentlyOnGoogle = true;
      await _romeApplyGoogleUserAgent();
    } else {
      if (_romeIsCurrentlyOnGoogle) {
        _romeIsCurrentlyOnGoogle = false;
      }
      await _romeApplyNormalUserAgentIfNeeded();
    }
  }

  Future<void> romePrintJsUserAgent() async {
    if (RomeWebViewController == null) return;

    try {
      final ua = await RomeWebViewController!.evaluateJavascript(
        source: "navigator.userAgent",
      );

      if (ua is String) {
        print('[JS UA] navigator.userAgent = $ua');
      } else {
        print('[JS UA] navigator.userAgent (non-string) = $ua');
      }
    } catch (e, st) {
      print('Error reading navigator.userAgent: $e\n$st');
    }
  }

  Future<void> romeDebugPrintCurrentUserAgent() async {
    RomeLoggerService()
        .RomeLogInfo('[STATE UA] _romeCurrentUserAgent = $_romeCurrentUserAgent');
    await romePrintJsUserAgent();
  }

  Future<void> RomeLoadLoadedFlag() async {
    final SharedPreferences romePrefs = await SharedPreferences.getInstance();
    RomeLoadedOnceSent = romePrefs.getBool(romeLoadedOnceKey) ?? false;
  }

  Future<void> RomeSaveLoadedFlag() async {
    final SharedPreferences romePrefs = await SharedPreferences.getInstance();
    await romePrefs.setBool(romeLoadedOnceKey, true);
    RomeLoadedOnceSent = true;
  }

  Future<void> RomeLoadCachedDeep() async {
    try {
      final SharedPreferences romePrefs = await SharedPreferences.getInstance();
      final String? romeCached = romePrefs.getString(romeCachedDeepKey);
      if ((romeCached ?? '').isNotEmpty) {
        RomeDeepLinkFromPush = romeCached;
      }
    } catch (_) {}
  }

  Future<void> RomeSaveCachedDeep(String uri) async {
    try {
      final SharedPreferences romePrefs = await SharedPreferences.getInstance();
      await romePrefs.setString(romeCachedDeepKey, uri);
    } catch (_) {}
  }

  Future<void> RomeSendLoadedOnce({
    required String url,
    required int timestart,
  }) async {
    if (RomeLoadedOnceSent) return;

    final int romeNow = DateTime.now().millisecondsSinceEpoch;

    await RomePostStat(
      event: 'Loaded',
      timeStart: timestart,
      timeFinish: romeNow,
      url: url,
      appSid: RomeAnalyticsSpyInstance.RomeAppsFlyerUid,
      firstPageLoadTs: RomeFirstPageTimestamp,
    );

    await RomeSaveLoadedFlag();
  }

  void RomeBootHarbor() {
    RomeStartWarmProgress();
    RomeWireFcmHandlers();
    RomeAnalyticsSpyInstance.RomeStartTracking(
      onUpdate: () => setState(() {}),
    );
    RomeBindNotificationTap();
    RomePrepareDeviceProfile();
  }

  void RomeWireFcmHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage romeMessage) async {
      final dynamic romeLink = romeMessage.data['uri'];
      if (romeLink != null) {
        final String romeUri = romeLink.toString();
        RomeDeepLinkFromPush = romeUri;
        await RomeSaveCachedDeep(romeUri);
      } else {
        RomeResetHomeAfterDelay();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage romeMessage) async {
      final dynamic romeLink = romeMessage.data['uri'];
      if (romeLink != null) {
        final String romeUri = romeLink.toString();
        RomeDeepLinkFromPush = romeUri;
        await RomeSaveCachedDeep(romeUri);

        RomeNavigateToUri(romeUri);

        await RomePushDeviceInfo();
        await RomePushAppsFlyerData();
      } else {
        RomeResetHomeAfterDelay();
      }
    });
  }

  void RomeBindNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onNotificationTap') {
        final Map<String, dynamic> romePayload =
        Map<String, dynamic>.from(call.arguments);
        final String? romeUriRaw = romePayload['uri']?.toString();

        if (romeUriRaw != null &&
            romeUriRaw.isNotEmpty &&
            !romeUriRaw.contains('Нет URI')) {
          final String romeUri = romeUriRaw;
          RomeDeepLinkFromPush = romeUri;
          await RomeSaveCachedDeep(romeUri);

          if (!context.mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext context) => RomeTableView(romeUri),
            ),
                (Route<dynamic> route) => false,
          );

          await RomePushDeviceInfo();
          await RomePushAppsFlyerData();
        }
      }
    });
  }

  Future<void> RomePrepareDeviceProfile() async {
    try {
      await RomeDeviceProfileInstance.RomeInitialize();

      final FirebaseMessaging romeMessaging = FirebaseMessaging.instance;
      final NotificationSettings romeSettings =
      await romeMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      RomeDeviceProfileInstance.RomePushEnabled =
          romeSettings.authorizationStatus ==
              AuthorizationStatus.authorized ||
              romeSettings.authorizationStatus ==
                  AuthorizationStatus.provisional;

      await RomeLoadLoadedFlag();
      await RomeLoadCachedDeep();

      RomeBosunInstance = RomeBosunViewModel(
        RomeDeviceProfileInstance: RomeDeviceProfileInstance,
        RomeAnalyticsSpyInstance: RomeAnalyticsSpyInstance,
      );

      RomeCourier = RomeCourierService(
        RomeBosun: RomeBosunInstance!,
        RomeGetWebViewController: () => RomeWebViewController,
      );
    } catch (error) {
      RomeLoggerService().RomeLogError('prepareDeviceProfile fail: $error');
    }
  }

  void RomeNavigateToUri(String link) async {
    try {
      await RomeWebViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(link)),
      );
    } catch (error) {
      RomeLoggerService().RomeLogError('navigate error: $error');
    }
  }

  void RomeResetHomeAfterDelay() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        RomeWebViewController?.loadUrl(
          urlRequest: URLRequest(url: WebUri(RomeHomeUrl)),
        );
      } catch (_) {}
    });
  }

  String? _romeResolveTokenForShip() {
    if (widget.RomeSignal != null && widget.RomeSignal!.isNotEmpty) {
      return widget.RomeSignal;
    }
    return null;
  }

  Future<void> _romeSendAllDataToPageTwice() async {
    await RomePushDeviceInfo();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await RomePushDeviceInfo();
      await RomePushAppsFlyerData();
    });
  }

  Future<void> RomePushDeviceInfo() async {
    final String? romeToken = _romeResolveTokenForShip();

    try {
      await RomeCourier?.RomePutDeviceToLocalStorage(romeToken);
    } catch (error) {
      RomeLoggerService().RomeLogError('pushDeviceInfo error: $error');
    }
  }

  Future<void> RomePushAppsFlyerData() async {
    final String? romeToken = _romeResolveTokenForShip();

    try {
      await RomeCourier?.RomeSendRawToPage(
        romeToken,
        deepLink: RomeDeepLinkFromPush,
      );
    } catch (error) {
      RomeLoggerService().RomeLogError('pushAppsFlyerData error: $error');
    }
  }

  void RomeStartWarmProgress() {
    int romeTick = 0;
    RomeWarmProgress = 0.0;

    RomeWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
          if (!mounted) return;

          setState(() {
            romeTick++;
            RomeWarmProgress = romeTick / (RomeWarmSeconds * 10);

            if (RomeWarmProgress >= 1.0) {
              RomeWarmProgress = 1.0;
              RomeWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      RomeSleepAt = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {
      if (Platform.isIOS && RomeSleepAt != null) {
        final DateTime romeNow = DateTime.now();
        final Duration romeDrift = romeNow.difference(RomeSleepAt!);

        if (romeDrift > const Duration(minutes: 25)) {
          RomeReboardHarbor();
        }
      }
      RomeSleepAt = null;
    }
  }

  void RomeReboardHarbor() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              RomeHarbor(RomeSignal: widget.RomeSignal),
        ),
            (Route<dynamic> route) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RomeWarmTimer.cancel();

    _romeParentInstallTimer?.cancel();
    _romePopupInstallTimer?.cancel();

    RomeWebViewController = null;
    RomePopupWebViewController = null;

    super.dispose();
  }

  bool RomeIsBareEmail(Uri uri) {
    final String romeScheme = uri.scheme;
    if (romeScheme.isNotEmpty) return false;
    final String romeRaw = uri.toString();
    return romeRaw.contains('@') && !romeRaw.contains(' ');
  }

  Uri RomeToMailto(Uri uri) {
    final String romeFull = uri.toString();
    final List<String> romeParts = romeFull.split('?');
    final String romeEmail = romeParts.first;
    final Map<String, String> romeQueryParams = romeParts.length > 1
        ? Uri.splitQueryString(romeParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: romeEmail,
      queryParameters: romeQueryParams.isEmpty ? null : romeQueryParams,
    );
  }

  Future<bool> RomeOpenMailExternal(Uri mailto) async {
    try {
      final String scheme = mailto.scheme.toLowerCase();
      final String path = mailto.path.toLowerCase();

      RomeLoggerService().RomeLogInfo(
          'RomeOpenMailExternal: scheme=$scheme path=$path uri=$mailto');

      if (scheme != 'mailto') {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        RomeLoggerService()
            .RomeLogInfo('RomeOpenMailExternal: non-mailto result=$ok');
        return ok;
      }

      final bool can = await canLaunchUrl(mailto);
      RomeLoggerService()
          .RomeLogInfo('RomeOpenMailExternal: canLaunchUrl(mailto) = $can');

      if (can) {
        final bool ok = await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        );
        RomeLoggerService()
            .RomeLogInfo('RomeOpenMailExternal: externalApplication result=$ok');
        if (ok) return true;
      }

      RomeLoggerService().RomeLogWarn(
          'RomeOpenMailExternal: no native handler for mailto, fallback to Gmail Web');
      final Uri gmailUri = RomeGmailizeMailto(mailto);
      final bool webOk = await RomeOpenWeb(gmailUri);
      RomeLoggerService()
          .RomeLogInfo('RomeOpenMailExternal: Gmail Web fallback result=$webOk');
      return webOk;
    } catch (e, st) {
      RomeLoggerService()
          .RomeLogError('RomeOpenMailExternal error: $e\n$st; url=$mailto');
      return false;
    }
  }

  Future<bool> RomeOpenMailWeb(Uri mailto) async {
    final Uri romeGmailUri = RomeGmailizeMailto(mailto);
    return RomeOpenWeb(romeGmailUri);
  }

  Uri RomeGmailizeMailto(Uri mailUri) {
    final Map<String, String> romeQueryParams = mailUri.queryParameters;

    final Map<String, String> romeParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (mailUri.path.isNotEmpty) 'to': mailUri.path,
      if ((romeQueryParams['subject'] ?? '').isNotEmpty)
        'su': romeQueryParams['subject']!,
      if ((romeQueryParams['body'] ?? '').isNotEmpty)
        'body': romeQueryParams['body']!,
      if ((romeQueryParams['cc'] ?? '').isNotEmpty)
        'cc': romeQueryParams['cc']!,
      if ((romeQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': romeQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', romeParams);
  }

  bool RomeIsPlatformLink(Uri uri) {
    final String romeScheme = uri.scheme.toLowerCase();
    if (RomeSpecialSchemes.contains(romeScheme)) {
      return true;
    }

    if (romeScheme == 'http' || romeScheme == 'https') {
      final String romeHost = uri.host.toLowerCase();

      if (RomeExternalHosts.contains(romeHost)) {
        return true;
      }

      if (romeHost.endsWith('t.me')) return true;
      if (romeHost.endsWith('wa.me')) return true;
      if (romeHost.endsWith('m.me')) return true;
      if (romeHost.endsWith('signal.me')) return true;
      if (romeHost.endsWith('facebook.com')) return true;
      if (romeHost.endsWith('instagram.com')) return true;
      if (romeHost.endsWith('twitter.com')) return true;
      if (romeHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String RomeDigitsOnly(String source) =>
      source.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri RomeHttpizePlatformUri(Uri uri) {
    final String romeScheme = uri.scheme.toLowerCase();

    if (romeScheme == 'tg' || romeScheme == 'telegram') {
      final Map<String, String> romeQp = uri.queryParameters;
      final String? romeDomain = romeQp['domain'];

      if (romeDomain != null && romeDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$romeDomain',
          <String, String>{
            if (romeQp['start'] != null) 'start': romeQp['start']!,
          },
        );
      }

      final String romePath = uri.path.isNotEmpty ? uri.path : '';

      return Uri.https(
        't.me',
        '/$romePath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if ((romeScheme == 'http' || romeScheme == 'https') &&
        uri.host.toLowerCase().endsWith('t.me')) {
      return uri;
    }

    if (romeScheme == 'viber') {
      return uri;
    }

    if (romeScheme == 'whatsapp') {
      final Map<String, String> romeQp = uri.queryParameters;
      final String? romePhone = romeQp['phone'];
      final String? romeText = romeQp['text'];

      if (romePhone != null && romePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${RomeDigitsOnly(romePhone)}',
          <String, String>{
            if (romeText != null && romeText.isNotEmpty) 'text': romeText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (romeText != null && romeText.isNotEmpty) 'text': romeText,
        },
      );
    }

    if ((romeScheme == 'http' || romeScheme == 'https') &&
        (uri.host.toLowerCase().endsWith('wa.me') ||
            uri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return uri;
    }

    if (romeScheme == 'skype') {
      return uri;
    }

    if (romeScheme == 'fb-messenger') {
      final String romePath =
      uri.pathSegments.isNotEmpty ? uri.pathSegments.join('/') : '';
      final Map<String, String> romeQp = uri.queryParameters;

      final String romeId = romeQp['id'] ?? romeQp['user'] ?? romePath;

      if (romeId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$romeId',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    if (romeScheme == 'sgnl') {
      final Map<String, String> romeQp = uri.queryParameters;
      final String? romePhone = romeQp['phone'];
      final String? romeUsername = romeQp['username'];

      if (romePhone != null && romePhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${RomeDigitsOnly(romePhone)}',
        );
      }

      if (romeUsername != null && romeUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$romeUsername',
        );
      }

      final String romePath = uri.pathSegments.join('/');
      if (romePath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$romePath',
          uri.queryParameters.isEmpty ? null : uri.queryParameters,
        );
      }

      return uri;
    }

    if (romeScheme == 'tel') {
      return Uri.parse('tel:${RomeDigitsOnly(uri.path)}');
    }

    if (romeScheme == 'mailto') {
      return uri;
    }

    if (romeScheme == 'bnl') {
      final String romeNewPath = uri.path.isNotEmpty ? uri.path : '';
      return Uri.https(
        'bnl.com',
        '/$romeNewPath',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      );
    }

    return uri;
  }

  Future<bool> RomeOpenWeb(Uri uri) async {
    try {
      if (await launchUrl(
        uri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      try {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> RomeOpenExternal(Uri uri) async {
    try {
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      return false;
    }
  }

  void RomeHandleServerSavedata(String savedata) {
    print('onServerResponse savedata: $savedata');


    if(savedata=='false'){
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) => SimpleFullInAppWebViewPage(),
        ),
      );
    }
  }

  Color _romeParseHexColor(String hex) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) {
      value = 'FF$value';
    }
    final intColor = int.tryParse(value, radix: 16) ?? 0xFF000000;
    return Color(intColor);
  }

  Future<void> _romeUpdateAppDataInLocalStorageFromProfile() async {
    final InAppWebViewController? controller = RomeWebViewController;
    if (controller == null) return;

    final String? token = _romeResolveTokenForShip();
    final Map<String, dynamic> map =
    RomeDeviceProfileInstance.RomeToMap(fcmToken: token);

    RomeLoggerService()
        .RomeLogInfo('updateAppDataFromProfile: ${jsonEncode(map)}');

    await RomeSaveJsonToLocalStorageAndPrefs(
      controller: controller,
      key: 'app_data',
      data: map,
    );
  }

  void _romeUpdateExtraDataFromServerPayload(Map<dynamic, dynamic> root) {
    try {
      final dynamic adataRaw = root['adata'];
      if (adataRaw is Map) {
        final Map adata = adataRaw;

        final dynamic buttonswlRaw = adata['buttonswl'];
        if (buttonswlRaw is List) {
          final List<String> list = buttonswlRaw
              .where((e) => e != null)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          setState(() {
            _romeButtonWhitelist = list;
          });
          RomeLoggerService()
              .RomeLogInfo('buttonswl updated: $_romeButtonWhitelist');
          _romeUpdateBackButtonVisibility();
        }

        if (adata.containsKey('fpscashier')) {
          final dynamic fpsRaw = adata['fpscashier'];
          bool? fpsValue;

          if (fpsRaw is bool) {
            fpsValue = fpsRaw;
          } else if (fpsRaw is num) {
            fpsValue = fpsRaw != 0;
          } else if (fpsRaw is String) {
            final String v = fpsRaw.toLowerCase().trim();
            if (v == 'true' || v == '1' || v == 'yes') fpsValue = true;
            if (v == 'false' || v == '0' || v == 'no') fpsValue = false;
          }

          if (fpsValue != null) {
            final bool old = RomeDeviceProfileInstance.romeSafeCasher;
            RomeDeviceProfileInstance.romeSafeCasher = fpsValue;
            RomeLoggerService().RomeLogInfo(
                'fpscashier updated from server payload: $fpsValue');

            _romeUpdateAppDataInLocalStorageFromProfile();

            if (!old && fpsValue && RomeWebViewController != null) {
              RomeLoggerService().RomeLogInfo(
                  'fpscashier switched to true, installing JS hooks now');
              _romeScheduleSafeInstall(RomeWebViewController!, label: 'parent');
            }
          }
        }

        final dynamic savelsRaw = adata['savels'];
        if (savelsRaw is Map) {
          RomeDeviceProfileInstance.RomeSavels =
          Map<String, dynamic>.from(savelsRaw);
          RomeLoggerService().RomeLogInfo(
              'savels stored in profile: ${RomeDeviceProfileInstance.RomeSavels}');
          _romeUpdateAppDataInLocalStorageFromProfile();
        }
      }
    } catch (e, st) {
      RomeLoggerService()
          .RomeLogError('Error in _romeUpdateExtraDataFromServerPayload: $e\n$st');
    }
  }

  void _romeUpdateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
    RomeLoggerService()
        .RomeLogInfo('SAFEAREA RAW PAYLOAD: ${jsonEncode(root)}');

    bool? safearea;
    String? bgLightHex;
    String? bgDarkHex;

    final dynamic content = root['content'];
    if (content is Map) {
      if (content['safearea'] != null) {
        final dynamic raw = content['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (content['safearea_color'] != null &&
          content['safearea_color'].toString().trim().isNotEmpty) {
        bgLightHex = content['safearea_color'].toString().trim();
        bgDarkHex = bgLightHex;
      }
    }

    final dynamic adata = root['adata'];
    if (adata is Map) {
      if (safearea == null && adata['safearea'] != null) {
        final dynamic raw = adata['safearea'];
        if (raw is bool) {
          safearea = raw;
        } else if (raw is String) {
          final String v = raw.toLowerCase().trim();
          if (v == 'true' || v == '1' || v == 'yes') safearea = true;
          if (v == 'false' || v == '0' || v == 'no') safearea = false;
        } else if (raw is num) {
          safearea = raw != 0;
        }
      }

      if (adata['bgsareaw'] != null &&
          adata['bgsareaw'].toString().trim().isNotEmpty) {
        bgLightHex = adata['bgsareaw'].toString().trim();
      }
      if (adata['bgsareab'] != null &&
          adata['bgsareab'].toString().trim().isNotEmpty) {
        bgDarkHex = adata['bgsareab'].toString().trim();
      }
    }

    if (safearea == null && root['safearea'] != null) {
      final dynamic raw = root['safearea'];
      if (raw is bool) {
        safearea = raw;
      } else if (raw is String) {
        final String v = raw.toLowerCase().trim();
        if (v == 'true' || v == '1' || v == 'yes') safearea = true;
        if (v == 'false' || v == '0' || v == 'no') safearea = false;
      } else if (raw is num) {
        safearea = raw != 0;
      }
    }

    RomeLoggerService().RomeLogInfo(
        'SAFEAREA PARSED: enabled=$safearea, light=$bgLightHex, dark=$bgDarkHex');

    if (safearea == null) {
      return;
    }

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    final bool enabled = safearea;
    Color background =
    enabled ? const Color(0xFF1A1A22) : const Color(0xFF000000);

    if (enabled && chosenHex != null && chosenHex.isNotEmpty) {
      background = _romeParseHexColor(chosenHex);
    }

    setState(() {
      _romeSafeAreaEnabled = enabled;
      _romeSafeAreaBackgroundColor = background;
      RomeDeviceProfileInstance.RomeSafeAreaEnabled = enabled;
      RomeDeviceProfileInstance.RomeSafeAreaColor =
      enabled ? (chosenHex ?? '#1A1A22') : '';
    });

    () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool('safearea_enabled', enabled);
        await prefs.setString(
          'safearea_color',
          RomeDeviceProfileInstance.RomeSafeAreaColor ?? '',
        );
        RomeLoggerService().RomeLogInfo(
          'SafeArea saved to prefs: enabled=$enabled, color="${RomeDeviceProfileInstance.RomeSafeAreaColor}"',
        );
      } catch (e, st) {
        RomeLoggerService().RomeLogError(
            'Error saving SafeArea to prefs: $e\n$st');
      }
    }();

    RomeLoggerService().RomeLogInfo(
        'SAFEAREA STATE UPDATED: enabled=$_romeSafeAreaEnabled, color=$_romeSafeAreaBackgroundColor (brightness=$platformBrightness)');
  }

  bool _romeMatchesButtonWhitelist(String url) {
    if (url.isEmpty) return false;
    if (_romeButtonWhitelist.isEmpty) return false;
    Uri? uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      return false;
    }

    final String host = uri.host.toLowerCase();
    final String full = uri.toString();

    for (final String item in _romeButtonWhitelist) {
      final String trimmed = item.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        if (full.startsWith(trimmed)) return true;
      } else {
        final String domain = trimmed.toLowerCase();
        if (host == domain || host.endsWith('.$domain')) return true;
      }
    }

    return false;
  }

  Future<void> _romeUpdateBackButtonVisibility() async {
    final String current = _romeCurrentUrl ?? RomeCurrentUrl;
    final bool shouldShow = _romeMatchesButtonWhitelist(current);

    if (_romeBackButtonHiddenAfterTap) {
      _romeBackButtonHiddenAfterTap = false;
    }

    if (shouldShow != _romeShowBackButton) {
      if (mounted) {
        setState(() {
          _romeShowBackButton = shouldShow;
        });
      } else {
        _romeShowBackButton = shouldShow;
      }
    }
  }

  Future<void> _romeHandleBackButtonPressed() async {
    if (mounted) {
      setState(() {
        _romeBackButtonHiddenAfterTap = true;
        _romeShowBackButton = false;
      });
    } else {
      _romeBackButtonHiddenAfterTap = true;
      _romeShowBackButton = false;
    }

    if (_romeIsPopupVisible) {
      await _romeHandlePopupBackPressed();
      return;
    }

    if (RomeWebViewController == null) return;
    try {
      if (await RomeWebViewController!.canGoBack()) {
        await RomeWebViewController!.goBack();
      } else {
        await RomeWebViewController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(RomeHomeUrl)),
        );
      }
    } catch (e, st) {
      RomeLoggerService()
          .RomeLogError('Error on back button pressed: $e\n$st');
    }
  }

  InAppWebViewSettings _romeMainWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  InAppWebViewSettings _romePopupWebViewSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
      isInspectable: true,
      disableDefaultErrorPage: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      allowsPictureInPictureMediaPlayback: true,
      useOnDownloadStart: true,
      javaScriptCanOpenWindowsAutomatically: true,
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      transparentBackground: false,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      domStorageEnabled: true,
      databaseEnabled: true,
      cacheEnabled: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      allowsBackForwardNavigationGestures: true,
    );
  }

  Future<void> _romeSafeEvaluateJavascript(
      InAppWebViewController? controller, {
        required String source,
        String debugName = 'js',
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    try {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      await controller.evaluateJavascript(source: source);
    } catch (e) {
      print('WERLOG: safeEvaluateJavascript error [$debugName]: $e');
    }
  }

  Future<void> _romeInstallJsErrorLogger(InAppWebViewController controller) async {
    await _romeSafeEvaluateJavascript(
      controller,
      debugName: 'installJsErrorLogger',
      source: r'''
        (function() {
          if (window.__ncupJsLoggerInstalled) return;
          window.__ncupJsLoggerInstalled = true;

          function serializeError(err) {
            try {
              if (!err) return null;
              var plain = {};
              Object.getOwnPropertyNames(err).forEach(function(key) {
                plain[key] = err[key];
              });
              return plain;
            } catch (_) {
              return { message: String(err) };
            }
          }

          window.onerror = function(message, source, lineno, colno, error) {
            try {
              var payload = {
                type: 'onerror',
                message: String(message || ''),
                source: String(source || ''),
                lineno: lineno || 0,
                colno: colno || 0,
                error: serializeError(error)
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger onerror inner fail', e);
            }
          };

          window.addEventListener('unhandledrejection', function(event) {
            try {
              var reason = event.reason;
              var payload = {
                type: 'unhandledrejection',
                reason: serializeError(reason) || { message: String(reason || '') }
              };
              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupJSLogger', payload);
              }
            } catch (e) {
              console.log('NcupJSLogger unhandledrejection inner fail', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _romeInstallPostMessageBridge(
      InAppWebViewController controller, {
        required String label,
      }) async {
    await _romeSafeEvaluateJavascript(
      controller,
      debugName: 'installPostMessageBridge-$label',
      source: '''
        (function() {
          if (window.__ncupPostMessageBridgeInstalled_$label) return;
          window.__ncupPostMessageBridgeInstalled_$label = true;

          window.addEventListener('message', function(event) {
            try {
              var dataRaw = event.data;
              var dataString;
              try {
                dataString = JSON.stringify(dataRaw);
              } catch (e) {
                dataString = String(dataRaw);
              }

              var payload = {
                label: '$label',
                origin: String(event.origin || ''),
                data: dataString,
                href: String(window.location.href || '')
              };

              console.log('[NCUP postMessage $label]', payload);

              if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                window.flutter_inappwebview.callHandler('NcupPostMessage', payload);
              }

              try {
                var parsed = dataRaw;
                if (typeof parsed === 'string') {
                  parsed = JSON.parse(parsed);
                }
                if (parsed && parsed.type === 'newTab' && parsed.url) {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('NcupCheckoutAction', parsed);
                  }
                }
              } catch (_) {}
            } catch (e) {
              console.log('NcupPostMessage bridge error', e);
            }
          });
        })();
      ''',
    );
  }

  Future<void> _romeInstallCheckoutInterceptor(
      InAppWebViewController controller,
      ) async {
    await _romeSafeEvaluateJavascript(
      controller,
      debugName: 'installCheckoutInterceptor',
      source: r'''
        (function() {
          if (window.__ncupCheckoutInterceptorInstalled) return;
          window.__ncupCheckoutInterceptorInstalled = true;

          function sendToFlutter(data) {
            try {
              if (!data || typeof data !== 'object') return;
              if (data.type === 'newTab' && data.url) {
                console.log('[NCUP checkout interceptor] newTab:', data.url);
                if (
                  window.flutter_inappwebview &&
                  window.flutter_inappwebview.callHandler
                ) {
                  window.flutter_inappwebview.callHandler(
                    'NcupCheckoutAction',
                    data
                  );
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] send error', e);
            }
          }

          function tryParseMaybeJson(value) {
            try {
              if (!value) return null;
              if (typeof value === 'object') {
                return value;
              }
              if (typeof value === 'string') {
                return JSON.parse(value);
              }
              return null;
            } catch (e) {
              return null;
            }
          }

          function tryHandlePayload(payload) {
            try {
              var data = tryParseMaybeJson(payload);
              if (!data) return;

              if (Array.isArray(data)) {
                data.forEach(function(item) {
                  if (item && item.type === 'newTab' && item.url) {
                    sendToFlutter(item);
                  }
                });
                return;
              }

              if (data.type === 'newTab' && data.url) {
                sendToFlutter(data);
                return;
              }

              if (data.savedata) {
                var saved = tryParseMaybeJson(data.savedata);
                if (saved && saved.type === 'newTab' && saved.url) {
                  sendToFlutter(saved);
                  return;
                }
              }

              if (data.data) {
                var nested = tryParseMaybeJson(data.data);
                if (nested && nested.type === 'newTab' && nested.url) {
                  sendToFlutter(nested);
                  return;
                }
              }

              if (data.content) {
                var content = tryParseMaybeJson(data.content);
                if (content && content.type === 'newTab' && content.url) {
                  sendToFlutter(content);
                  return;
                }
              }
            } catch (e) {
              console.log('[NCUP checkout interceptor] handle error', e);
            }
          }

          var originalFetch = window.fetch;
          if (originalFetch) {
            window.fetch = function() {
              return originalFetch.apply(this, arguments).then(function(response) {
                try {
                  var cloned = response.clone();
                  cloned.text().then(function(text) {
                    tryHandlePayload(text);
                  }).catch(function() {});
                } catch (e) {}
                return response;
              });
            };
          }

          var OriginalXHR = window.XMLHttpRequest;
          if (OriginalXHR) {
            window.XMLHttpRequest = function() {
              var xhr = new OriginalXHR();
              var originalOpen = xhr.open;
              var originalSend = xhr.send;

              xhr.open = function() {
                return originalOpen.apply(xhr, arguments);
              };

              xhr.send = function() {
                xhr.addEventListener('load', function() {
                  try {
                    tryHandlePayload(xhr.responseText);
                  } catch (e) {}
                });
                return originalSend.apply(xhr, arguments);
              };

              return xhr;
            };
          }

          var originalOpen = window.open;
          window.open = function(url, target, features) {
            try {
              console.log('[NCUP window.open intercepted]', url, target, features);
            } catch (e) {}

            if (originalOpen) {
              return originalOpen.apply(window, arguments);
            }
            return null;
          };
        })();
      ''',
    );
  }

  Future<void> _romeInstallLocalStorageHook(
      InAppWebViewController controller) async {
    await _romeSafeEvaluateJavascript(
      controller,
      debugName: 'installLocalStorageHook',
      source: r'''
        (function() {
          if (window.__ncupLocalStorageHookInstalled) return;
          window.__ncupLocalStorageHookInstalled = true;

          try {
            var originalSetItem = window.localStorage.setItem;
            window.localStorage.setItem = function(key, value) {
              try {
                if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                  window.flutter_inappwebview.callHandler('NcupLocalStorageSetItem', {
                    key: String(key),
                    value: String(value)
                  });
                }
              } catch (e) {
                console.log('Ncup localStorage hook error', e);
              }
              return originalSetItem.apply(this, arguments);
            };
          } catch (e) {
            console.log('Ncup localStorage hook init error', e);
          }
        })();
      ''',
    );
  }

  Future<void> _romeSafeInstallAll(
      InAppWebViewController? controller, {
        required String label,
      }) async {
    if (controller == null) return;
    if (!mounted) return;

    if (!RomeDeviceProfileInstance.romeSafeCasher) {
      print('WERLOG: safeInstallAll skipped ($label) because fpscashier=false');
      return;
    }

    try {
      await Future<void>.delayed(
        label == 'popup'
            ? const Duration(milliseconds: 550)
            : const Duration(milliseconds: 250),
      );
      if (!mounted) return;
      await _romeInstallJsErrorLogger(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _romeInstallPostMessageBridge(controller, label: label);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _romeInstallCheckoutInterceptor(controller);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      await _romeInstallLocalStorageHook(controller);
    } catch (e) {
      print('WERLOG: safeInstallAll error label=$label error=$e');
    }
  }

  void _romeScheduleSafeInstall(
      InAppWebViewController controller, {
        required String label,
      }) {
    if (label == 'popup') {
      _romePopupInstallTimer?.cancel();
      _romePopupInstallTimer =
          Timer(const Duration(milliseconds: 450), () async {
            if (!mounted) return;
            await _romeSafeInstallAll(controller, label: label);
          });
    } else {
      _romeParentInstallTimer?.cancel();
      _romeParentInstallTimer =
          Timer(const Duration(milliseconds: 250), () async {
            if (!mounted) return;
            await _romeSafeInstallAll(controller, label: label);
          });
    }
  }

  Map<String, dynamic>? _romeTryDecodeMap(dynamic value) {
    try {
      if (value == null) return null;
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      if (value is String) {
        final String trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        final dynamic decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _romeOpenExternalForJsonNewTab(Uri uri) async {
    if (_romeIsAboutBlankUri(uri)) return false;

    final String url = uri.toString();

    if (_romeHandledNewTabUrls.contains(url)) {
      print('WERLOG: duplicate JSON newTab ignored url=$url');
      return true;
    }

    _romeHandledNewTabUrls.add(url);

    if (_romeIsOpeningExternalNewTab) {
      print('WERLOG: external newTab already opening, ignored url=$url');
      return false;
    }

    _romeIsOpeningExternalNewTab = true;

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      print('WERLOG: JSON newTab external launched=$launched url=$url');
      return launched;
    } catch (e) {
      print('WERLOG: JSON newTab external error=$e url=$url');
      return false;
    } finally {
      Future<void>.delayed(const Duration(seconds: 2), () {
        _romeIsOpeningExternalNewTab = false;
      });
    }
  }

  Future<bool> _romeHandleCheckoutAction(dynamic rawPayload) async {
    try {
      Map<String, dynamic>? data = _romeTryDecodeMap(rawPayload);
      if (data == null) return false;

      if (data.containsKey('savedata')) {
        final Map<String, dynamic>? savedataMap =
        _romeTryDecodeMap(data['savedata']);
        if (savedataMap != null) {
          data = savedataMap;
        }
      }

      if (data.containsKey('data')) {
        final Map<String, dynamic>? dataMap = _romeTryDecodeMap(data['data']);
        if (dataMap != null &&
            dataMap['type']?.toString() == 'newTab' &&
            (dataMap['url']?.toString() ?? '').isNotEmpty) {
          data = dataMap;
        }
      }

      if (data.containsKey('content')) {
        final Map<String, dynamic>? contentMap =
        _romeTryDecodeMap(data['content']);
        if (contentMap != null &&
            contentMap['type']?.toString() == 'newTab' &&
            (contentMap['url']?.toString() ?? '').isNotEmpty) {
          data = contentMap;
        }
      }

      final String type = data['type']?.toString() ?? '';
      final String url = data['url']?.toString() ?? '';

      if (type == 'newTab' && url.isNotEmpty) {
        final Uri? uri = Uri.tryParse(url);
        if (uri == null || _romeIsAboutBlankUri(uri)) {
          print('WERLOG: invalid JSON newTab uri=$url');
          return false;
        }

        print('WERLOG: handle JSON newTab url=$url');
        await _romeOpenExternalForJsonNewTab(uri);
        return true;
      }

      return false;
    } catch (e) {
      print('WERLOG: handleCheckoutAction error: $e');
      return false;
    }
  }

  Future<bool> _romeOnCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction request,
      ) async {
    final Uri? romeUri = request.request.url;
    final String urlString = romeUri?.toString() ?? '';

    print(
      'WERLOG: MAIN onCreateWindow '
          'windowId=${request.windowId} '
          'url=$urlString '
          'isDialog=${request.isDialog} '
          'hasGesture=${request.hasGesture}',
    );

    if (romeUri != null) {
      _romeCurrentUrl = romeUri.toString();
      await _romeUpdateBackButtonVisibility();

      if (_romeIsGoogleUrl(romeUri)) {}

      if (RomeIsBankScheme(romeUri) ||
          ((romeUri.scheme == 'http' || romeUri.scheme == 'https') &&
              RomeIsBankDomain(romeUri))) {
        await RomeOpenBank(romeUri);
        return false;
      }

      if (RomeIsBareEmail(romeUri)) {
        final Uri romeMailto = RomeToMailto(romeUri);
        await RomeOpenMailExternal(romeMailto);
        return false;
      }

      final String romeScheme = romeUri.scheme.toLowerCase();

      if (romeScheme == 'mailto') {
        await RomeOpenMailExternal(romeUri);
        return false;
      }

      if (romeScheme == 'tel') {
        await launchUrl(romeUri, mode: LaunchMode.externalApplication);
        return false;
      }

      final String host = romeUri.host.toLowerCase();
      final bool romeIsSocial = host.endsWith('facebook.com') ||
          host.endsWith('instagram.com') ||
          host.endsWith('twitter.com') ||
          host.endsWith('x.com');

      if (romeIsSocial) {
        await RomeOpenExternal(romeUri);
        return false;
      }

      if (RomeIsPlatformLink(romeUri)) {
        final Uri romeWebUri = RomeHttpizePlatformUri(romeUri);
        await RomeOpenExternal(romeWebUri);
        return false;
      }
    }

    if (!mounted) return false;

    setState(() {
      _romePopupCreateAction = request;
      _romePopupUrl = urlString.isNotEmpty && !_romeIsAboutBlankUrl(urlString)
          ? urlString
          : null;
      _romePopupCurrentUrl = _romePopupUrl;
      _romeIsPopupVisible = true;
      _romePopupCanGoBack = false;
    });

    return true;
  }

  Future<bool> _romeOnPopupCreateWindowHandler(
      InAppWebViewController controller,
      CreateWindowAction createWindowAction,
      ) async {
    final Uri? uri = createWindowAction.request.url;
    final String urlString = uri?.toString() ?? '';

    print(
      'WERLOG: POPUP onCreateWindow '
          'windowId=${createWindowAction.windowId} '
          'url=$urlString',
    );

    if (!mounted) return false;

    if (createWindowAction.windowId != null) {
      setState(() {
        _romePopupCreateAction = createWindowAction;
        _romePopupUrl = urlString.isNotEmpty && !_romeIsAboutBlankUrl(urlString)
            ? urlString
            : _romePopupUrl;
        _romePopupCurrentUrl = _romePopupUrl;
        _romeIsPopupVisible = true;
      });
      return true;
    }

    if (urlString.isNotEmpty && !_romeIsAboutBlankUrl(urlString)) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(urlString)),
        );
      } catch (e) {
        print('WERLOG: popup inner window.open load error: $e url=$urlString');
      }
    }

    return false;
  }

  void _romeClosePopup() {
    setState(() {
      _romeIsPopupVisible = false;
      _romePopupUrl = null;
      _romePopupCurrentUrl = null;
      _romePopupCreateAction = null;
      _romePopupCanGoBack = false;
      RomePopupWebViewController = null;
    });
  }

  Future<void> _romeClosePopupAndNotifyParent({
    String reason = 'closed_by_user',
  }) async {
    try {
      await RomeWebViewController?.evaluateJavascript(
        source: '''
          try {
            window.dispatchEvent(new MessageEvent('message', {
              data: ${jsonEncode({
          'type': 'ncup_popup_closed',
          'reason': reason,
        })},
              origin: window.location.origin
            }));
          } catch(e) {
            console.log('ncup popup close notify failed', e);
          }
        ''',
      );
    } catch (e) {
      print('WERLOG: closePopup notify parent error: $e');
    }
    _romeClosePopup();
  }

  Future<void> _romeRefreshPopupCanGoBack() async {
    final InAppWebViewController? c = RomePopupWebViewController;
    if (c == null) {
      if (_romePopupCanGoBack && mounted) {
        setState(() {
          _romePopupCanGoBack = false;
        });
      }
      return;
    }
    try {
      final bool can = await c.canGoBack();
      if (!mounted) return;
      if (can != _romePopupCanGoBack) {
        setState(() {
          _romePopupCanGoBack = can;
        });
      }
    } catch (e) {
      print('WERLOG: _romeRefreshPopupCanGoBack error: $e');
    }
  }

  Future<void> _romeHandlePopupBackPressed() async {
    final InAppWebViewController? c = RomePopupWebViewController;
    if (c == null) {
      _romeClosePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _romeRefreshPopupCanGoBack();
        });
      } else {
        await _romeClosePopupAndNotifyParent(reason: 'popup_back_no_history');
      }
    } catch (e) {
      print('WERLOG: _romeHandlePopupBackPressed error: $e');
      _romeClosePopup();
    }
  }

  bool _romeIsCurrentPopupInWhitelist() {
    if (!_romeIsPopupVisible) return false;
    final String popupUrlForCheck = _romePopupCurrentUrl ?? _romePopupUrl ?? '';
    return _romeMatchesButtonWhitelist(popupUrlForCheck);
  }

  Widget _romeBuildPopupWebView() {
    final bool popupInWhitelist = _romeIsCurrentPopupInWhitelist();

    final bool showBackArrow = !popupInWhitelist && _romePopupCanGoBack;
    final bool showCloseButton = !popupInWhitelist && !_romePopupCanGoBack;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            if (!popupInWhitelist) ...[
              SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black,
                  child: Row(
                    children: [
                      if (showBackArrow)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: _romeHandlePopupBackPressed,
                        )
                      else if (showCloseButton)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            _romeClosePopupAndNotifyParent(reason: 'close_button');
                          },
                        ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white24),
            ],
            Expanded(
              child: InAppWebView(
                windowId: _romePopupCreateAction?.windowId,
                initialUrlRequest:
                (_romePopupCreateAction?.windowId == null) && _romePopupUrl != null
                    ? URLRequest(url: WebUri(_romePopupUrl!))
                    : null,
                initialSettings: _romePopupWebViewSettings(),
                onWebViewCreated:
                    (InAppWebViewController popupController) async {
                  RomePopupWebViewController = popupController;

                  print(
                    'WERLOG: popup created '
                        'windowId=${_romePopupCreateAction?.windowId} '
                        'initialUrl=${_romePopupUrl ?? _romePopupCreateAction?.request.url}',
                  );

                  final String popupInitUrl =
                      _romePopupUrl ?? _romePopupCreateAction?.request.url?.toString() ?? '';
                  if (popupInitUrl.isNotEmpty) {
                    final Uri? popupUri = Uri.tryParse(popupInitUrl);
                    if (popupUri != null && _romeIsGoogleUrl(popupUri)) {
                      await _romeApplyGoogleUserAgentForPopup();
                    }
                  }

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupLocalStorageSetItem',
                    callback: (List<dynamic> args) async {
                      try {
                        if (args.isEmpty) return null;
                        final dynamic raw = args.first;
                        if (raw is Map) {
                          final String key = raw['key']?.toString() ?? '';
                          final String value = raw['value']?.toString() ?? '';
                          if (key.isNotEmpty) {
                            final SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                            await prefs.setString(key, value);
                            RomeLoggerService().RomeLogInfo(
                                'NcupLocalStorageSetItem (popup): saved key="$key" len=${value.length}');
                          }
                        }
                      } catch (e, st) {
                        RomeLoggerService().RomeLogError(
                            'NcupLocalStorageSetItem popup handler error: $e\n$st');
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupCheckoutAction',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupCheckoutAction args=$args');
                      if (args.isNotEmpty) {
                        await _romeHandleCheckoutAction(args.first);
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupPostMessage',
                    callback: (List<dynamic> args) async {
                      print('WERLOG: POPUP NcupPostMessage args=$args');
                      if (args.isNotEmpty) {
                        final dynamic first = args.first;
                        if (first is Map && first['data'] != null) {
                          await _romeHandleCheckoutAction(first['data']);
                        } else {
                          await _romeHandleCheckoutAction(first);
                        }
                      }
                      return null;
                    },
                  );

                  popupController.addJavaScriptHandler(
                    handlerName: 'NcupJSLogger',
                    callback: (List<dynamic> args) {
                      print('WERLOG: POPUP JS error payload: $args');
                      return null;
                    },
                  );
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStart: (controller, uri) async {
                  print('WERLOG: popup onLoadStart url=$uri');
                  if (uri != null && !_romeIsAboutBlankUri(uri)) {
                    if (_romeIsGoogleUrl(uri)) {
                      await _romeApplyGoogleUserAgentForPopup();
                    }

                    if (mounted) {
                      setState(() {
                        _romePopupCurrentUrl = uri.toString();
                        if (_romeBackButtonHiddenAfterTap) {
                          _romeBackButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _romeRefreshPopupCanGoBack();
                },
                onLoadStop: (controller, uri) async {
                  print('WERLOG: popup onLoadStop url=$uri');
                  if (uri != null && !_romeIsAboutBlankUri(uri)) {
                    if (mounted) {
                      setState(() {
                        _romePopupCurrentUrl = uri.toString();
                      });
                    }
                  }
                  if (!_romeIsAboutBlankUri(uri)) {
                    _romeScheduleSafeInstall(controller, label: 'popup');
                  }
                  _romeRefreshPopupCanGoBack();
                },
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  if (url != null && !_romeIsAboutBlankUri(url)) {
                    if (mounted) {
                      setState(() {
                        _romePopupCurrentUrl = url.toString();
                        if (_romeBackButtonHiddenAfterTap) {
                          _romeBackButtonHiddenAfterTap = false;
                        }
                      });
                    }
                  }
                  _romeRefreshPopupCanGoBack();
                },
                onCreateWindow: _romeOnPopupCreateWindowHandler,
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction navigationAction,
                    ) async {
                  final Uri? uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_romeIsAboutBlankUri(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  if (_romeIsGoogleUrl(uri)) {
                    await _romeApplyGoogleUserAgentForPopup();
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (RomeIsBareEmail(uri)) {
                    final Uri mailto = RomeToMailto(uri);
                    await RomeOpenMailExternal(mailto);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await RomeOpenMailExternal(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (RomeIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          RomeIsBankDomain(uri))) {
                    await RomeOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    print(
                      'WERLOG: popup blocked non-http/https scheme=$scheme url=$uri',
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  print('WERLOG: popup onCloseWindow');
                  _romeClosePopup();
                },
                onLoadError: (controller, uri, code, message) async {
                  print(
                    'WERLOG: popup onLoadError url=$uri code=$code msg=$message',
                  );
                },
                onReceivedError: (controller, request, error) async {
                  print(
                    'WERLOG: popup onReceivedError '
                        'url=${request.url} '
                        'type=${error.type} '
                        'desc=${error.description}',
                  );
                },
                onReceivedHttpError:
                    (controller, request, errorResponse) async {
                  print(
                    'WERLOG: popup onReceivedHttpError '
                        'url=${request.url} '
                        'status=${errorResponse.statusCode} '
                        'reason=${errorResponse.reasonPhrase}',
                  );
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print(
                    'WERLOG: popup console: '
                        '${consoleMessage.messageLevel} ${consoleMessage.message}',
                  );
                },
                onDownloadStartRequest: (controller, req) async {
                  print(
                      'WERLOG: popup download for url=${req.url}, opening external');
                  await RomeOpenExternal(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    RomeBindNotificationTap();

    final Color bgColor =
    _romeSafeAreaEnabled ? _romeSafeAreaBackgroundColor : Colors.black;

    final Widget webView = Stack(
      children: <Widget>[
        if (RomeCoverVisible)
          const Center(child: ArenaScreen())
        else
          Container(
            color: bgColor,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(RomeWebViewKeyCounter),
                  initialSettings: _romeMainWebViewSettings(),
                  initialUrlRequest: URLRequest(
                    url: WebUri(RomeHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController controller) async {
                    RomeWebViewController = controller;
                    _romeCurrentUrl = RomeHomeUrl;

                    RomeBosunInstance ??= RomeBosunViewModel(
                      RomeDeviceProfileInstance: RomeDeviceProfileInstance,
                      RomeAnalyticsSpyInstance: RomeAnalyticsSpyInstance,
                    );

                    RomeCourier ??= RomeCourierService(
                      RomeBosun: RomeBosunInstance!,
                      RomeGetWebViewController: () => RomeWebViewController,
                    );

                    try {
                      final ua = await controller.evaluateJavascript(
                        source: "navigator.userAgent",
                      );
                      if (ua is String && ua.trim().isNotEmpty) {
                        _romeBaseUserAgent = ua.trim();
                        _romeCurrentUserAgent = _romeBaseUserAgent!;
                        RomeDeviceProfileInstance.RomeBaseUserAgent =
                            _romeBaseUserAgent;
                        RomeLoggerService().RomeLogInfo(
                            'Initial WebView User-Agent: $_romeBaseUserAgent');
                        print(
                            '[UA] INITIAL WEBVIEW USER AGENT: $_romeBaseUserAgent');
                      }
                    } catch (e) {
                      RomeLoggerService().RomeLogWarn(
                          'Failed to read navigator.userAgent on create: $e');
                    }

                    await _romeApplyNormalUserAgentIfNeeded();

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupLocalStorageSetItem',
                      callback: (List<dynamic> args) async {
                        try {
                          if (args.isEmpty) return null;
                          final dynamic raw = args.first;
                          if (raw is Map) {
                            final String key =
                                raw['key']?.toString() ?? '';
                            final String value =
                                raw['value']?.toString() ?? '';
                            if (key.isNotEmpty) {
                              final SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                              await prefs.setString(key, value);
                              RomeLoggerService().RomeLogInfo(
                                  'NcupLocalStorageSetItem (main): saved key="$key" len=${value.length}');
                            }
                          }
                        } catch (e, st) {
                          RomeLoggerService().RomeLogError(
                              'NcupLocalStorageSetItem main handler error: $e\n$st');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> args) async {
                        if (args.isEmpty) return null;

                        print("Get Data server $args");

                        try {
                          dynamic first = args[0];

                          if (first is List && first.isNotEmpty) {
                            first = first.first;
                          }

                          final bool handled =
                          await _romeHandleCheckoutAction(first);
                          if (handled) {}

                          if (first is Map) {
                            final Map<dynamic, dynamic> root = first;

                            if (root['savedata'] != null) {
                              RomeHandleServerSavedata(
                                  root['savedata'].toString());
                              await _romeHandleCheckoutAction(root['savedata']);
                            }

                            _romeUpdateExtraDataFromServerPayload(root);
                            _romeUpdateSafeAreaFromServerPayload(root);
                            await _romeUpdateUserAgentFromServerPayload(root);

                            await _romeApplyNormalUserAgentIfNeeded();

                            try {
                              if (!_romeLoadedJsExecutedOnce) {
                                final dynamic adataRaw = root['adata'];
                                if (adataRaw is Map) {
                                  final Map adata = adataRaw;
                                  final dynamic loadedJsRaw =
                                  adata['loadedjs'];
                                  if (loadedJsRaw != null) {
                                    final String loadedJs =
                                    loadedJsRaw.toString().trim();
                                    if (loadedJs.isNotEmpty) {
                                      _romePendingLoadedJs = loadedJs;
                                      RomeLoggerService().RomeLogInfo(
                                        'loadedjs received, will execute ONCE after 6 seconds',
                                      );

                                      Future<void>.delayed(
                                        const Duration(seconds: 6),
                                            () async {
                                          if (!mounted) return;
                                          if (_romeLoadedJsExecutedOnce) {
                                            RomeLoggerService()
                                                .RomeLogInfo(
                                                'Skipping loadedjs: already executed once');
                                            return;
                                          }
                                          if (RomeWebViewController ==
                                              null) {
                                            RomeLoggerService()
                                                .RomeLogWarn(
                                                'Skipping loadedjs execution: controller is null');
                                            return;
                                          }
                                          final String? jsToRun =
                                              _romePendingLoadedJs;
                                          if (jsToRun == null ||
                                              jsToRun.isEmpty) {
                                            return;
                                          }
                                          RomeLoggerService().RomeLogInfo(
                                              'Executing loadedjs from server payload (ONCE, delayed 6s)');
                                          try {
                                            await RomeWebViewController
                                                ?.evaluateJavascript(
                                              source: jsToRun,
                                            );
                                            _romeLoadedJsExecutedOnce = true;
                                          } catch (e, st) {
                                            RomeLoggerService().RomeLogError(
                                                'Error executing delayed loadedjs: $e\n$st');
                                          }
                                        },
                                      );
                                    }
                                  }
                                }
                              } else {
                                RomeLoggerService().RomeLogInfo(
                                    'loadedjs ignored: already executed once earlier');
                              }
                            } catch (e, st) {
                              RomeLoggerService().RomeLogError(
                                  'Error scheduling loadedjs: $e\n$st');
                            }
                          }
                        } catch (e, st) {
                          print('onServerResponse error: $e\n$st');
                        }

                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupCheckoutAction',
                      callback: (List<dynamic> args) async {
                        try {
                          print('WERLOG: MAIN NcupCheckoutAction args=$args');
                          if (args.isNotEmpty) {
                            await _romeHandleCheckoutAction(args.first);
                          }
                        } catch (e) {
                          print(
                              'WERLOG: MAIN NcupCheckoutAction error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupJSLogger',
                      callback: (List<dynamic> args) {
                        try {
                          final dynamic payload =
                          args.isNotEmpty ? args.first : null;
                          print('WERLOG: MAIN JS error payload: $payload');
                        } catch (e) {
                          print('WERLOG: NcupJSLogger handler error: $e');
                        }
                        return null;
                      },
                    );

                    controller.addJavaScriptHandler(
                      handlerName: 'NcupPostMessage',
                      callback: (List<dynamic> args) async {
                        try {
                          print('WERLOG: MAIN NcupPostMessage args=$args');
                          if (args.isNotEmpty) {
                            final dynamic first = args.first;
                            if (first is Map && first['data'] != null) {
                              await _romeHandleCheckoutAction(first['data']);
                            } else {
                              await _romeHandleCheckoutAction(first);
                            }
                          }
                        } catch (e) {
                          print(
                              'WERLOG: NcupPostMessage handler error: $e');
                        }
                        return null;
                      },
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  onLoadStart:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      RomeStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? romeViewUri = uri;
                    if (romeViewUri != null) {
                      _romeCurrentUrl = romeViewUri.toString();

                      await _romeSwitchUserAgentForUrl(romeViewUri);

                      await _romeUpdateBackButtonVisibility();

                      if (RomeIsBareEmail(romeViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        final Uri romeMailto = RomeToMailto(romeViewUri);
                        await RomeOpenMailExternal(romeMailto);
                        return;
                      }

                      final String romeScheme =
                      romeViewUri.scheme.toLowerCase();

                      if (romeScheme == 'mailto') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await RomeOpenMailExternal(romeViewUri);
                        return;
                      }

                      if (RomeIsBankScheme(romeViewUri)) {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                        await RomeOpenBank(romeViewUri);
                        return;
                      }

                      if (romeScheme != 'http' && romeScheme != 'https') {
                        try {
                          await controller.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController controller,
                      Uri? uri,
                      int code,
                      String message,
                      ) async {
                    final int romeNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String romeEvent =
                        'InAppWebViewError(code=$code, message=$message)';

                    await RomePostStat(
                      event: romeEvent,
                      timeStart: romeNow,
                      timeFinish: romeNow,
                      url: uri?.toString() ?? '',
                      appSid: RomeAnalyticsSpyInstance.RomeAppsFlyerUid,
                      firstPageLoadTs: RomeFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController controller,
                      WebResourceRequest request,
                      WebResourceError error,
                      ) async {
                    final int romeNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String romeDescription =
                    (error.description ?? '').toString();
                    final String romeEvent =
                        'WebResourceError(code=$error, message=$romeDescription)';

                    await RomePostStat(
                      event: romeEvent,
                      timeStart: romeNow,
                      timeFinish: romeNow,
                      url: request.url?.toString() ?? '',
                      appSid: RomeAnalyticsSpyInstance.RomeAppsFlyerUid,
                      firstPageLoadTs: RomeFirstPageTimestamp,
                    );
                  },
                  onLoadStop:
                      (InAppWebViewController controller, Uri? uri) async {
                    setState(() {
                      RomeCurrentUrl = uri.toString();
                      _romeCurrentUrl = RomeCurrentUrl;
                    });

                    if (uri != null) {
                      await _romeSwitchUserAgentForUrl(uri);
                    }

                    if (!_romeIsAboutBlankUri(uri)) {
                      _romeScheduleSafeInstall(controller, label: 'parent');
                    }

                    await romeDebugPrintCurrentUserAgent();

                    await _romeSendAllDataToPageTwice();
                    await _romeUpdateBackButtonVisibility();

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        RomeSendLoadedOnce(
                          url: RomeCurrentUrl.toString(),
                          timestart: RomeStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  onUpdateVisitedHistory:
                      (controller, url, isReload) async {
                    if (url != null && !_romeIsAboutBlankUri(url)) {
                      _romeCurrentUrl = url.toString();
                      await _romeUpdateBackButtonVisibility();
                      await _romeSwitchUserAgentForUrl(url);
                    }
                  },
                  shouldOverrideUrlLoading:
                      (InAppWebViewController controller,
                      NavigationAction action) async {
                    final Uri? romeUri = action.request.url;
                    if (romeUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    _romeCurrentUrl = romeUri.toString();
                    await _romeUpdateBackButtonVisibility();

                    if (_romeIsAboutBlankUri(romeUri)) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (_romeIsGoogleUrl(romeUri)) {
                      _romeIsCurrentlyOnGoogle = true;
                      await _romeApplyGoogleUserAgent();
                      return NavigationActionPolicy.ALLOW;
                    } else {
                      if (_romeIsCurrentlyOnGoogle) {
                        _romeIsCurrentlyOnGoogle = false;
                      }
                      await _romeApplyNormalUserAgentIfNeeded();
                    }

                    if (RomeIsBareEmail(romeUri)) {
                      final Uri romeMailto = RomeToMailto(romeUri);
                      await RomeOpenMailExternal(romeMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String romeScheme = romeUri.scheme.toLowerCase();

                    if (romeScheme == 'mailto') {
                      await RomeOpenMailExternal(romeUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (RomeIsBankScheme(romeUri)) {
                      await RomeOpenBank(romeUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if ((romeScheme == 'http' || romeScheme == 'https') &&
                        RomeIsBankDomain(romeUri)) {
                      await RomeOpenBank(romeUri);

                      if (_romeIsAdobeRedirect(romeUri)) {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  RomeAdobeRedirectScreen(uri: romeUri),
                            ),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (romeScheme == 'tel') {
                      await launchUrl(
                        romeUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String host = romeUri.host.toLowerCase();
                    final bool romeIsSocial =
                        host.endsWith('facebook.com') ||
                            host.endsWith('instagram.com') ||
                            host.endsWith('twitter.com') ||
                            host.endsWith('x.com');

                    if (romeIsSocial) {
                      await RomeOpenExternal(romeUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (RomeIsPlatformLink(romeUri)) {
                      final Uri romeWebUri =
                      RomeHttpizePlatformUri(romeUri);
                      await RomeOpenExternal(romeWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (romeScheme != 'http' && romeScheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: _romeOnCreateWindowHandler,
                  onCloseWindow: (controller) {
                    print('WERLOG: MAIN onCloseWindow');
                  },
                  onDownloadStartRequest: (
                      InAppWebViewController controller,
                      DownloadStartRequest req,
                      ) async {
                    await RomeOpenExternal(req.url);
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    print(
                      'WERLOG: MAIN console: '
                          '${consoleMessage.messageLevel} ${consoleMessage.message}',
                    );
                  },
                ),
                Visibility(
                  visible: !RomeVeilVisible,
                  child: const Center(child:ArenaScreen()),
                ),
                if (_romeIsPopupVisible &&
                    (_romePopupUrl != null || _romePopupCreateAction != null))
                  _romeBuildPopupWebView(),
              ],
            ),
          ),
      ],
    );

    final bool popupInWhitelist = _romeIsCurrentPopupInWhitelist();

    final bool whitelistMatch =
        (!_romeIsPopupVisible && _romeShowBackButton) || popupInWhitelist;

    final bool shouldShowTopBackBar =
        whitelistMatch && !_romeBackButtonHiddenAfterTap;

    final Color topBarColor =
    _romeSafeAreaEnabled ? _romeSafeAreaBackgroundColor : Colors.black;

    final Widget topBackBar = shouldShowTopBackBar
        ? Container(
      color: topBarColor,
      padding: const EdgeInsets.only(left: 4, right: 4),
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _romeHandleBackButtonPressed,
          ),
        ],
      ),
    )
        : const SizedBox.shrink();

    final Widget fullScreen = Column(
      children: [
        topBackBar,
        Expanded(child: webView),
      ],
    );

    final Widget body = _romeSafeAreaEnabled
        ? SafeArea(
      child: fullScreen,
    )
        : fullScreen;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SizedBox.expand(
          child: ColoredBox(
            color: bgColor,
            child: body,
          ),
        ),
      ),
    );
  }

  bool _romeIsAdobeRedirect(Uri uri) {
    final String host = uri.host.toLowerCase();
    return host == 'c00.adobe.com';
  }
}

// ---------------------- Экран для c00.adobe.com ----------------------

class RomeAdobeRedirectScreen extends StatelessWidget {
  final Uri uri;

  const RomeAdobeRedirectScreen({super.key, required this.uri});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF111111),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Go to the App Store and download the app.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                ),
              ),
              SizedBox(height: 24),
              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(RomeFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tz_data.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RomeHall(),
    ),
  );
}