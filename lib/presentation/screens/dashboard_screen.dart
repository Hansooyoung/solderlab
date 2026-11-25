import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../providers/inspection_providers.dart';
import '../widgets/status_chip.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';
import 'history_screen.dart';
import 'inspection_detail_screen.dart';
import 'workstation_setup_screen.dart';
import '../../core/animations/anim_kit.dart';

/// DashboardScreen: Beranda Utama SolderLab (Warm Eggshell & Modern Card Layout)
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statisticsProvider);
    final historyAsync = ref.watch(inspectionsListProvider);
    final yieldTrendAsync = ref.watch(yieldTrendProvider);

    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      body: RefreshIndicator(
        color: AppTheme.slateBlue,
        backgroundColor: Colors.white,
        onRefresh: () async {
          ref.invalidate(statisticsProvider);
          ref.invalidate(inspectionsListProvider);
          ref.invalidate(yieldTrendProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 100),
          children: [
            // 1. Ringkasan Aktivitas QC Nyata (Tanpa data hardcoded)
            Builder(
              builder: (context) {
                final stats = statsAsync.value;
                final list = historyAsync.value ?? const [];
                final activeDays = list
                    .map((i) => i.inspectedAt.length >= 10 ? i.inspectedAt.substring(0, 10) : '')
                    .where((d) => d.isNotEmpty)
                    .toSet()
                    .length;
                final hasData = stats != null && stats.totalInspections > 0;
                final mood = !hasData
                    ? SoldyMood.idle
                    : (stats.overallYieldRate >= 85.0
                        ? SoldyMood.happy
                        : (stats.overallYieldRate >= 60.0 ? SoldyMood.warning : SoldyMood.alert));
                final coachMessages = hasData
                    ? <String>[
                        'Aktivitas QC: $activeDays Hari Tercatat • ${stats.totalInspections} sesi selesai dengan tingkat rapi ${stats.overallYieldRate.toStringAsFixed(1)}%.',
                        'Soldy-Net-V6 aktif menyaring kaki komponen panjang yang belum dipotong agar hasil cek fokus pada sambungan timah.',
                        'Tip Soldy: Gunakan cahaya meja netral tanpa silau tajam dan pegang kamera tegak 90° di atas papan PCB.',
                      ]
                    : const <String>[
                        'Hai! Aku Soldy AI. Ketuk tombol di bawah untuk mulai inspeksi titik solder di papan PCB apa pun (THT, IC, Header, SMD).',
                        'Soldy-Net-V6 otomatis menolak kawat kaki komponen sebelum dipotong dan permukaan beton meja kerja.',
                        'Tip Praktik: Panaskan pad & kaki komponen bersamaan 2–3 detik agar timah membentuk meniskus cekung mengilap.',
                      ];

                return FadeSlideIn(
                  index: 0,
                  child: SoldyCoachBanner(
                    mood: mood,
                    badge: hasData ? 'RINGKASAN SOLDY AI' : 'SOLDY AI V6 SIAP',
                    messages: coachMessages,
                    actionLabel: hasData ? 'Scan Papan Baru' : null,
                    onActionTap: hasData
                        ? () {
                            Navigator.push(
                              context,
                              SolderPageRoute(builder: (_) => const WorkstationSetupScreen()),
                            );
                          }
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // 2. 2 KPI Boxes (Side by Side)
            statsAsync.when(
              data: (stats) {
                final totalBoards = stats.totalInspections;
                final totalJoints = stats.totalJointsInspected;
                final yieldRate = stats.totalInspections > 0 ? stats.overallYieldRate : 100.0;
                final totalFail = stats.totalFailJoints;
                final totalUncertain = stats.totalUncertainJoints;

                String topDefectLabel = 'Belum ada cacat tercatat';
                if (totalFail > 0) {
                  String? topCode;
                  int topCount = 0;
                  stats.defectBreakdown.forEach((k, v) {
                    if (v > topCount) {
                      topCount = v;
                      topCode = k;
                    }
                  });
                  if (topCode != null) {
                    const labels = {
                      'D1_BRIDGE': 'Jembatan Solder D1',
                      'D2_COLD': 'Solder Dingin D2',
                      'D3_INSUFFICIENT': 'Kurang Timah D3',
                      'D4_EXCESS': 'Kelebihan Timah D4',
                      'D5_PINHOLE': 'Rongga Udara D5',
                    };
                    topDefectLabel = '$totalFail Titik Rework (Terbanyak: ${labels[topCode] ?? topCode})';
                  } else {
                    topDefectLabel = '$totalFail Titik Perlu Rework';
                  }
                } else if (totalUncertain > 0) {
                  topDefectLabel = '$totalUncertain Titik Perlu Tinjauan Manual';
                } else if (totalJoints > 0) {
                  topDefectLabel = 'Semua $totalJoints titik lulus kriteria visual';
                }

                return Column(
                  children: [
                    FadeSlideIn(
                      index: 1,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildKpiBox(
                              title: 'PAPAN DIPERIKSA',
                              numericValue: totalBoards.toDouble(),
                              suffix: ' Papan',
                              subtitle: 'Akumulasi uji modul',
                              icon: Icons.memory_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildKpiBox(
                              title: 'SAMBUNGAN SOLDER',
                              numericValue: totalJoints.toDouble(),
                              suffix: ' Kaki',
                              subtitle: 'Titik pad dievaluasi',
                              icon: Icons.grain_rounded,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. Ringkasan Kerapian Mutu
                    FadeSlideIn(
                      index: 2,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.cardDecoration(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.softSky,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.verified_outlined, color: AppTheme.slateBlue, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Flexible(
                                        child: Text(
                                          'Tingkat Kerapian: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      CountUpText(
                                        value: yieldRate,
                                        decimals: 1,
                                        suffix: '%',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.slateBlueDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    topDefectLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (totalBoards > 0) ...[
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        index: 3,
                        child: yieldTrendAsync.when(
                          data: (trend) => Container(
                            padding: const EdgeInsets.all(16),
                            decoration: AppTheme.cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'TREN MUTU HARIAN',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.textMuted,
                                          letterSpacing: 0.7,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppTheme.softSky,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        trend.length >= 2 ? '${trend.length} Hari' : 'Hari ke-1',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.slateBlueDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                AnimatedSparkline(
                                  values: trend,
                                  color: AppTheme.slateBlue,
                                  height: 52,
                                ),
                              ],
                            ),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.slateBlue)),
              error: (_, _) => const SizedBox(),
            ),
            const SizedBox(height: 20),

            // 4. Quick Action Button
            FadeSlideIn(
              index: 4,
              child: PressableScale(
                onTap: () {
                  Navigator.push(
                    context,
                    SolderPageRoute(builder: (_) => const WorkstationSetupScreen()),
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
                      Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Mulai Pemeriksaan Solder Baru',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 5. Riwayat Pemeriksaan Terkini
            FadeSlideIn(
              index: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'RIWAYAT PEMERIKSAAN TERKINI',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateBlue,
                        letterSpacing: 0.6,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressableScale(
                    onTap: () {
                      Navigator.push(
                        context,
                        SolderPageRoute(builder: (_) => const HistoryScreen()),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Text(
                        'Lihat Semua →',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slateBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Daftar Kartu Riwayat Terkini
            historyAsync.when(
              data: (inspections) {
                if (inspections.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.cardDecoration(),
                    child: const Center(
                      child: Text(
                        'Belum ada data pemeriksaan tersimpan.\nKetuk tombol di atas untuk memulai pemindaian pertama.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                      ),
                    ),
                  );
                }

                final displayList = inspections.take(4).toList();
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = displayList[index];
                    return FadeSlideIn(
                      index: 5 + index,
                      child: PressableScale(
                        onTap: () {
                          Navigator.push(
                            context,
                            SolderPageRoute(
                              builder: (_) => InspectionDetailScreen(inspectionId: item.id!),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AppTheme.cardDecoration(),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            '#${item.inspectionCode}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.slateBlueDark,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        StatusChip(
                                          status: item.overallStatus,
                                          useIndonesian: true,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${item.boardName} • ${item.totalJoints} Titik (${item.passCount} Optimal, ${item.failCount} Perlu Rework)',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.softSkyBorder),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
              error: (_, _) => const SizedBox(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiBox({
    required String title,
    required double numericValue,
    required String suffix,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.6,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: AppTheme.slateBlue),
            ],
          ),
          const SizedBox(height: 8),
          CountUpText(
            value: numericValue,
            suffix: suffix,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppTheme.slateBlueDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
