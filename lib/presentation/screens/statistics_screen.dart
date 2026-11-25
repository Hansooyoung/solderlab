import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/inspection_providers.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';
import 'ipc_standard_screen.dart';
import '../../core/animations/anim_kit.dart';

/// StatisticsScreen: Layar Distribusi Defek Solder (Pareto Analysis & Actionable Insight)
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statisticsProvider);

    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      body: statsAsync.when(
        data: (stats) {
          // 100% Data Nyata dari SQLite (nol angka fallback tiruan)
          final d1 = stats.defectBreakdown['D1_BRIDGE'] ?? 0;
          final d2 = stats.defectBreakdown['D2_COLD'] ?? 0;
          final d3 = stats.defectBreakdown['D3_INSUFFICIENT'] ?? 0;
          final d4 = stats.defectBreakdown['D4_EXCESS'] ?? 0;
          final d5 = stats.defectBreakdown['D5_PINHOLE'] ?? 0;

          final totalDefects = d1 + d2 + d3 + d4 + d5;
          final d4Pct = totalDefects > 0 ? (d4 / totalDefects * 100) : 0.0;
          final d3Pct = totalDefects > 0 ? (d3 / totalDefects * 100) : 0.0;
          final d2Pct = totalDefects > 0 ? (d2 / totalDefects * 100) : 0.0;
          final d1Pct = totalDefects > 0 ? (d1 / totalDefects * 100) : 0.0;
          final d5Pct = totalDefects > 0 ? (d5 / totalDefects * 100) : 0.0;

          final ranked = [
            ('D4', 'Kelebihan Timah', d4, d4Pct, 'Kurangi durasi tempel kawat timah atau gunakan diameter 0.8mm.'),
            ('D3', 'Kurang Timah', d3, d3Pct, 'Tambahkan sedikit timah berinti flux hingga pad terlapisi penuh.'),
            ('D2', 'Solder Dingin', d2, d2Pct, 'Gunakan flux secukupnya dan panaskan pad + kaki komponen bersamaan 2–3 detik.'),
            ('D1', 'Jembatan Solder', d1, d1Pct, 'Bersihkan jembatan antar pad menggunakan desoldering wick dan flux.'),
            ('D5', 'Rongga Udara', d5, d5Pct, 'Panaskan ulang titik berongga agar uap flux terlepas sebelum timah membeku.'),
          ]..sort((a, b) => b.$3.compareTo(a.$3));

          final top1 = ranked[0];
          final top2 = ranked[1];
          final vitalFewPct = totalDefects > 0 ? (top1.$4 + top2.$4) : 0.0;
          final focusTitle = totalDefects > 0
              ? 'Fokus Utama: ${top1.$2} (${top1.$4.toStringAsFixed(1)}%)'
              : (stats.totalInspections > 0
                  ? 'Nol Cacat Tercatat'
                  : 'Belum Ada Data Inspeksi');
          final focusDesc = totalDefects > 0
              ? top1.$5
              : 'Lakukan pemindaian papan PCB dan simpan hasilnya ke log untuk melihat distribusi Pareto aktual Anda.';
          final vitalFewLabel = totalDefects > 0 ? 'VITAL FEW (${top1.$1}+${top2.$1})' : 'VITAL FEW (TOP 2)';

          return ListView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 100),
            children: [
              // Header Deskriptif
              const FadeSlideIn(
                index: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Distribusi Defek Solder',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.slateBlueDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Analisis Pareto cacat sambungan solder & prioritas tindakan teknisi',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              FadeSlideIn(
                index: 1,
                child: SoldyCoachBanner(
                  mood: totalDefects == 0
                      ? (stats.totalInspections > 0 ? SoldyMood.happy : SoldyMood.idle)
                      : SoldyMood.warning,
                  badge: 'INSIGHT PARETO SOLDY',
                  messages: totalDefects > 0
                      ? [
                          'Prioritas utama: ${top1.$2} menyumbang ${top1.$4.toStringAsFixed(1)}% dari total $totalDefects cacat tercatat.',
                          'Rekomendasi Soldy: ${top1.$5}',
                        ]
                      : const [
                          'Belum ada cacat solder tercatat. Simpan hasil pemindaian agar Soldy memetakan diagram Pareto pribadi Anda.',
                          'Buka Kamus Standar Solder untuk membandingkan bentuk meniskus ideal sebelum sesi latihan berikutnya.',
                        ],
                ),
              ),
              const SizedBox(height: 14),

              // Kontainer Diagram Pareto (5 Batang Horisontal)
              FadeSlideIn(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISTRIBUSI CACAT IPC-A-610',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 14),

                      _buildParetoBar(
                        code: 'D4',
                        name: 'Kelebihan Timah',
                        count: d4,
                        percent: d4Pct,
                        color: AppTheme.slateBlue,
                        isHighlighted: totalDefects > 0 && top1.$1 == 'D4',
                      ),
                      const SizedBox(height: 12),

                      _buildParetoBar(
                        code: 'D3',
                        name: 'Kurang Timah',
                        count: d3,
                        percent: d3Pct,
                        color: const Color(0xFF6B8EA9),
                        isHighlighted: totalDefects > 0 && top1.$1 == 'D3',
                      ),
                      const SizedBox(height: 12),

                      _buildParetoBar(
                        code: 'D2',
                        name: 'Solder Dingin',
                        count: d2,
                        percent: d2Pct,
                        color: const Color(0xFF88A9C3),
                        isHighlighted: totalDefects > 0 && top1.$1 == 'D2',
                      ),
                      const SizedBox(height: 12),

                      _buildParetoBar(
                        code: 'D1',
                        name: 'Jembatan Solder',
                        count: d1,
                        percent: d1Pct,
                        color: const Color(0xFFA8CCE8),
                        isHighlighted: totalDefects > 0 && top1.$1 == 'D1',
                      ),
                      const SizedBox(height: 12),

                      _buildParetoBar(
                        code: 'D5',
                        name: 'Rongga Udara',
                        count: d5,
                        percent: d5Pct,
                        color: const Color(0xFFD2E3F0),
                        isHighlighted: totalDefects > 0 && top1.$1 == 'D5',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Kartu Fokus Utama Dinamis
              FadeSlideIn(
                index: 2,
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
                        child: const Icon(Icons.auto_graph_rounded, color: AppTheme.slateBlue, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              focusTitle,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.slateBlueDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              focusDesc,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textPrimary,
                                height: 1.35,
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

              // KPI Row (2 Cards)
              FadeSlideIn(
                index: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: AppTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL CACAT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            CountUpText(
                              value: totalDefects.toDouble(),
                              suffix: ' Titik',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.slateBlueDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Akumulasi non-conformance',
                              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: AppTheme.cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vitalFewLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            CountUpText(
                              value: vitalFewPct,
                              decimals: 1,
                              suffix: '%',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.slateBlueDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Dominasi 2 tipe defek utama',
                              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tombol Aksi Menuju Kamus Standar Solder
              FadeSlideIn(
                index: 4,
                child: PressableScale(
                  onTap: () {
                    Navigator.push(
                      context,
                      SolderPageRoute(builder: (_) => const IpcStandardScreen()),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.slateBlue,
                      borderRadius: BorderRadius.circular(14),
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
                            'Buka Kamus Standar Solder',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.slateBlue)),
        error: (err, _) => Center(child: Text('Gagal memuat statistik: $err')),
      ),
    );
  }

  Widget _buildParetoBar({
    required String code,
    required String name,
    required int count,
    required double percent,
    required Color color,
    bool isHighlighted = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isHighlighted ? AppTheme.slateBlue : AppTheme.softSky,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isHighlighted ? Colors.white : AppTheme.slateBlueDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${percent.toStringAsFixed(1)}% ($count)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
                color: isHighlighted ? AppTheme.slateBlueDark : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedBar(
          fraction: (percent / 100).clamp(0.01, 1.0),
          color: color,
        ),
      ],
    );
  }
}
