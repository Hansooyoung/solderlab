import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/defect_type_model.dart';
import '../../data/models/inspection_joint_model.dart';
import '../../data/models/inspection_model.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';
import '../../services/export/export_service.dart';
import '../providers/inspection_providers.dart';
import '../widgets/status_chip.dart';
import 'camera_scan_screen.dart';
import '../../core/animations/anim_kit.dart';

/// Halaman Rincian Riwayat Inspeksi SolderLab dengan koreksi status interaktif & ringkasan Soldy AI
class InspectionDetailScreen extends ConsumerStatefulWidget {
  final int inspectionId;

  const InspectionDetailScreen({super.key, required this.inspectionId});

  @override
  ConsumerState<InspectionDetailScreen> createState() => _InspectionDetailScreenState();
}

class _InspectionDetailScreenState extends ConsumerState<InspectionDetailScreen> {
  InspectionModel? _item;
  bool _loading = true;

  static const List<DefectTypeModel> _fallbackDefectTypes = [
    DefectTypeModel(id: 1, defectCode: 'PASS_NORMAL', defectName: 'Normal Solder Joint', description: 'Meniskus cekung ideal', category: 'CONFORMANCE', qualityStatus: 'PASS'),
    DefectTypeModel(id: 2, defectCode: 'D1_BRIDGE', defectName: 'Solder Bridging', description: 'Hubung singkat antar pad', category: 'VOLUME', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 3, defectCode: 'D2_COLD', defectName: 'Cold / Disturbed Solder', description: 'Permukaan kusam atau retak', category: 'THERMAL', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 4, defectCode: 'D3_INSUFFICIENT', defectName: 'Insufficient Wetting / Solder', description: 'Pembasahan timah tidak cukup', category: 'WETTING', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 5, defectCode: 'D4_EXCESS', defectName: 'Excess Solder', description: 'Gumpalan timah cembung berlebih', category: 'VOLUME', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 6, defectCode: 'D5_PINHOLE', defectName: 'Pin Holes / Blow Holes', description: 'Rongga gas mikro', category: 'THERMAL', qualityStatus: 'FAIL'),
  ];

  @override
  void initState() {
    super.initState();
    _loadInspection();
  }

  Future<void> _loadInspection() async {
    final data = await ref.read(repositoryProvider).getInspectionById(widget.inspectionId);
    if (mounted) {
      setState(() {
        _item = data;
        _loading = false;
      });
    }
  }

