import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import '../providers/inspection_providers.dart';
import '../widgets/app_logo.dart';
import 'main_navigation_scaffold.dart';
import '../../core/animations/anim_kit.dart';

/// Halaman Permintaan Perizinan Aplikasi SolderLab (Kamera & Penyimpanan)
class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key});

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  bool _cameraGranted = true;
  bool _storageGranted = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      appBar: AppBar(
        title: const Text('Izin Akses Perangkat'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: AppLogo(size: 48, showText: true, fontSize: 20),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  ref.tr('deviceAccessRequired'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppTheme.slateBlueDark,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  ref.tr('permissionDesc'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 1. Izin Kamera
              _buildPermissionTile(
                icon: Icons.camera_alt_outlined,
                title: ref.tr('cameraPermissionTitle'),
                description: ref.tr('cameraPermissionDesc'),
                isGranted: _cameraGranted,
                onToggle: (val) => setState(() => _cameraGranted = val),
              ),
              const SizedBox(height: 12),

              // 2. Izin Penyimpanan & Direktori
              _buildPermissionTile(
                icon: Icons.folder_outlined,
                title: ref.tr('storagePermissionTitle'),
                description: ref.tr('storagePermissionDesc'),
                isGranted: _storageGranted,
                onToggle: (val) => setState(() => _storageGranted = val),
              ),
              const SizedBox(height: 16),

              // 3. Jaminan Privasi
              Container(
                padding: const EdgeInsets.all(14),
                decoration: AppTheme.cardDecoration(
                  backgroundColor: AppTheme.softSky,
                  borderColor: AppTheme.softSkyBorder,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded, size: 22, color: AppTheme.slateBlue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ref.tr('privacyGuarantee'),
                        style: const TextStyle(fontSize: 11, color: AppTheme.slateBlueDark, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // Tombol Setujui & Lanjutkan
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    await ref.read(repositoryProvider).setPermissionGranted(true);
                    if (context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        SolderPageRoute(builder: (_) => const MainNavigationScaffold()),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.slateBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    ref.tr('grantAndContinue'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String description,
    required bool isGranted,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isGranted ? AppTheme.softSky : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isGranted ? AppTheme.slateBlue : Colors.grey, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slateBlueDark),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                ),
              ],
            ),
          ),
          Switch(
            value: isGranted,
            activeThumbColor: AppTheme.slateBlue,
            activeTrackColor: AppTheme.softSky,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
