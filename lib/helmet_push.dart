import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as RomeMath;
import 'dart:ui';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle, SystemChrome;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as RomeTimezoneData;
import 'package:timezone/timezone.dart' as RomeTimezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show RomeMafiaHarbor, RomeCaptainHarbor, RomeBillHarbor;

// ============================================================================
// ROME инфраструктура (бывшая Dress Retro инфраструктура)
// ============================================================================

class RomeLogger {
  const RomeLogger();

  void RomeLogInfo(Object RomeMessage) =>
      debugPrint('[DressRetroLogger] $RomeMessage');

  void RomeLogWarn(Object RomeMessage) =>
      debugPrint('[DressRetroLogger/WARN] $RomeMessage');

  void RomeLogError(Object RomeMessage) =>
      debugPrint('[DressRetroLogger/ERR] $RomeMessage');
}

class RomeVault {
  static final RomeVault RomeSharedInstance = RomeVault._RomeInternalConstructor();
  RomeVault._RomeInternalConstructor();
  factory RomeVault() => RomeSharedInstance;

  final RomeLogger RomeLoggerInstance = const RomeLogger();
}

// ============================================================================
// Константы (статистика/кеш) — строки в кавычках не меняем
// ============================================================================

const String RomeLoadedOnceKey = 'wheel_loaded_once';
const String RomeStatEndpoint = 'https://getgame.portalroullete.bar/stat';
const String RomeCachedFcmKey = 'wheel_cached_fcm';

// НОВОЕ: ключи для сохранения SafeArea и цвета в SharedPreferences
const String RomeSafeAreaEnabledKey = 'safearea_enabled';
const String RomeSafeAreaColorKey = 'safearea_color';

// ---------------- Bank constants (из первого main.dart) ----------------

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
// Утилиты: RomeKit (бывший DressRetroKit)
// ============================================================================

class RomeKit {
  static bool RomeLooksLikeBareMail(Uri RomeUri) {
    final String RomeScheme = RomeUri.scheme;
    if (RomeScheme.isNotEmpty) return false;
    final String RomeRaw = RomeUri.toString();
    return RomeRaw.contains('@') && !RomeRaw.contains(' ');
  }

  static Uri RomeToMailto(Uri RomeUri) {
    final String RomeFull = RomeUri.toString();
    final List<String> RomeBits = RomeFull.split('?');
    final String RomeWho = RomeBits.first;
    final Map<String, String> RomeQuery =
    RomeBits.length > 1 ? Uri.splitQueryString(RomeBits[1]) : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: RomeWho,
      queryParameters: RomeQuery.isEmpty ? null : RomeQuery,
    );
  }

  static Uri RomeGmailize(Uri RomeMailUri) {
    final Map<String, String> RomeQp = RomeMailUri.queryParameters;
    final Map<String, String> RomeParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (RomeMailUri.path.isNotEmpty) 'to': RomeMailUri.path,
      if ((RomeQp['subject'] ?? '').isNotEmpty) 'su': RomeQp['subject']!,
      if ((RomeQp['body'] ?? '').isNotEmpty) 'body': RomeQp['body']!,
      if ((RomeQp['cc'] ?? '').isNotEmpty) 'cc': RomeQp['cc']!,
      if ((RomeQp['bcc'] ?? '').isNotEmpty) 'bcc': RomeQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', RomeParams);
  }

  static String RomeDigitsOnly(String RomeSource) =>
      RomeSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия ссылок: RomeLinker (бывший DressRetroLinker)
// ============================================================================

