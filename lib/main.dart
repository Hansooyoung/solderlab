import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: SolderLabApp(),
    ),
  );
}

class SolderLabApp extends StatefulWidget {
  const SolderLabApp({super.key});

  @override
  State<SolderLabApp> createState() => _SolderLabAppState();
}

class _SolderLabAppState extends State<SolderLabApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Jaminan Privasi & Zero-Background Resource Leak:
    // Bersihkan image cache saat aplikasi dijeda atau tidak aktif
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SolderLab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.solderLabTheme,
      home: const SplashScreen(),
    );
  }
}