  Future<void> _overrideSavedJoint(int jointIdx) async {
    final insp = _item;
    if (insp == null) return;
    final joint = insp.joints[jointIdx];
    final defectTypes = ref.read(defectTypesProvider).value ?? _fallbackDefectTypes;

    final selected = await showModalBottomSheet<DefectTypeModel>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Koreksi Manual • Titik #${joint.jointIndex}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.slateBlueDark),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status saat ini: ${joint.defectType?.defectName ?? joint.result} (${(joint.confidence * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                ...defectTypes.map((dt) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      dt.isPass ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                      color: dt.isPass ? AppTheme.passGreen : AppTheme.failRed,
                    ),
                    title: Text(dt.defectName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(dt.defectCode, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    onTap: () => Navigator.pop(ctx, dt),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;

    final updatedJoints = List<InspectionJointModel>.from(insp.joints);
    updatedJoints[jointIdx] = joint.copyWith(
      result: selected.isPass ? AppConstants.statusPass : AppConstants.statusFail,
      defectTypeId: selected.id,
      defectType: selected,
      confidence: 1.0,
    );

    int passC = 0, failC = 0, uncC = 0;
    for (final j in updatedJoints) {
      if (j.isPass) {
        passC++;
      } else if (j.isFail) {
        failC++;
      } else {
        uncC++;
      }
    }

    String overall = AppConstants.statusPass;
    if (failC > 0) {
      overall = AppConstants.statusFail;
    } else if (uncC > 0 || updatedJoints.isEmpty) {
      overall = AppConstants.statusUncertain;
    }

    final updated = insp.copyWith(
      passCount: passC,
      failCount: failC,
      uncertainCount: uncC,
      overallResult: overall,
      manualReviewStatus: true,
      joints: updatedJoints,
    );

    await ref.read(repositoryProvider).updateInspectionReview(updated);
    ref.invalidate(statisticsProvider);
    ref.invalidate(inspectionsListProvider);
    ref.invalidate(yieldTrendProvider);

    if (mounted) {
      setState(() => _item = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Titik #${joint.jointIndex} diperbarui ke ${selected.defectCode}.'),
          backgroundColor: AppTheme.slateBlue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.warmEggshell,
        body: Center(child: CircularProgressIndicator(color: AppTheme.slateBlue)),
      );
    }

    final item = _item;
    if (item == null) {
      return Scaffold(
        backgroundColor: AppTheme.warmEggshell,
        appBar: AppBar(title: const Text('Detail Pemeriksaan')),
        body: const Center(child: Text('Data inspeksi tidak ditemukan.')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      appBar: AppBar(
        backgroundColor: AppTheme.warmEggshell,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.slateBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '#${item.inspectionCode}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.slateBlueDark,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.slateBlue),
            tooltip: 'Ekspor PDF',
            onPressed: () async {
              final path = await ExportService.exportInspectionToPdf(item);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Laporan PDF: $path'),
                    backgroundColor: AppTheme.slateBlue,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Status Card
            FadeSlideIn(
              index: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(
                  backgroundColor: item.isPass ? AppTheme.softSky : AppTheme.reworkBadgeBg,
                  borderColor: item.isPass ? AppTheme.softSkyBorder : AppTheme.reworkBadgeBorder,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.boardName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppTheme.slateBlueDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Waktu: ${item.inspectedAt}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopIn(child: StatusChip(status: item.overallStatus, useIndonesian: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Ringkasan Interaktif Soldy
            FadeSlideIn(
              index: 1,
              child: SoldyCoachBanner(
                mood: item.isPass ? SoldyMood.happy : (item.failCount > 0 ? SoldyMood.alert : SoldyMood.warning),
                badge: 'CATATAN AUDIT SOLDY',
                messages: [
                  item.isPass
                      ? 'Skor kerapian ${item.yieldRate.toStringAsFixed(1)}% (${item.passCount}/${item.totalJoints} titik lulus visual).'
                      : 'Terdapat ${item.failCount} titik perlu rework. Ketuk kartu titik di bawah jika ingin mengoreksi label secara manual.',
                  if (item.notes != null && item.notes!.isNotEmpty) item.notes!,
                  'Gunakan tombol di bawah kapan saja untuk memindai ulang papan ini setelah penyolderan ulang.',
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Citra Penuh Beranotasi (ketuk untuk perbesar)
            if (item.imagePath.isNotEmpty && File(item.imagePath).existsSync()) ...[
              FadeSlideIn(
                index: 1,
                child: PressableScale(
                  onTap: () => _openImagePreview(context, item.imagePath),
                  child: Container(
                    width: double.infinity,
                    height: 200,
                    decoration: AppTheme.cardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(item.imagePath), fit: BoxFit.cover),
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                                SizedBox(width: 4),
                                Text('Perbesar', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Metadata Card
            FadeSlideIn(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(),
                child: Column(
                  children: [
                    _rowMeta('Total Sambungan', '${item.totalJoints} Titik'),
                    const Divider(height: 14),
                    _rowMeta('Kondisi Solder', '${item.passCount} Optimal • ${item.failCount} Perlu Rework'),
                    const Divider(height: 14),
                    _rowMeta('Tingkat Kerapian', '${item.yieldRate.toStringAsFixed(1)}%'),
                    const Divider(height: 14),
                    _rowMeta('Latensi Mesin AI', '${item.totalInferenceTimeMs} ms (${item.modelVersion})'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Daftar Titik Solder (Ketuk untuk koreksi)
            const FadeSlideIn(
              index: 3,
              child: Text(
                'RINCIAN SAMBUNGAN SOLDER (KETUK KOREKSI)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.slateBlue,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 10),

            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: item.joints.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final joint = item.joints[index];
                return FadeSlideIn(
                  index: 3 + (index % 8),
                  child: InkWell(
                    onTap: () => _overrideSavedJoint(index),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: AppTheme.cardDecoration(),
                      child: Row(
                        children: [
                          if (joint.cropImagePath != null && File(joint.cropImagePath!).existsSync())
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(joint.cropImagePath!), width: 44, height: 44, fit: BoxFit.cover),
                            )
                          else
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppTheme.softSky,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.grain_rounded, color: AppTheme.slateBlue, size: 20),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Titik Solder #${joint.jointIndex}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.slateBlueDark),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  joint.defectType?.defectName ?? (joint.isPass ? 'Meniskus Cekung Sesuai Standar' : 'Perlu Tinjauan'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: joint.isPass ? AppTheme.textSecondary : AppTheme.failRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusChip(status: joint.result, fontSize: 10, useIndonesian: true),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.softSkyBorder, width: 1)),
        ),
        child: SafeArea(
          child: PressableScale(
            onTap: () {
              Navigator.push(
                context,
                SolderPageRoute(
                  builder: (_) => CameraScanScreen(
                    isRework: true,
                    parentInspectionId: item.id,
                    boardType: item.boardType,
                  ),
                ),
              );
            },
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: AppTheme.slateBlue,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.slateBlue.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt_rounded, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Foto Ulang / Rework Solder Ini',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openImagePreview(BuildContext context, String imagePath) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.5,
              child: Image.file(File(imagePath), fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowMeta(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.slateBlueDark),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
