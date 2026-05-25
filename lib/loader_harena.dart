// ============================================================================
// ArenaScreen — отдельный Flutter-экран.
// Шлем спартанца крутится вокруг своей оси (Y) на готическом фоне.
// ----------------------------------------------------------------------------
// Требуются ассеты:
//   assets/arena_bg.png  — тёмный мраморный фон с эмблемой и щитами
//   assets/helmet.png    — шлем с красным гребнем (PNG с прозрачным фоном)
//
// pubspec.yaml:
//   flutter:
//     uses-material-design: true
//     assets:
//       - assets/arena_bg.png
//       - assets/helmet.png
//
// Использование:
//   Navigator.push(
//     context,
//     MaterialPageRoute(builder: (_) => const ArenaScreen()),
//   );
// ============================================================================

import 'dart:math' as ArenaMath;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({Key? key}) : super(key: key);

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen>
    with TickerProviderStateMixin {
  /// Основной контроллер вращения шлема — 1 полный оборот за 6 секунд
  late final AnimationController ArenaSpinController;

  /// Доп. контроллер для мерцания пламени / искр (4 секунды)
  late final AnimationController ArenaEmberController;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    ArenaSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    ArenaEmberController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    ArenaSpinController.dispose();
    ArenaEmberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0306),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double ArenaW = constraints.maxWidth;
          final double ArenaH = constraints.maxHeight;
          // Шлем по высоте — примерно 38% экрана
          final double ArenaHelmetSize = ArenaW * 0.55;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 1) Фон
              Image.asset(
                'assets/arena_bg.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),

              // 2) Лёгкая виньетка для большей глубины
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: <Color>[
                      Colors.transparent,
                      Color(0xCC000000),
                    ],
                    stops: <double>[0.55, 1.0],
                  ),
                ),
                child: SizedBox.expand(),
              ),

              // 3) Мерцающие искры/пламя (поверх фона)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: ArenaEmberController,
                    builder: (BuildContext context, Widget? _) {
                      return CustomPaint(
                        painter: ArenaEmberPainter(
                          ArenaPhase: ArenaEmberController.value,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // 4) Шлем — вращается вокруг оси Y (3D effect)
              Center(
                child: AnimatedBuilder(
                  animation: ArenaSpinController,
                  builder: (BuildContext context, Widget? _) {
                    final double ArenaAngle =
                        ArenaSpinController.value * 2 * ArenaMath.pi;

                    // Лёгкое покачивание вверх-вниз
                    final double ArenaBob = ArenaMath
                        .sin(ArenaSpinController.value * 2 * ArenaMath.pi) *
                        6;

                    return Transform.translate(
                      offset: Offset(0, ArenaBob),
                      child: _ArenaSpinningHelmet(
                        ArenaAngle: ArenaAngle,
                        ArenaSize: ArenaHelmetSize,
                      ),
                    );
                  },
                ),
              ),

              // 5) Тень-блик под шлемом (пол)
              Positioned(
                bottom: ArenaH * 0.10,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: ArenaSpinController,
                  builder: (BuildContext context, Widget? _) {
                    final double ArenaPulse = 0.5 +
                        0.5 *
                            ArenaMath.sin(
                                ArenaSpinController.value * 2 * ArenaMath.pi);
                    return Center(
                      child: Container(
                        width: ArenaHelmetSize * 0.85,
                        height: ArenaHelmetSize * 0.10,
                        decoration: BoxDecoration(
                          shape: BoxShape.rectangle,
                          borderRadius:
                          BorderRadius.circular(ArenaHelmetSize),
                          gradient: RadialGradient(
                            colors: <Color>[
                              const Color(0xFFB31C20)
                                  .withOpacity(0.45 + 0.25 * ArenaPulse),
                              const Color(0xFF8A0E12).withOpacity(0.15),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // 6) Подпись
              Positioned(
                bottom: 36,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: ArenaSpinController,
                    builder: (BuildContext context, Widget? _) {
                      final int ArenaDots =
                      ((ArenaSpinController.value * 6).floor() % 4);
                      return Text(
                        'ARENA${'.' * ArenaDots}',
                        style: TextStyle(
                          color: const Color(0xFFE2C081),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                          shadows: <Shadow>[
                            Shadow(
                              color: const Color(0xFFB31C20).withOpacity(0.85),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Виджет шлема с 3D-вращением по вертикальной оси.
/// При angle > π/2 показываем зеркальное отражение шлема, чтобы
/// рисунок не выворачивался "наизнанку" — выглядит как полноценный 3D-поворот.
class _ArenaSpinningHelmet extends StatelessWidget {
  final double ArenaAngle;
  final double ArenaSize;

  const _ArenaSpinningHelmet({
    required this.ArenaAngle,
    required this.ArenaSize,
  });

  @override
  Widget build(BuildContext context) {
    // Нормализованный угол в [0, 2π)
    final double ArenaA = ArenaAngle % (2 * ArenaMath.pi);

    // cos угла — определяет ширину проекции (squash) и видимость "лица" шлема.
    final double ArenaCos = ArenaMath.cos(ArenaA);

    // Когда мы за пределами фронтальной полусферы (cos < 0), показываем
    // отражённую версию шлема — имитация "задней" стороны 3D-объекта.
    final bool ArenaIsBack = ArenaCos < 0;

    // Матрица 3D-вращения с лёгкой перспективой
    final Matrix4 ArenaMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0015) // перспектива
      ..rotateY(ArenaA);

    // Если "задняя" сторона — слегка затемним шлем
    final double ArenaShadeFactor = ArenaIsBack ? 0.55 : 1.0;

    Widget ArenaHelmet = SizedBox(
      width: ArenaSize,
      height: ArenaSize,
      child: Image.asset(
        'assets/helmet.png',
        fit: BoxFit.contain,
      ),
    );

    // Затемнение задней стороны
    ArenaHelmet = ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withOpacity(1 - ArenaShadeFactor),
        BlendMode.darken,
      ),
      child: ArenaHelmet,
    );

    // Лёгкое свечение под шлемом (золотистая аура)
    final Widget ArenaWithGlow = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Container(
          width: ArenaSize * 1.15,
          height: ArenaSize * 1.15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                const Color(0xFFFFB347).withOpacity(0.20),
                const Color(0xFFB31C20).withOpacity(0.10),
                Colors.transparent,
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
        ),
        Transform(
          alignment: Alignment.center,
          transform: ArenaMatrix,
          child: ArenaHelmet,
        ),
      ],
    );

    return ArenaWithGlow;
  }
}

/// Рисует мерцающие искры/угольки поверх фона
class ArenaEmberPainter extends CustomPainter {
  final double ArenaPhase; // 0..1

  ArenaEmberPainter({required this.ArenaPhase});

  @override
  void paint(Canvas ArenaCanvas, Size ArenaSize) {
    final ArenaMath.Random ArenaRnd = ArenaMath.Random(31);
    final Paint ArenaPaint = Paint();

    // Поднимающиеся угольки (снизу вверх, зацикленно)
    for (int i = 0; i < 22; i++) {
      final double ArenaSeedX = ArenaRnd.nextDouble();
      final double ArenaSpeed = 0.7 + ArenaRnd.nextDouble() * 0.8;
      final double ArenaPhaseOffset = ArenaRnd.nextDouble();

      // Прогресс отдельной частицы — 0 (снизу) .. 1 (вверху)
      final double ArenaLocalT =
      ((ArenaPhase * ArenaSpeed + ArenaPhaseOffset) % 1.0);

      // Лёгкое горизонтальное "колыхание"
      final double ArenaWave = ArenaMath.sin(
          (ArenaPhase * 2 * ArenaMath.pi) + i * 0.7) *
          (ArenaSize.width * 0.02);

      final double ArenaX = ArenaSeedX * ArenaSize.width + ArenaWave;
      // Стартуют у нижней четверти и поднимаются к верхней половине
      final double ArenaY = ArenaSize.height * (0.95 - ArenaLocalT * 0.65);

      // Прозрачность гаснет к концу пути
      final double ArenaAlpha =
          (1.0 - ArenaLocalT) * (0.55 + 0.45 * ArenaRnd.nextDouble());

      final double ArenaRadius =
          1.0 + ArenaRnd.nextDouble() * 2.2 * (1 - ArenaLocalT);

      ArenaPaint.color = Color.lerp(
        const Color(0xFFFFC451),
        const Color(0xFFB31C20),
        ArenaLocalT,
      )!
          .withOpacity(ArenaAlpha.clamp(0.0, 1.0));

      ArenaCanvas.drawCircle(
        Offset(ArenaX, ArenaY),
        ArenaRadius,
        ArenaPaint,
      );
    }

    // Лёгкое свечение в углах от факелов (если они есть на фоне)
    final Paint ArenaGlow = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFA64C)
              .withOpacity(0.18 + 0.12 * ArenaMath.sin(ArenaPhase * 6.28)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(ArenaSize.width * 0.18, ArenaSize.height * 0.92),
          radius: ArenaSize.width * 0.35,
        ),
      );
    ArenaCanvas.drawRect(Offset.zero & ArenaSize, ArenaGlow);

    final Paint ArenaGlow2 = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          const Color(0xFFFFA64C).withOpacity(0.18 +
              0.12 * ArenaMath.sin(ArenaPhase * 6.28 + ArenaMath.pi)),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(ArenaSize.width * 0.82, ArenaSize.height * 0.92),
          radius: ArenaSize.width * 0.35,
        ),
      );
    ArenaCanvas.drawRect(Offset.zero & ArenaSize, ArenaGlow2);
  }

  @override
  bool shouldRepaint(covariant ArenaEmberPainter ArenaOld) =>
      ArenaOld.ArenaPhase != ArenaPhase;
}