class RomeLinker {
  static Future<bool> RomeOpen(Uri RomeUri) async {
    try {
      if (await launchUrl(
        RomeUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        RomeUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (RomeError) {
      debugPrint('DressRetroLinker error: $RomeError; url=$RomeUri');
      try {
        return await launchUrl(
          RomeUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// Bank helpers (из первого main.dart)
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
    debugPrint('RomeOpenBank error: $e; url=$uri');
  }
  return false;
}

// ============================================================================
// FCM Background Handler
// ============================================================================

@pragma('vm:entry-point')
Future<void> RomeFcmBackgroundHandler(RemoteMessage RomeMessage) async {
  debugPrint("Spin ID: ${RomeMessage.messageId}");
  debugPrint("Spin Data: ${RomeMessage.data}");
}

// ============================================================================
// RomeDeviceProfile (бывший DressRetroDeviceProfile)
// ============================================================================

class RomeDeviceProfile {
  String? RomeDeviceId;
  String? RomeSessionId = 'wheel-one-off';
  String? RomePlatformKind;
  String? RomeOsBuild;
  String? RomeAppVersion;
  String? RomeLocaleCode;
  String? RomeTimezoneName;
  bool RomePushEnabled = true;

  // Новый UA из WebView
  String? RomeBaseUserAgent;

  // Для SafeArea
  bool RomeSafeAreaEnabled = false;
  String? RomeSafeAreaColor;

  Future<void> RomeInitialize() async {
    try {
      RomeTimezoneData.initializeTimeZones();
    } catch (_) {}

    final DeviceInfoPlugin RomeInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo RomeAndroidInfo =
      await RomeInfoPlugin.androidInfo;
      RomeDeviceId = RomeAndroidInfo.id;
      RomePlatformKind = 'android';
      RomeOsBuild = RomeAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo RomeIosInfo = await RomeInfoPlugin.iosInfo;
      RomeDeviceId = RomeIosInfo.identifierForVendor;
      RomePlatformKind = 'ios';
      RomeOsBuild = RomeIosInfo.systemVersion;
    }

    final PackageInfo RomePackageInfo = await PackageInfo.fromPlatform();
    RomeAppVersion = RomePackageInfo.version;
    RomeLocaleCode = Platform.localeName.split('_').first;
    RomeTimezoneName = RomeTimezone.local.name;
    RomeSessionId = 'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> RomeAsMap({String? RomeFcmToken}) => <String, dynamic>{
    'fcm_token': RomeFcmToken ?? 'missing_token',
    'device_id': RomeDeviceId ?? 'missing_id',
    'app_name': 'joiler',
    'instance_id': RomeSessionId ?? 'missing_session',
    'platform': RomePlatformKind ?? 'missing_system',
    'os_version': RomeOsBuild ?? 'missing_build',
    'app_version': RomeAppVersion ?? 'missing_app',
    'language': RomeLocaleCode ?? 'en',
    'timezone': RomeTimezoneName ?? 'UTC',
    'push_enabled': RomePushEnabled,
    'fthcashier': 'true',
    'safearea': RomeSafeAreaEnabled,
    'safearea_color': RomeSafeAreaColor ?? '',
    'base_ua': RomeBaseUserAgent ?? '',
  };
}

// ============================================================================
// AppsFlyer шпион: RomeSpy (бывший DressRetroSpy)
// ============================================================================

class RomeSpy {
  AppsFlyerOptions? RomeOptions;
  AppsflyerSdk? RomeSdk;

  String RomeAppsFlyerUid = '';
  String RomeAppsFlyerData = '';

  void RomeStart({VoidCallback? RomeOnUpdate}) {
    final AppsFlyerOptions RomeOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    RomeOptions = RomeOpts;
    RomeSdk = AppsflyerSdk(RomeOpts);

    RomeSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    RomeSdk?.startSDK(
      onSuccess: () =>
          RomeVault().RomeLoggerInstance.RomeLogInfo('WheelSpy started'),
      onError: (RomeCode, RomeMsg) => RomeVault()
          .RomeLoggerInstance
          .RomeLogError('WheelSpy error $RomeCode: $RomeMsg'),
    );

    RomeSdk?.onInstallConversionData((RomeValue) {
      RomeAppsFlyerData = RomeValue.toString();
      RomeOnUpdate?.call();
    });

    RomeSdk?.getAppsFlyerUID().then((RomeValue) {
      RomeAppsFlyerUid = RomeValue.toString();
      RomeOnUpdate?.call();
    });
  }
}

// ============================================================================
// Мост для FCM токена: RomeFcmBridge (бывший DressRetroFcmBridge)
// ============================================================================

class RomeFcmBridge {
  final RomeLogger RomeLog = const RomeLogger();
  String? RomeToken;
  final List<void Function(String)> RomeWaiters = <void Function(String)>[];

  String? get RomeCurrentToken => RomeToken;

  RomeFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall RomeCall) async {
      if (RomeCall.method == 'setToken') {
        final String RomeTokenString = RomeCall.arguments as String;
        if (RomeTokenString.isNotEmpty) {
          RomeSetToken(RomeTokenString);
        }
      }
    });

    RomeRestoreToken();
  }

  Future<void> RomeRestoreToken() async {
    try {
      final SharedPreferences RomePrefs = await SharedPreferences.getInstance();
      final String? RomeCached = RomePrefs.getString(RomeCachedFcmKey);
      if (RomeCached != null && RomeCached.isNotEmpty) {
        RomeSetToken(RomeCached, RomeNotify: false);
      }
    } catch (_) {}
  }

  Future<void> RomePersistToken(String RomeNewToken) async {
    try {
      final SharedPreferences RomePrefs = await SharedPreferences.getInstance();
      await RomePrefs.setString(RomeCachedFcmKey, RomeNewToken);
    } catch (_) {}
  }

  void RomeSetToken(
      String RomeNewToken, {
        bool RomeNotify = true,
      }) {
    RomeToken = RomeNewToken;
    RomePersistToken(RomeNewToken);
    if (RomeNotify) {
      for (final void Function(String) RomeCallback
      in List<void Function(String)>.from(RomeWaiters)) {
        try {
          RomeCallback(RomeNewToken);
        } catch (RomeErr) {
          RomeLog.RomeLogWarn('fcm waiter error: $RomeErr');
        }
      }
      RomeWaiters.clear();
    }
  }

  Future<void> RomeWaitForToken(
      Function(String RomeTokenValue) RomeOnToken,
      ) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((RomeToken ?? '').isNotEmpty) {
        RomeOnToken(RomeToken!);
        return;
      }

      RomeWaiters.add(RomeOnToken);
    } catch (RomeErr) {
      RomeLog.RomeLogError('wheelWaitToken error: $RomeErr');
    }
  }
}

// ============================================================================
// RomeLoader (новый лоадер)
// ============================================================================

class RomeLoader extends StatefulWidget {
  const RomeLoader({Key? key}) : super(key: key);

  @override
  State<RomeLoader> createState() => _RomeLoaderState();
}

