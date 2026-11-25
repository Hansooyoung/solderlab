import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../services/export/export_service.dart';
import '../providers/inspection_providers.dart';
import '../widgets/status_chip.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';
import 'inspection_detail_screen.dart';
import '../../core/animations/anim_kit.dart';

/// HistoryScreen: Layar Riwayat Pemeriksaan SolderLab (Search, Filter, Export)
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(inspectionsListProvider);
    final currentFilter = ref.watch(historyFilterProvider);

    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      body: SafeArea(
        child: Column(
          children: [
            // Header & Search
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Riwayat Pemeriksaan',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.slateBlueDark,
                          letterSpacing: -0.4,
                        ),
                      ),
                      // Quick Export Action
                      IconButton(
                        icon: const Icon(Icons.file_download_outlined, color: AppTheme.slateBlue),
                        tooltip: 'Ekspor Semua Riwayat (CSV)',
                        onPressed: () async {
                          final list = historyAsync.value;
                          if (list == null || list.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Tidak ada riwayat untuk diekspor.')),
                            );
                            return;
                          }
                          final path = await ExportService.exportToCsv(list);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Riwayat diekspor ke: $path'),
                                backgroundColor: AppTheme.slateBlue,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Log audit mutu solder & rekam jejak latihan teknisi',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search Box
                  Container(
                    height: 44,
                    decoration: AppTheme.cardDecoration(
                      backgroundColor: Colors.white,
                      borderColor: AppTheme.softSkyBorder,
                      radius: 12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
                            decoration: const InputDecoration(
                              hintText: 'Cari kode QC, jenis papan (SMD, Umum), atau catatan...',
                              hintStyle: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) {
                              setState(() => _searchQuery = val.trim().toLowerCase());
                              ref.read(historySearchProvider.notifier).setSearch(val.trim());
                            },
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                              ref.read(historySearchProvider.notifier).setSearch('');
                            },
                            child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Filter Pills (Semua, Lulus, Tinjau, Rework)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterPill('ALL', 'Semua', currentFilter),
                        const SizedBox(width: 8),
                        _buildFilterPill('PASS', 'Lulus', currentFilter),
                        const SizedBox(width: 8),
                        _buildFilterPill('UNCERTAIN', 'Tinjau', currentFilter),
                        const SizedBox(width: 8),
                        _buildFilterPill('FAIL', 'Rework', currentFilter),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Daftar List Riwayat
            Expanded(
              child: historyAsync.when(
                data: (inspections) {
                  // Filter berdasarkan teks pencarian
                  var filtered = inspections;
                  if (_searchQuery.isNotEmpty) {
                    filtered = filtered.where((item) {
                      final matchCode = item.inspectionCode.toLowerCase().contains(_searchQuery);
                      final matchBoard = item.boardName.toLowerCase().contains(_searchQuery) ||
                          item.boardType.toLowerCase().contains(_searchQuery);
                      final matchNotes = (item.notes ?? '').toLowerCase().contains(_searchQuery);
                      return matchCode || matchBoard || matchNotes;
                    }).toList();
                  }

                  if (filtered.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: SoldyCoachBanner(
                          mood: SoldyMood.idle,
                          badge: 'RIWAYAT KOSONG',
                          messages: [
                            _searchQuery.isNotEmpty
                                ? 'Tidak ditemukan log untuk "$_searchQuery". Coba kata kunci lain atau bersihkan pencarian.'
                                : 'Belum ada sesi QC tersimpan. Ketuk tombol Kamera untuk mulai memeriksa papan PCB bersama Soldy.',
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 6, bottom: 100),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return FadeSlideIn(
                        index: index % 8,
                        child: Dismissible(
                          key: Key('history_${item.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: AppTheme.reworkBadgeBg,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.reworkBadgeBorder),
                            ),
                            child: const Icon(Icons.delete_outline_rounded, color: AppTheme.failRed),
                          ),
                          confirmDismiss: (_) async {
                            return await showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('Hapus Riwayat?', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.slateBlueDark)),
                                content: Text('Hapus pemeriksaan #${item.inspectionCode} beserta foto buktinya?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.failRed),
                                    child: const Text('Hapus', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                          },
                          onDismissed: (_) {
                            if (item.id != null) {
                              ref.read(repositoryProvider).deleteInspection(item.id!);
                              ref.invalidate(statisticsProvider);
                              ref.invalidate(inspectionsListProvider);
                              ref.invalidate(yieldTrendProvider);
                            }
                          },
                          child: PressableScale(
                            onTap: () {
                              if (item.id != null) {
                                Navigator.push(
                                  context,
                                  SolderPageRoute(
                                    builder: (_) => InspectionDetailScreen(inspectionId: item.id!),
                                  ),
                                );
                              }
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
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '#${item.inspectionCode} • ${item.boardName}',
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
                                              fontSize: 10,
                                              useIndonesian: true,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item.totalJoints} Titik • ${item.passCount} Optimal • ${item.failCount} Perlu Rework',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatDate(item.createdAt),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.softSkyBorder),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.slateBlue)),
                error: (err, _) => Center(child: Text('Gagal memuat: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String filterKey, String label, String activeFilter) {
    final isSelected = activeFilter == filterKey;
    return PressableScale(
      onTap: () => ref.read(historyFilterProvider.notifier).setFilter(filterKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.slateBlue : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.slateBlue : AppTheme.softSkyBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : AppTheme.slateBlue,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
