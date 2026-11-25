import 'package:flutter/material.dart';
import '../../core/animations/anim_kit.dart';
import '../../core/theme/app_theme.dart';

/// IpcStandardScreen: Kamus Standar Solder (Visual Quality Reference & IPC-A-610 Guide)
class IpcStandardScreen extends StatelessWidget {
  const IpcStandardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      body: ListView(
        padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 100),
        children: [
          // Header Judul
          const FadeSlideIn(
            index: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kamus Standar Solder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.slateBlueDark,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kriteria visual mutu ideal & klasifikasi cacat solder',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 1. Card 0: Acuan Mutu Sempurna (Soft Sky Highlight)
          FadeSlideIn(
            index: 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(
                backgroundColor: AppTheme.softSky,
                borderColor: AppTheme.softSkyBorder,
              ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.star_rounded, color: AppTheme.slateBlue, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[ACUAN MUTU] Fillet Cekung Sempurna',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateBlueDark,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Meniskus cekung mengilap dengan sudut kontak wetting < 90°. Timah membasahi pad tembaga dan kaki komponen secara merata 360° tanpa gumpalan.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textPrimary,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Kriteria akseptansi ideal untuk integritas sirkuit jangka panjang.',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            ),
          ),
          const SizedBox(height: 14),

          const FadeSlideIn(
            index: 2,
            child: Text(
              'KLASIFIKASI CACAT SOLDER ELEKTRONIKA',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Card 1: D1 Jembatan Solder
          FadeSlideIn(
            index: 2,
            child: _buildDefectCard(
              badge: '[CACAT D1]',
              title: 'Jembatan Solder (Solder Bridge)',
              description: 'Hubungan timah tak sengaja antar dua pad atau jalur konduktor yang memicu korsleting listrik.',
              reworkSolution: 'Solusi: Serap jembatan timah menggunakan copper wick atau penyedot timah ber-flux.',
              icon: Icons.alt_route_rounded,
            ),
          ),
          const SizedBox(height: 10),

          // 3. Card 2: D2 Solder Dingin
          FadeSlideIn(
            index: 3,
            child: _buildDefectCard(
              badge: '[CACAT D2]',
              title: 'Solder Dingin (Cold Joint)',
              description: 'Permukaan timah kusam, kasar, atau retak akibat suhu solder kurang atau PCB bergoyang sebelum timah beku.',
              reworkSolution: 'Solusi: Oleskan sedikit pasta flux lalu panaskan ulang pad selama 2-3 detik hingga timah mengalir licin.',
              icon: Icons.ac_unit_rounded,
            ),
          ),
          const SizedBox(height: 10),

          // 4. Card 3: D3 Kurang Timah
          FadeSlideIn(
            index: 4,
            child: _buildDefectCard(
              badge: '[CACAT D3]',
              title: 'Kurang Timah (Insufficient Solder)',
              description: 'Volume timah terlalu sedikit sehingga pad tembaga belum tertutup 360° atau kekuatan mekanik sambungan rapuh.',
              reworkSolution: 'Solusi: Panaskan pad dan tambahkan kawat timah 0.8mm berinti flux selama 1 detik.',
              icon: Icons.trending_down_rounded,
            ),
          ),
          const SizedBox(height: 10),

          // 5. Card 4: D4 Kelebihan Timah
          FadeSlideIn(
            index: 5,
            child: _buildDefectCard(
              badge: '[CACAT D4]',
              title: 'Kelebihan Timah (Excess Solder)',
              description: 'Gumpalan cembung bulat berlebih menutupi bentuk kaki komponen (> 90° wetting angle).',
              reworkSolution: 'Solusi: Tempelkan pita tembaga (desoldering wick) ber-flux ke pad untuk menyerap kelebihan timah.',
              icon: Icons.bubble_chart_rounded,
              isVitalFew: true,
            ),
          ),
          const SizedBox(height: 16),

          // 6. Footer Note IPC-A-610
          FadeSlideIn(
            index: 6,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.softSkyBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 18, color: AppTheme.slateBlue),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mengacu pada standar internasional IPC-A-610 Kelas 2 untuk keandalan perakitan elektronik komersial.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefectCard({
    required String badge,
    required String title,
    required String description,
    required String reworkSolution,
    required IconData icon,
    bool isVitalFew = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(
        backgroundColor: Colors.white,
        borderColor: isVitalFew ? AppTheme.softSkyBorder : AppTheme.softSkyBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isVitalFew ? AppTheme.softSky : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isVitalFew ? AppTheme.slateBlue : AppTheme.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isVitalFew ? AppTheme.slateBlue : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.slateBlueDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    reworkSolution,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