class _RomeLoaderState extends State<RomeLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController RomeController;

  static const Color RomeBackgroundColor = Color(0xFF05071B);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    RomeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    RomeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RomeBackgroundColor,
      child: AnimatedBuilder(
        animation: RomeController,
        builder: (BuildContext context, Widget? child) {
          final double RomePhase = RomeController.value * 2 * RomeMath.pi;
          return CustomPaint(
            painter: RomeLoaderPainter(
              RomePhase: RomePhase,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class RomeLoaderPainter extends CustomPainter {
  final double RomePhase;

  RomeLoaderPainter({
    required this.RomePhase,
  });

  @override
  void paint(Canvas RomeCanvas, Size RomeSize) {
    final double RomeWidth = RomeSize.width;
    final double RomeHeight = RomeSize.height;

    final Paint RomeBackgroundPaint = Paint()
      ..color = const Color(0xFF05071B)
      ..style = PaintingStyle.fill;
    RomeCanvas.drawRect(Offset.zero & RomeSize, RomeBackgroundPaint);

    final double RomePulse = (RomeMath.sin(RomePhase) + 1) / 2;

    final Paint RomeCirclePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.red.withOpacity(0.14 + 0.16 * RomePulse),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(RomeWidth * 0.5, RomeHeight * 0.45),
          radius: RomeHeight * (0.4 + 0.15 * RomePulse),
        ),
      );

    RomeCanvas.drawCircle(
      Offset(RomeWidth * 0.5, RomeHeight * 0.45),
      RomeHeight * (0.4 + 0.15 * RomePulse),
      RomeCirclePaint,
    );

    final Paint RomeOuterPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: <Color>[
          Colors.redAccent.withOpacity(0.10 + 0.10 * (1 - RomePulse)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(RomeWidth * 0.5, RomeHeight * 0.45),
          radius: RomeHeight * (0.55 + 0.10 * (1 - RomePulse)),
        ),
      );
    RomeCanvas.drawCircle(
      Offset(RomeWidth * 0.5, RomeHeight * 0.45),
      RomeHeight * (0.55 + 0.10 * (1 - RomePulse)),
      RomeOuterPaint,
    );

    final double RomeBaseSize = RomeWidth * 0.35;
    final double RomeFontSize =
        RomeBaseSize + RomePulse * (RomeBaseSize * 0.15);

    const String RomeLetter = 'N';
    const String RomeWord = 'CUP';

    final TextPainter RomeLetterPainter = TextPainter(
      text: TextSpan(
        text: RomeLetter,
        style: TextStyle(
          fontSize: RomeFontSize,
          fontWeight: FontWeight.w900,
          color: Colors.red.shade600,
          letterSpacing: 4,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.8),
              blurRadius: 22 + 18 * RomePulse,
              offset: const Offset(0, 0),
            ),
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: RomeWidth);

    final double RomeLetterX = (RomeWidth - RomeLetterPainter.width) / 2;
    final double RomeLetterY = (RomeHeight - RomeLetterPainter.height) / 2;

    final Offset RomeLetterOffset = Offset(RomeLetterX, RomeLetterY);

    final Rect RomeLetterRect = Rect.fromCenter(
      center: Offset(RomeWidth / 2, RomeHeight / 2),
      width: RomeLetterPainter.width * 1.4,
      height: RomeLetterPainter.height * 1.6,
    );

    final Paint RomeGlowPaint = Paint()
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        28 + 24 * RomePulse,
      )
      ..color = Colors.red.withOpacity(0.7 + 0.2 * RomePulse);

    RomeCanvas.saveLayer(RomeLetterRect, RomeGlowPaint);
    RomeLetterPainter.paint(RomeCanvas, RomeLetterOffset);
    RomeCanvas.restore();

    RomeLetterPainter.paint(RomeCanvas, RomeLetterOffset);

    final double RomeCupFontSize = RomeWidth * 0.11;

    final TextPainter RomeCupPainterReal = TextPainter(
      text: TextSpan(
        text: RomeWord,
        style: TextStyle(
          fontSize: RomeCupFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.red.shade100.withOpacity(0.95),
          letterSpacing: 5,
          shadows: <Shadow>[
            Shadow(
              color: Colors.redAccent.withOpacity(0.7),
              blurRadius: 12 + 10 * RomePulse,
              offset: const Offset(0, 0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: RomeWidth);

    final double RomeCupX = (RomeWidth - RomeCupPainterReal.width) / 2;
    final double RomeCupY =
        RomeLetterY + RomeLetterPainter.height + RomeHeight * 0.03;

    final Offset RomeCupOffset = Offset(RomeCupX, RomeCupY);
    RomeCupPainterReal.paint(RomeCanvas, RomeCupOffset);
  }

  @override
  bool shouldRepaint(covariant RomeLoaderPainter RomeOldDelegate) =>
      RomeOldDelegate.RomePhase != RomePhase;
}

// ============================================================================
// Статистика (RomeFinalUrl / RomePostStat) — строки не меняем
// ============================================================================

Future<String> RomeFinalUrl(
    String RomeStartUrl, {
      int RomeMaxHops = 10,
    }) async {
  final HttpClient RomeClient = HttpClient();

  try {
    Uri RomeCurrentUri = Uri.parse(RomeStartUrl);

    for (int RomeI = 0; RomeI < RomeMaxHops; RomeI++) {
      final HttpClientRequest RomeRequest =
      await RomeClient.getUrl(RomeCurrentUri);
      RomeRequest.followRedirects = false;
      final HttpClientResponse RomeResponse = await RomeRequest.close();

      if (RomeResponse.isRedirect) {
        final String? RomeLoc =
        RomeResponse.headers.value(HttpHeaders.locationHeader);
        if (RomeLoc == null || RomeLoc.isEmpty) break;

        final Uri RomeNextUri = Uri.parse(RomeLoc);
        RomeCurrentUri = RomeNextUri.hasScheme
            ? RomeNextUri
            : RomeCurrentUri.resolveUri(RomeNextUri);
        continue;
      }

      return RomeCurrentUri.toString();
    }

    return RomeCurrentUri.toString();
  } catch (RomeError) {
    debugPrint('wheelFinalUrl error: $RomeError');
    return RomeStartUrl;
  } finally {
    RomeClient.close(force: true);
  }
}

Future<void> RomePostStat({
  required String RomeEvent,
  required int RomeTimeStart,
  required String RomeUrl,
  required int RomeTimeFinish,
  required String RomeAppSid,
  int? RomeFirstPageTs,
}) async {
  try {
    final String RomeResolvedUrl = await RomeFinalUrl(RomeUrl);
    final Map<String, dynamic> RomePayload = <String, dynamic>{
      'event': RomeEvent,
      'timestart': RomeTimeStart,
      'timefinsh': RomeTimeFinish,
      'url': RomeResolvedUrl,
      'appleID': '6755681349',
      'open_count': '$RomeAppSid/$RomeTimeStart',
    };

    debugPrint('wheelStat $RomePayload');

    final http.Response RomeResp = await http.post(
      Uri.parse('$RomeStatEndpoint/$RomeAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(RomePayload),
    );

    debugPrint('wheelStat resp=${RomeResp.statusCode} body=${RomeResp.body}');
  } catch (RomeError) {
    debugPrint('wheelPostStat error: $RomeError');
  }
}

// ============================================================================
// WebView-экран: RomeTableView (бывший DressRetroTableView)
// SafeArea + SafeArea color + localStorage подхватываются из SharedPreferences
// ============================================================================

class RomeTableView extends StatefulWidget with WidgetsBindingObserver {
  String RomeStartingUrl;
  RomeTableView(this.RomeStartingUrl, {super.key});

  @override
  State<RomeTableView> createState() => _RomeTableViewState(RomeStartingUrl);
}

class _RomeTableViewState extends State<RomeTableView>
    with WidgetsBindingObserver {
  _RomeTableViewState(this.RomeCurrentUrl);

  final RomeVault RomeVaultInstance = RomeVault();

  late InAppWebViewController RomeWebViewController;
  String? RomePushToken;
  final RomeDeviceProfile RomeDeviceProfileInstance = RomeDeviceProfile();
  final RomeSpy RomeSpyInstance = RomeSpy();

  bool RomeOverlayBusy = false;
  String RomeCurrentUrl;
  DateTime? RomeLastPausedAt;

  bool RomeLoadedOnceSent = false;
  int? RomeFirstPageTimestamp;
  int RomeStartLoadTimestamp = 0;

  // --------- Социальные / внешние хосты / схемы ---------

  final Set<String> RomeExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
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

  final Set<String> RomeExternalSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

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

  // --------- UserAgent + SafeArea ---------

  String? _romeBaseUserAgent;
  String _romeCurrentUserAgent = '';
  String? _romeServerUserAgent;
  bool _romeIsInGoogleAuth = false;

  bool _romeSafeAreaEnabled = false;
  Color _romeSafeAreaBackgroundColor = Colors.black;

  // --------- POPUP (window.open) ---------

  InAppWebViewController? _romePopupWebViewController;
  bool _romeIsPopupVisible = false;
  String? _romePopupUrl;
  CreateWindowAction? _romePopupCreateAction;
  bool _romePopupCanGoBack = false;
  String? _romePopupCurrentUrl;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(RomeFcmBackgroundHandler);

    RomeFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    // 1) SafeArea state (enabled + color) подхватываем из SharedPreferences
    _romeLoadSafeAreaFromPrefs();

    // 2) Push
    RomeInitPushAndGetToken();

    // 3) Профиль устройства -> localStorage + SharedPreferences (app_data)
    RomeDeviceProfileInstance.RomeInitialize().then((_) async {
      if (!mounted) return;
      await _romeUpdateLocalStorage();
    });

    // 4) FCM + AppsFlyer
    RomeWireForegroundPushHandlers();
    RomeBindPlatformNotificationTap();
    RomeSpyInstance.RomeStart(RomeOnUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState RomeState) {
    if (RomeState == AppLifecycleState.paused) {
      RomeLastPausedAt = DateTime.now();
    }
    if (RomeState == AppLifecycleState.resumed) {
      if (Platform.isIOS && RomeLastPausedAt != null) {
        final DateTime RomeNow = DateTime.now();
        final Duration RomeDrift = RomeNow.difference(RomeLastPausedAt!);
        if (RomeDrift > const Duration(minutes: 25)) {
          RomeForceReloadToLobby();
        }
      }
      RomeLastPausedAt = null;
    }
  }

  void RomeForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((Duration RomeDuration) {
      if (!mounted) return;
      // здесь можно вернуть в RomeMafiaHarbor/RomeCaptainHarbor/RomeBillHarbor при необходимости
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------

  void RomeWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage RomeMsg) {
      if (RomeMsg.data['uri'] != null) {
        RomeNavigateTo(RomeMsg.data['uri'].toString());
      } else {
        RomeReturnToCurrentUrl();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage RomeMsg) {
      if (RomeMsg.data['uri'] != null) {
        RomeNavigateTo(RomeMsg.data['uri'].toString());
      } else {
        RomeReturnToCurrentUrl();
      }
    });
  }

  void RomeNavigateTo(String RomeNewUrl) async {
    await RomeWebViewController.loadUrl(
      urlRequest: URLRequest(url: WebUri(RomeNewUrl)),
    );
  }

  void RomeReturnToCurrentUrl() async {
    Future<void>.delayed(const Duration(seconds: 3), () {
      RomeWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(RomeCurrentUrl)),
      );
    });
  }

  Future<void> RomeInitPushAndGetToken() async {
    final FirebaseMessaging RomeFm = FirebaseMessaging.instance;
    await RomeFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    RomePushToken = await RomeFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------

  void RomeBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall RomeCall) async {
      if (RomeCall.method == "onNotificationTap") {
        final Map<String, dynamic> RomePayload =
        Map<String, dynamic>.from(RomeCall.arguments);
        debugPrint("URI from platform tap: ${RomePayload['uri']}");
        final String? RomeUriString = RomePayload["uri"]?.toString();
        if (RomeUriString != null && !RomeUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext RomeContext) =>
                  RomeTableView(RomeUriString),
            ),
                (Route<dynamic> RomeRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // localStorage + SharedPreferences: профиль устройства
  // --------------------------------------------------------------------------

  /// Обновляем app_data в localStorage И синхронно сохраняем JSON в SharedPreferences
  Future<void> _romeUpdateLocalStorage() async {
    try {
      final Map<String, dynamic> data =
      RomeDeviceProfileInstance.RomeAsMap(RomeFcmToken: RomePushToken);

      final String json = jsonEncode(data);

      // 1) В localStorage WebView
      await RomeWebViewController.evaluateJavascript(
        source: "localStorage.setItem('app_data', JSON.stringify($json));",
      );

      // 2) В SharedPreferences (чтобы при следующем запуске можно было восстановить)
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_data', json);

      RomeVaultInstance.RomeLoggerInstance
          .RomeLogInfo('app_data saved to localStorage & SharedPreferences: $json');
    } catch (e, st) {
      RomeVaultInstance.RomeLoggerInstance
          .RomeLogError('updateLocalStorage error: $e\n$st');
    }
  }

  /// Восстанавливаем app_data из SharedPreferences обратно в localStorage
  Future<void> _romeRestoreAppDataFromPrefsToLocalStorage() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? savedJson = prefs.getString('app_data');
      if (savedJson == null || savedJson.isEmpty) {
        return;
      }

      final String js =
          "localStorage.setItem('app_data', JSON.stringify($savedJson));";

      await RomeWebViewController.evaluateJavascript(source: js);

      RomeVaultInstance.RomeLoggerInstance.RomeLogInfo(
          'app_data restored from SharedPreferences to localStorage: $savedJson');
    } catch (e, st) {
      RomeVaultInstance.RomeLoggerInstance.RomeLogError(
          '_romeRestoreAppDataFromPrefsToLocalStorage error: $e\n$st');
    }
  }

  // --------------------------------------------------------------------------
  // UserAgent / SafeArea helpers
  // --------------------------------------------------------------------------

  bool _romeIsGoogleUrl(Uri uri) {
    final String full = uri.toString().toLowerCase();
    return full.contains('google');
  }

  Future<void> _romeApplyUserAgent({String? fullua, String? uatail}) async {
    if (_romeBaseUserAgent == null || _romeBaseUserAgent!.trim().isEmpty) {
      try {
        final ua = await RomeWebViewController.evaluateJavascript(
          source: "navigator.userAgent",
        );
        if (ua is String && ua.trim().isNotEmpty) {
          _romeBaseUserAgent = ua.trim();
          _romeCurrentUserAgent = _romeBaseUserAgent!;
          RomeDeviceProfileInstance.RomeBaseUserAgent = _romeBaseUserAgent;
          RomeVaultInstance.RomeLoggerInstance
              .RomeLogInfo('Base User-Agent detected: $_romeBaseUserAgent');
        }
      } catch (e) {
        RomeVaultInstance.RomeLoggerInstance
            .RomeLogWarn('Failed to get base userAgent from JS: $e');
      }
    }

    if (_romeBaseUserAgent == null || _romeBaseUserAgent!.trim().isEmpty) {
      RomeVaultInstance.RomeLoggerInstance
          .RomeLogWarn('Base User-Agent is null, skip UA update');
      return;
    }

    String newUa;
    if (fullua != null && fullua.trim().isNotEmpty) {
      newUa = fullua.trim();
    } else if (uatail != null && uatail.trim().isNotEmpty) {
      newUa = "${_romeBaseUserAgent!}/${uatail.trim()}";
    } else {
      newUa = _romeBaseUserAgent!;
    }

    _romeServerUserAgent = newUa;
    RomeVaultInstance.RomeLoggerInstance
        .RomeLogInfo('Server UA calculated: $_romeServerUserAgent');
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

  Future<void> _romeApplyNormalUserAgentIfNeeded() async {
    if (_romeIsInGoogleAuth) {
      RomeVaultInstance.RomeLoggerInstance.RomeLogInfo(
          'Skip normal UA apply because we are in Google auth');
      return;
    }

    final String targetUa = _romeServerUserAgent ?? _romeBaseUserAgent ?? 'random';

    if (targetUa == _romeCurrentUserAgent) return;

    try {
      await RomeWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _romeCurrentUserAgent = targetUa;
      debugPrint('[UA] NORMAL WEBVIEW USER AGENT: $_romeCurrentUserAgent');
    } catch (e) {
      RomeVaultInstance.RomeLoggerInstance
          .RomeLogError('Error while setting UA "$targetUa": $e');
    }
  }

  Future<void> _romeAddRandomToUserAgentForGoogle() async {
    const String targetUa = 'random';
    if (_romeCurrentUserAgent == targetUa && _romeIsInGoogleAuth) return;

    try {
      await RomeWebViewController.setSettings(
        settings: InAppWebViewSettings(userAgent: targetUa),
      );
      _romeCurrentUserAgent = targetUa;
      _romeIsInGoogleAuth = true;
      debugPrint('[UA] GOOGLE RANDOM USER AGENT: $_romeCurrentUserAgent');
    } catch (e) {
      RomeVaultInstance.RomeLoggerInstance
          .RomeLogError('Error setting RANDOM UA for Google: $e');
    }
  }

  Future<void> _romeRestoreUserAgentAfterGoogleIfNeeded() async {
    if (!_romeIsInGoogleAuth) return;
    _romeIsInGoogleAuth = false;
    await _romeApplyNormalUserAgentIfNeeded();
  }

  // Хелпер для парсинга HEX‑цвета (общий для SafeArea и prefs)
  Color _romeParseHexColor(String hex, {Color fallback = const Color(0xFF1A1A22)}) {
    String value = hex.trim();
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value';
    final intColor = int.tryParse(value, radix: 16);
    if (intColor == null) return fallback;
    return Color(intColor);
  }

  // НОВОЕ: загрузка SafeArea из SharedPreferences при старте
  Future<void> _romeLoadSafeAreaFromPrefs() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool enabled = prefs.getBool(RomeSafeAreaEnabledKey) ?? false;
      final String colorHex = prefs.getString(RomeSafeAreaColorKey) ?? '';

      Color bg = Colors.black;
      if (enabled) {
        if (colorHex.isNotEmpty) {
          bg = _romeParseHexColor(colorHex, fallback: const Color(0xFF1A1A22));
        } else {
          bg = const Color(0xFF1A1A22);
        }
      }

      if (!mounted) return;

      setState(() {
        _romeSafeAreaEnabled = enabled;
        _romeSafeAreaBackgroundColor = bg;
        RomeDeviceProfileInstance.RomeSafeAreaEnabled = enabled;
        RomeDeviceProfileInstance.RomeSafeAreaColor =
        enabled ? (colorHex.isNotEmpty ? colorHex : '#1A1A22') : '';
      });

      RomeVaultInstance.RomeLoggerInstance.RomeLogInfo(
          'SafeArea loaded from prefs: enabled=$enabled, color="$colorHex"');
    } catch (e, st) {
      RomeVaultInstance.RomeLoggerInstance
          .RomeLogError('_romeLoadSafeAreaFromPrefs error: $e\n$st');
    }
  }

  void _romeUpdateSafeAreaFromServerPayload(Map<dynamic, dynamic> root) {
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

    if (safearea == null) return;

    final Brightness platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;

    String? chosenHex;
    if (platformBrightness == Brightness.light) {
      chosenHex = bgLightHex ?? bgDarkHex;
    } else {
      chosenHex = bgDarkHex ?? bgLightHex;
    }

    Color background = safearea ? const Color(0xFF1A1A22) : Colors.black;

    if (safearea && chosenHex != null && chosenHex.isNotEmpty) {
      background = _romeParseHexColor(chosenHex, fallback: const Color(0xFF1A1A22));
    }

    setState(() {
      _romeSafeAreaEnabled = safearea!;
      _romeSafeAreaBackgroundColor = background;
      RomeDeviceProfileInstance.RomeSafeAreaEnabled = safearea;
      RomeDeviceProfileInstance.RomeSafeAreaColor =
      safearea ? (chosenHex ?? '#1A1A22') : '';
    });

    // НОВОЕ: сохраняем SafeArea в SharedPreferences при каждом обновлении
    () async {
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setBool(RomeSafeAreaEnabledKey, safearea!);
        await prefs.setString(
          RomeSafeAreaColorKey,
          RomeDeviceProfileInstance.RomeSafeAreaColor ?? '',
        );
        RomeVaultInstance.RomeLoggerInstance.RomeLogInfo(
          'SafeArea saved to prefs: enabled=$safearea, color="${RomeDeviceProfileInstance.RomeSafeAreaColor}"',
        );
      } catch (e, st) {
        RomeVaultInstance.RomeLoggerInstance
            .RomeLogError('Error saving SafeArea to prefs: $e\n$st');
      }
    }();
  }

  // --------------------------------------------------------------------------
  // POPUP helpers
  // --------------------------------------------------------------------------

  InAppWebViewSettings _romePopupSettings() {
    return InAppWebViewSettings(
      javaScriptEnabled: true,
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

  void _romeOpenPopup(CreateWindowAction req, {String? urlString}) {
    setState(() {
      _romePopupCreateAction = req;
      _romePopupUrl = (urlString != null && urlString.isNotEmpty)
          ? urlString
          : req.request.url?.toString();
      _romePopupCurrentUrl = _romePopupUrl;
      _romeIsPopupVisible = true;
      _romePopupCanGoBack = false;
    });
  }

  void _romeClosePopup() {
    setState(() {
      _romeIsPopupVisible = false;
      _romePopupUrl = null;
      _romePopupCurrentUrl = null;
      _romePopupCreateAction = null;
      _romePopupCanGoBack = false;
      _romePopupWebViewController = null;
    });
  }

  Future<void> _romeRefreshPopupCanGoBack() async {
    final InAppWebViewController? c = _romePopupWebViewController;
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
    } catch (_) {}
  }

  Future<void> _romeHandlePopupBackPressed() async {
    final InAppWebViewController? c = _romePopupWebViewController;
    if (c == null) {
      _romeClosePopup();
      return;
    }
    try {
      if (await c.canGoBack()) {
        await c.goBack();
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          _romeRefreshPopupCanGoBack();
        });
      } else {
        _romeClosePopup();
      }
    } catch (_) {
      _romeClosePopup();
    }
  }

  Widget _romeBuildPopupOverlay() {
    if (!_romeIsPopupVisible || (_romePopupUrl == null && _romePopupCreateAction == null)) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.96),
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                color: Colors.black,
                height: 48,
                child: Row(
                  children: [
                    if (_romePopupCanGoBack)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _romeHandlePopupBackPressed,
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _romeClosePopup,
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Expanded(
              child: InAppWebView(
                windowId: _romePopupCreateAction?.windowId,
                initialUrlRequest:
                (_romePopupCreateAction?.windowId == null && _romePopupUrl != null)
                    ? URLRequest(url: WebUri(_romePopupUrl!))
                    : null,
                initialSettings: _romePopupSettings(),
                onWebViewCreated: (InAppWebViewController controller) async {
                  _romePopupWebViewController = controller;
                },
                onLoadStart: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _romePopupCurrentUrl = uri.toString();
                    });
                  }
                  await _romeRefreshPopupCanGoBack();
                },
                onPermissionRequest: (controller, request) async {
                  return PermissionResponse(
                    resources: request.resources,
                    action: PermissionResponseAction.GRANT,
                  );
                },
                onLoadStop: (controller, uri) async {
                  if (uri != null) {
                    setState(() {
                      _romePopupCurrentUrl = uri.toString();
                    });
                  }
                  await _romeRefreshPopupCanGoBack();
                },
                onUpdateVisitedHistory:
                    (controller, url, isReload) async {
                  if (url != null) {
                    setState(() {
                      _romePopupCurrentUrl = url.toString();
                    });
                  }
                  await _romeRefreshPopupCanGoBack();
                },
                shouldOverrideUrlLoading: (
                    InAppWebViewController controller,
                    NavigationAction nav,
                    ) async {
                  final Uri? uri = nav.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final String scheme = uri.scheme.toLowerCase();

                  if (RomeKit.RomeLooksLikeBareMail(uri)) {
                    final Uri mailto = RomeKit.RomeToMailto(uri);
                    await RomeLinker.RomeOpen(RomeKit.RomeGmailize(mailto));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'mailto') {
                    await RomeLinker.RomeOpen(RomeKit.RomeGmailize(uri));
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme == 'tel') {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (RomeIsBankScheme(uri) ||
                      ((scheme == 'http' || scheme == 'https') &&
                          RomeIsBankDomain(uri))) {
                    await RomeOpenBank(uri);
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (scheme != 'http' && scheme != 'https') {
                    return NavigationActionPolicy.CANCEL;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onCloseWindow: (controller) {
                  _romeClosePopup();
                },
                onDownloadStartRequest: (controller, req) async {
                  await RomeLinker.RomeOpen(req.url);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    RomeBindPlatformNotificationTap();

    final bool RomeIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    final Color bgColor = _romeSafeAreaEnabled
        ? _romeSafeAreaBackgroundColor
        : (RomeIsDark ? Colors.black : Colors.white);

    final Widget webView = InAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        disableDefaultErrorPage: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsPictureInPictureMediaPlayback: true,
        useOnDownloadStart: true,
        javaScriptCanOpenWindowsAutomatically: true,
        useShouldOverrideUrlLoading: true,
        supportMultipleWindows: true,
      ),
      initialUrlRequest: URLRequest(
        url: WebUri(RomeCurrentUrl),
      ),
      onWebViewCreated: (InAppWebViewController RomeController) async {
        RomeWebViewController = RomeController;

        // Инициализация UA
        try {
          final ua = await RomeController.evaluateJavascript(
            source: "navigator.userAgent",
          );
          if (ua is String && ua.trim().isNotEmpty) {
            _romeBaseUserAgent = ua.trim();
            _romeCurrentUserAgent = _romeBaseUserAgent!;
            RomeDeviceProfileInstance.RomeBaseUserAgent = _romeBaseUserAgent;
            debugPrint('[UA] INITIAL: $_romeBaseUserAgent');
          }
        } catch (e) {
          RomeVaultInstance.RomeLoggerInstance
              .RomeLogWarn('Failed to read navigator.userAgent: $e');
        }

        await _romeApplyNormalUserAgentIfNeeded();

        // После создания WebView — актуализируем localStorage
        await _romeUpdateLocalStorage();

        // Через 6 секунд после открытия экрана — восстановление app_data из SharedPreferences
        Future<void>.delayed(const Duration(seconds: 6), () async {
          if (!mounted) return;
          await _romeRestoreAppDataFromPrefsToLocalStorage();
        });

        RomeWebViewController.addJavaScriptHandler(
          handlerName: 'onServerResponse',
          callback: (List<dynamic> RomeArgs) {
            RomeVaultInstance.RomeLoggerInstance
                .RomeLogInfo("JS Args: $RomeArgs");

            try {
              dynamic first = RomeArgs.isNotEmpty ? RomeArgs[0] : null;

              if (first is List && first.isNotEmpty) {
                first = first.first;
              }

              if (first is Map) {
                final Map<dynamic, dynamic> root = first;

                // safearea + userAgent из сервера
                _romeUpdateSafeAreaFromServerPayload(root);
                _romeUpdateUserAgentFromServerPayload(root);
                _romeApplyNormalUserAgentIfNeeded();

                // При каждом ответе сервера можно обновлять localStorage
                _romeUpdateLocalStorage();
              }

              try {
                return RomeArgs
                    .reduce((dynamic RomeV, dynamic RomeE) => RomeV + RomeE);
              } catch (_) {
                return RomeArgs.toString();
              }
            } catch (e) {
              return RomeArgs.toString();
            }
          },
        );
      },
      onLoadStart: (
          InAppWebViewController RomeController,
          Uri? RomeUri,
          ) async {
        RomeStartLoadTimestamp = DateTime.now().millisecondsSinceEpoch;

        if (RomeUri != null) {
          if (_romeIsGoogleUrl(RomeUri)) {
            await _romeAddRandomToUserAgentForGoogle();
          } else {
            await _romeRestoreUserAgentAfterGoogleIfNeeded();
            await _romeApplyNormalUserAgentIfNeeded();
          }

          if (RomeKit.RomeLooksLikeBareMail(RomeUri)) {
            try {
              await RomeController.stopLoading();
            } catch (_) {}
            final Uri RomeMailto = RomeKit.RomeToMailto(RomeUri);
            await RomeLinker.RomeOpen(
              RomeKit.RomeGmailize(RomeMailto),
            );
            return;
          }

          // банки
          if (RomeIsBankScheme(RomeUri) ||
              ((RomeUri.scheme == 'http' || RomeUri.scheme == 'https') &&
                  RomeIsBankDomain(RomeUri))) {
            try {
              await RomeController.stopLoading();
            } catch (_) {}
            await RomeOpenBank(RomeUri);
            return;
          }

          final String RomeScheme = RomeUri.scheme.toLowerCase();
          if (RomeScheme != 'http' && RomeScheme != 'https') {
            try {
              await RomeController.stopLoading();
            } catch (_) {}
          }
        }
      },
      onLoadStop: (
          InAppWebViewController RomeController,
          Uri? RomeUri,
          ) async {
        await RomeController.evaluateJavascript(
          source: "console.log('Hello from Roulette JS!');",
        );

        setState(() {
          RomeCurrentUrl = RomeUri?.toString() ?? RomeCurrentUrl;
        });

        await _romeRestoreUserAgentAfterGoogleIfNeeded();
        await _romeApplyNormalUserAgentIfNeeded();

        // После полной загрузки страницы обновляем localStorage
        await _romeUpdateLocalStorage();

        // И сразу тянем app_data из SharedPreferences в localStorage
        await _romeRestoreAppDataFromPrefsToLocalStorage();

        Future<void>.delayed(const Duration(seconds: 20), () {
          RomeSendLoadedOnce();
        });
      },
      shouldOverrideUrlLoading: (
          InAppWebViewController RomeController,
          NavigationAction RomeNav,
          ) async {
        final Uri? RomeUri = RomeNav.request.url;
        if (RomeUri == null) {
          return NavigationActionPolicy.ALLOW;
        }

        if (_romeIsGoogleUrl(RomeUri)) {
          await _romeAddRandomToUserAgentForGoogle();
        } else {
          await _romeRestoreUserAgentAfterGoogleIfNeeded();
          await _romeApplyNormalUserAgentIfNeeded();
        }

        if (RomeKit.RomeLooksLikeBareMail(RomeUri)) {
          final Uri RomeMailto = RomeKit.RomeToMailto(RomeUri);
          await RomeLinker.RomeOpen(
            RomeKit.RomeGmailize(RomeMailto),
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String RomeScheme = RomeUri.scheme.toLowerCase();

        if (RomeScheme == 'mailto') {
          await RomeLinker.RomeOpen(
            RomeKit.RomeGmailize(RomeUri),
          );
          return NavigationActionPolicy.CANCEL;
        }

        if (RomeIsBankScheme(RomeUri) ||
            ((RomeScheme == 'http' || RomeScheme == 'https') &&
                RomeIsBankDomain(RomeUri))) {
          await RomeOpenBank(RomeUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (RomeScheme == 'tel') {
          await launchUrl(
            RomeUri,
            mode: LaunchMode.externalApplication,
          );
          return NavigationActionPolicy.CANCEL;
        }

        final String RomeHost = RomeUri.host.toLowerCase();
        final bool RomeIsSocial = RomeHost.endsWith('facebook.com') ||
            RomeHost.endsWith('instagram.com') ||
            RomeHost.endsWith('twitter.com') ||
            RomeHost.endsWith('x.com');

        if (RomeIsSocial) {
          await RomeLinker.RomeOpen(RomeUri);
          return NavigationActionPolicy.CANCEL;
        }

        if (RomeIsExternalDestination(RomeUri)) {
          final Uri RomeMapped = RomeMapExternalToHttp(RomeUri);
          await RomeLinker.RomeOpen(RomeMapped);
          return NavigationActionPolicy.CANCEL;
        }

        if (RomeScheme != 'http' && RomeScheme != 'https') {
          return NavigationActionPolicy.CANCEL;
        }

        return NavigationActionPolicy.ALLOW;
      },
      onCreateWindow: (
          InAppWebViewController RomeController,
          CreateWindowAction RomeReq,
          ) async {
        final Uri? RomeUrl = RomeReq.request.url;
        if (RomeUrl == null) return false;

        if (_romeIsGoogleUrl(RomeUrl)) {
          await _romeAddRandomToUserAgentForGoogle();
        } else {
          await _romeRestoreUserAgentAfterGoogleIfNeeded();
          await _romeApplyNormalUserAgentIfNeeded();
        }

        if (RomeKit.RomeLooksLikeBareMail(RomeUrl)) {
          final Uri RomeMail = RomeKit.RomeToMailto(RomeUrl);
          await RomeLinker.RomeOpen(
            RomeKit.RomeGmailize(RomeMail),
          );
          return false;
        }

        final String RomeScheme = RomeUrl.scheme.toLowerCase();

        if (RomeScheme == 'mailto') {
          await RomeLinker.RomeOpen(
            RomeKit.RomeGmailize(RomeUrl),
          );
          return false;
        }

        if (RomeIsBankScheme(RomeUrl) ||
            ((RomeScheme == 'http' || RomeScheme == 'https') &&
                RomeIsBankDomain(RomeUrl))) {
          await RomeOpenBank(RomeUrl);
          return false;
        }

        if (RomeScheme == 'tel') {
          await launchUrl(
            RomeUrl,
            mode: LaunchMode.externalApplication,
          );
          return false;
        }

        final String RomeHost = RomeUrl.host.toLowerCase();
        final bool RomeIsSocial = RomeHost.endsWith('facebook.com') ||
            RomeHost.endsWith('instagram.com') ||
            RomeHost.endsWith('twitter.com') ||
            RomeHost.endsWith('x.com');

        if (RomeIsSocial) {
          await RomeLinker.RomeOpen(RomeUrl);
          return false;
        }

        if (RomeIsExternalDestination(RomeUrl)) {
          final Uri RomeMapped = RomeMapExternalToHttp(RomeUrl);
          await RomeLinker.RomeOpen(RomeMapped);
          return false;
        }

        // popup-логика: всё, что осталось http/https — открываем во всплывающем WebView
        if (RomeScheme == 'http' || RomeScheme == 'https') {
          _romeOpenPopup(RomeReq, urlString: RomeUrl.toString());
          return true; // говорим WebView, что создаём окно сами
        }

        return false;
      },
    );

    final Widget body = Stack(
      children: <Widget>[
        webView,
        if (RomeOverlayBusy)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black87,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        _romeBuildPopupOverlay(),
      ],
    );

    final Widget wrapped = _romeSafeAreaEnabled ? SafeArea(child: body) : body;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bgColor,
        body: wrapped,
      ),
    );
  }

  // ========================================================================
  // Внешние "столы" (протоколы/мессенджеры/соцсети)
  // ========================================================================

  bool RomeIsExternalDestination(Uri RomeUri) {
    final String RomeScheme = RomeUri.scheme.toLowerCase();
    if (RomeExternalSchemes.contains(RomeScheme)) {
      return true;
    }

    if (RomeScheme == 'http' || RomeScheme == 'https') {
      final String RomeHost = RomeUri.host.toLowerCase();
      if (RomeExternalHosts.contains(RomeHost)) {
        return true;
      }
      if (RomeHost.endsWith('t.me')) return true;
      if (RomeHost.endsWith('wa.me')) return true;
      if (RomeHost.endsWith('m.me')) return true;
      if (RomeHost.endsWith('signal.me')) return true;
      if (RomeHost.endsWith('facebook.com')) return true;
      if (RomeHost.endsWith('instagram.com')) return true;
      if (RomeHost.endsWith('twitter.com')) return true;
      if (RomeHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri RomeMapExternalToHttp(Uri RomeUri) {
    final String RomeScheme = RomeUri.scheme.toLowerCase();

    if (RomeScheme == 'tg' || RomeScheme == 'telegram') {
      final Map<String, String> RomeQp = RomeUri.queryParameters;
      final String? RomeDomain = RomeQp['domain'];
      if (RomeDomain != null && RomeDomain.isNotEmpty) {
        return Uri.https('t.me', '/$RomeDomain', <String, String>{
          if (RomeQp['start'] != null) 'start': RomeQp['start']!,
        });
      }
      final String RomePath = RomeUri.path.isNotEmpty ? RomeUri.path : '';
      return Uri.https(
        't.me',
        '/$RomePath',
        RomeUri.queryParameters.isEmpty ? null : RomeUri.queryParameters,
      );
    }

    if (RomeScheme == 'whatsapp') {
      final Map<String, String> RomeQp = RomeUri.queryParameters;
      final String? RomePhone = RomeQp['phone'];
      final String? RomeText = RomeQp['text'];
      if (RomePhone != null && RomePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${RomeKit.RomeDigitsOnly(RomePhone)}',
          <String, String>{
            if (RomeText != null && RomeText.isNotEmpty) 'text': RomeText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (RomeText != null && RomeText.isNotEmpty) 'text': RomeText,
        },
      );
    }

    if (RomeScheme == 'bnl') {
      final String RomeNewPath = RomeUri.path.isNotEmpty ? RomeUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$RomeNewPath',
        RomeUri.queryParameters.isEmpty ? null : RomeUri.queryParameters,
      );
    }

    return RomeUri;
  }

  Future<void> RomeSendLoadedOnce() async {
    if (RomeLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final int RomeNow = DateTime.now().millisecondsSinceEpoch;

    await RomePostStat(
      RomeEvent: 'Loaded',
      RomeTimeStart: RomeStartLoadTimestamp,
      RomeTimeFinish: RomeNow,
      RomeUrl: RomeCurrentUrl,
      RomeAppSid: RomeSpyInstance.RomeAppsFlyerUid,
      RomeFirstPageTs: RomeFirstPageTimestamp,
    );

    RomeLoadedOnceSent = true;
  }
}