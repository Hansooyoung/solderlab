import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'camera_scan_screen.dart';
import '../../core/animations/anim_kit.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';

/// WorkstationSetupScreen: Layar Persiapan Meja Solder (Pre-Flight Diagnostics)
class WorkstationSetupScreen extends StatefulWidget {
  const WorkstationSetupScreen({super.key});

  @override
  State<WorkstationSetupScreen> createState() => _WorkstationSetupScreenState();
}

class _WorkstationSetupScreenState extends State<WorkstationSetupScreen> {
  bool _angleReady = true;
  bool _lightingReady = true;
  bool _lensClean = true;
  bool _pcbStable = true;
  String _selectedBoard = 'Pemeriksaan Umum PCB (Through-Hole)';

  static const Map<String, String> _boardTypeByOption = {
    'Pemeriksaan Umum PCB (Through-Hole)': AppConstants.boardGeneralPcb,
    'PCB SMD / Modul Campuran': AppConstants.boardSmdMixed,
    'Header Pin & Konektor Modul': AppConstants.boardHeaderConnector,
    'Soket IC & Rangkaian Komponen': AppConstants.boardIcSocket,
    'Papan Sirkuit Kustom': AppConstants.boardCustom,
  };

  final List<String> _boardOptions = [
    'Pemeriksaan Umum PCB (Through-Hole)',
    'PCB SMD / Modul Campuran',
    'Header Pin & Konektor Modul',
    'Soket IC & Rangkaian Komponen',
    'Papan Sirkuit Kustom',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      appBar: AppBar(
        backgroundColor: AppTheme.warmEggshell,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.slateBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Persiapan Meja Solder',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.slateBlueDark,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // Panduan Interaktif Soldy sebelum Membidik
                  FadeSlideIn(
                    index: 0,
                    child: SoldyCoachBanner(
                      mood: (_angleReady && _lightingReady && _lensClean && _pcbStable)
                          ? SoldyMood.happy
                          : SoldyMood.warning,
                      badge: 'PANDUAN SOLDY SEBELUM MEMBIDIK',
                      messages: (_angleReady && _lightingReady && _lensClean && _pcbStable)
                          ? const [
                              'Semua kondisi optik optimal! Soldy akan memindai titik timah dan otomatis menyaring kaki komponen yang belum terpotong.',
                              'Tip: Jika papan kecil, dekatkan kamera secukupnya agar solder cone terlihat kontras terhadap warna PCB.',
                            ]
                          : const [
                              'Beberapa syarat optik belum dicentang. Pastikan lensa tegak lurus 90° dan pencahayaan bebas silau agar evaluasi maksimal.',
                              'Latar meja yang tenang dan stabil membantu Soldy memisahkan papan PCB dari bayangan.',
                            ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pilihan Modul PCB
                  const FadeSlideIn(
                    index: 1,
                    child: Text(
                      'PILIHAN MODUL PCB',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateBlue,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeSlideIn(
                    index: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: AppTheme.cardDecoration(),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedBoard,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.slateBlue),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          items: _boardOptions.map((opt) {
                            return DropdownMenuItem<String>(
                              value: opt,
                              child: Text(opt),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedBoard = val);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4 Checklist Cards
                  const FadeSlideIn(
                    index: 2,
                    child: Text(
                      'CHECKLIST SUDUT & PENCAHAYAAN',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateBlue,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  FadeSlideIn(
                    index: 2,
                    child: _buildChecklistCard(
                      title: 'Sudut Kamera Tegak Lurus (90°)',
                      description: 'Posisikan lensa tepat di atas papan PCB sejajar bidang permukaan solder.',
                      icon: Icons.crop_free_rounded,
                      isChecked: _angleReady,
                      onToggle: () => setState(() => _angleReady = !_angleReady),
                    ),
                  ),
                  const SizedBox(height: 10),

                  FadeSlideIn(
                    index: 3,
                    child: _buildChecklistCard(
                      title: 'Pencahayaan Merata (Tanpa Silau)',
                      description: 'Gunakan lampu meja putih netral, hindari bayangan tajam & pantulan kilau timah.',
                      icon: Icons.wb_sunny_outlined,
                      isChecked: _lightingReady,
                      onToggle: () => setState(() => _lightingReady = !_lightingReady),
                    ),
                  ),
                  const SizedBox(height: 10),

                  FadeSlideIn(
                    index: 4,
                    child: _buildChecklistCard(
                      title: 'Lensa Bersih & Bebas Debu',
                      description: 'Pastikan kaca kamera tidak terkena residu asap pasta flux solder.',
                      icon: Icons.cleaning_services_outlined,
                      isChecked: _lensClean,
                      onToggle: () => setState(() => _lensClean = !_lensClean),
                    ),
                  ),
                  const SizedBox(height: 10),

                  FadeSlideIn(
                    index: 5,
                    child: _buildChecklistCard(
                      title: 'Papan Sirkuit Stabil & Rata',
                      description: 'Letakkan PCB di atas holder / mat antistatis agar tidak goyang saat scan.',
                      icon: Icons.layers_outlined,
                      isChecked: _pcbStable,
                      onToggle: () => setState(() => _pcbStable = !_pcbStable),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.softSkyBorder, width: 1)),
              ),
              child: PressableScale(
                onTap: () {
                  Navigator.push(
                    context,
                    SolderPageRoute(
                      builder: (_) => CameraScanScreen(
                        boardType: _boardTypeByOption[_selectedBoard] ?? AppConstants.boardGeneralPcb,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.slateBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.slateBlue.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Mulai Pemeriksaan Solder',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isChecked,
    required VoidCallback onToggle,
  }) {
    return PressableScale(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(
          borderColor: isChecked ? AppTheme.slateBlue.withValues(alpha: 0.45) : AppTheme.softSkyBorder,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isChecked ? AppTheme.softSky : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isChecked ? AppTheme.slateBlue : Colors.grey.shade500,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isChecked ? AppTheme.slateBlue : Colors.transparent,
                border: Border.all(
                  color: isChecked ? AppTheme.slateBlue : AppTheme.softSkyBorder,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: isChecked ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
