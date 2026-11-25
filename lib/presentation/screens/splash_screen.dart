import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../providers/inspection_providers.dart';
import 'main_navigation_scaffold.dart';

/// SplashScreen: Layar Pembuka SolderLab (Warm Eggshell & Dual Capsule Loading)
class SplashScreen extends ConsumerStatefulWidget {
  final bool autoStart;
  const SplashScreen({super.key, this.autoStart = true});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  String _statusText = 'Menyiapkan modul deteksi...';

  final List<String> _loadingTips = [
    'Memuat basis data standar mutu IPC-A-610...',
    'Menginisialisasi mesin penglihatan komputer...',
    'Menyiapkan modul deteksi multi-titik solder...',
    'Sistem siap! Masuk ke meja kerja SolderLab...',
  ];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
      value: widget.autoStart ? 0.0 : 0.70,
    );

    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );

    _progressController.addListener(() {
      final val = _progressController.value;
      if (val < 0.3) {
        setState(() => _statusText = _loadingTips[0]);
      } else if (val < 0.65) {
        setState(() => _statusText = _loadingTips[1]);
      } else if (val < 0.9) {
        setState(() => _statusText = _loadingTips[2]);
      } else {
        setState(() => _statusText = _loadingTips[3]);
      }
    });

    if (widget.autoStart) {
      _startAppInit();
    } else {
      _statusText = _loadingTips[2];
    }
  }

  Future<void> _startAppInit() async {
    _progressController.forward();

    try {
      // Inisialisasi basis data SQLite lokal & AI Service
      await Future.wait([
        AppDatabase.instance.database,
        ref.read(aiServiceProvider.future),
      ]);
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationScaffold(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Header Judul Aplikasi SolderLab
              Column(
                children: [
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2052738D),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(
                            Icons.bolt_rounded,
                            color: AppTheme.slateBlue,
                            size: 28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'SolderLab',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.slateBlueDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ASISTEN INSPEKSI & BELAJAR SOLDER ELEKTRONIKA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),

              // 2. Soldy Animated Living Mascot
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SoldyAvatarAnimated(
                    size: 210,
                    enableBreathing: widget.autoStart,
                    enableBlinking: widget.autoStart,
                  ),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, _) {
                      return Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.slateBlue,
                        ),
                      );
                    },
                  ),
                ],
              ),

              // 3. Dual Capsule Progress Bar & Bottom Tip
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dual Capsule Loading Bar
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, _) {
                      final percent = (_progressAnimation.value * 100).toInt();
                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 12,
                            decoration: BoxDecoration(
                              color: AppTheme.softSky,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.softSkyBorder, width: 1),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _progressAnimation.value.clamp(0.05, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.slateBlue,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Memuat Sistem $percent%',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.slateBlue,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Bottom Info Capsule
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.softSkyBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F52738D),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.slateBlue),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '100% On-Device AI • Privasi Terjamin',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.slateBlue,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
