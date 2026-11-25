import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/defect_type_model.dart';
import '../../data/models/inspection_joint_model.dart';
import '../../data/models/inspection_model.dart';
import '../../services/ai/ai_inference_service.dart';
import '../../services/export/export_service.dart';
import '../providers/inspection_providers.dart';
import '../widgets/status_chip.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../features/shared/widgets/soldy_coach_banner.dart';
import 'camera_scan_screen.dart';
import '../../core/animations/anim_kit.dart';

/// Layar Tampilan Hasil Analisis SolderLab
class InspectionResultScreen extends ConsumerStatefulWidget {
  final MultiSolderInferenceResult result;
  final Uint8List rawImageBytes;

  const InspectionResultScreen({
    super.key,
    required this.result,
    required this.rawImageBytes,
  });

  @override
  ConsumerState<InspectionResultScreen> createState() => _InspectionResultScreenState();
}

class _InspectionResultScreenState extends ConsumerState<InspectionResultScreen> {
  bool _isSaving = false;
  bool _isSaved = false;
  InspectionModel? _currentInspection;

  @override
  void initState() {
    super.initState();
    _currentInspection = widget.result.inspection;
  }

  Future<void> _saveToDatabase() async {
    if (_currentInspection == null || _isSaved) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final repo = ref.read(repositoryProvider);
      final id = await repo.saveInspection(_currentInspection!);
      _currentInspection = _currentInspection!.copyWith(id: id);

      ref.invalidate(statisticsProvider);
      ref.invalidate(inspectionsListProvider);
      ref.invalidate(yieldTrendProvider);

      setState(() {
        _isSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pemeriksaan berhasil disimpan ke basis data SQLite lokal.'),
            backgroundColor: AppTheme.slateBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan pemeriksaan: $e'),
            backgroundColor: AppTheme.failRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  static const List<DefectTypeModel> _fallbackDefectTypes = [
    DefectTypeModel(id: 1, defectCode: 'PASS_NORMAL', defectName: 'Normal Solder (PASS)', description: 'Meniskus cekung ideal', category: 'CONFORMANCE', qualityStatus: 'PASS'),
    DefectTypeModel(id: 2, defectCode: 'D1_BRIDGE', defectName: 'Jembatan Solder (Bridge)', description: 'Hubung singkat antar pad', category: 'VOLUME', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 3, defectCode: 'D2_COLD', defectName: 'Solder Dingin (Cold Joint)', description: 'Permukaan kusam atau retak', category: 'THERMAL', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 4, defectCode: 'D3_INSUFFICIENT', defectName: 'Kurang Timah (Insufficient)', description: 'Pembasahan timah tidak cukup', category: 'WETTING', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 5, defectCode: 'D4_EXCESS', defectName: 'Kelebihan Timah (Excess Solder)', description: 'Gumpalan timah cembung berlebih', category: 'VOLUME', qualityStatus: 'FAIL'),
    DefectTypeModel(id: 6, defectCode: 'D5_PINHOLE', defectName: 'Lubang Jarum (Pinhole)', description: 'Rongga gas mikro', category: 'THERMAL', qualityStatus: 'FAIL'),
  ];

  Future<void> _overrideJointStatus(int jointListIndex) async {
    final insp = _currentInspection;
    if (insp == null) return;
    final joint = insp.joints[jointListIndex];
    final defectTypes = ref.read(defectTypesProvider).value ?? _fallbackDefectTypes;

    final selected = await showModalBottomSheet<DefectTypeModel>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Koreksi Manual • Kaki #${joint.jointIndex}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.slateBlueDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Prediksi AI: ${joint.defectType?.defectName ?? joint.result} (${(joint.confidence * 100).toStringAsFixed(0)}%)',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                ...defectTypes.map((dt) {
                  final isPassOption = dt.isPass;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isPassOption ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                      color: isPassOption ? AppTheme.passGreen : AppTheme.failRed,
                    ),
                    title: Text(
                      dt.defectName,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    ),
                    subtitle: Text(
                      dt.defectCode,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
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
    updatedJoints[jointListIndex] = joint.copyWith(
      result: selected.isPass ? AppConstants.statusPass : AppConstants.statusFail,
      defectTypeId: selected.id,
      defectType: selected,
      confidence: 1.0,
    );

    int passCount = 0;
    int failCount = 0;
    int uncertainCount = 0;
    for (final j in updatedJoints) {
      if (j.isPass) {
        passCount++;
      } else if (j.isFail) {
        failCount++;
      } else {
        uncertainCount++;
      }
    }

    String overall = AppConstants.statusPass;
    if (failCount > 0) {
      overall = AppConstants.statusFail;
    } else if (uncertainCount > 0 || updatedJoints.isEmpty) {
      overall = AppConstants.statusUncertain;
    }

    final updatedInspection = insp.copyWith(
      passCount: passCount,
      failCount: failCount,
      uncertainCount: uncertainCount,
      overallResult: overall,
      manualReviewStatus: true,
      joints: updatedJoints,
    );

    setState(() {
      _currentInspection = updatedInspection;
    });

    if (_isSaved && updatedInspection.id != null) {
      await ref.read(repositoryProvider).updateInspectionReview(updatedInspection);
      ref.invalidate(statisticsProvider);
      ref.invalidate(inspectionsListProvider);
      ref.invalidate(yieldTrendProvider);
    }
  }

  Future<void> _exportPdf() async {
    if (_currentInspection == null) return;
    try {
      final path = await ExportService.exportInspectionToPdf(_currentInspection!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF berhasil dibuat: $path'),
            backgroundColor: AppTheme.slateBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ekspor gagal: $e')),
        );
      }
    }
  }

  Future<void> _handleRetakeOrRework() async {
    if (!_isSaved && _currentInspection != null) {
      await _saveToDatabase();
    }
    if (!mounted) return;
    final isFail = !(_currentInspection?.isPass ?? true);
    Navigator.pushReplacement(
      context,
      SolderPageRoute(
        builder: (_) => CameraScanScreen(
          isRework: isFail,
          parentInspectionId: isFail ? _currentInspection?.id : null,
          boardType: _currentInspection?.boardType ?? AppConstants.boardGeneralPcb,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final insp = _currentInspection;
    if (insp == null) {
      return const Scaffold(
        body: Center(child: Text('Data pemeriksaan tidak tersedia.')),
      );
    }

    final isPass = insp.isPass;
    final isUncertain = insp.isUncertain;
    final Color bannerBg = isPass
        ? AppTheme.softSky
        : (isUncertain ? const Color(0xFFFFFBEB) : AppTheme.reworkBadgeBg);
    final Color bannerBorder = isPass
        ? AppTheme.softSkyBorder
        : (isUncertain ? const Color(0xFFFDE68A) : AppTheme.reworkBadgeBorder);
    final Color bannerTitleColor = isPass
        ? AppTheme.slateBlueDark
        : (isUncertain ? const Color(0xFFB45309) : AppTheme.failRed);
    final String bannerHeadline = isPass
        ? 'Lulus Standar: Solder Optimal'
        : (isUncertain
            ? 'Perlu Verifikasi Manual (${insp.uncertainCount} Titik)'
            : 'Terdapat ${insp.failCount} Titik Solder Perlu Rework');
    final String bannerBody = isPass
        ? 'Seluruh ${insp.totalJoints} titik sambungan memenuhi kriteria visual meniskus ideal (< 90°).'
        : (isUncertain
            ? '${insp.passCount} titik optimal • ${insp.uncertainCount} titik memiliki keyakinan rendah; ketuk kartu untuk konfirmasi manual.'
            : '${insp.passCount} titik optimal • ${insp.failCount} titik perlu rework${insp.uncertainCount > 0 ? " • ${insp.uncertainCount} perlu tinjauan" : ""}.');

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
          'Hasil Pemeriksaan Solder',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.slateBlueDark,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.slateBlue),
            tooltip: 'Ekspor PDF',
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // 1. Header Banner Status
                  FadeSlideIn(
                    index: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: bannerBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: bannerBorder,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1052738D),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '#${insp.inspectionCode} • ${insp.boardName}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.slateBlue,
                                    letterSpacing: 0.6,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PopIn(
                                child: StatusChip(
                                  status: insp.overallStatus,
                                  useIndonesian: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            bannerHeadline,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: bannerTitleColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bannerBody,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textPrimary,
                              height: 1.35,
                            ),
                          ),
                          if (widget.result.filteredNonSolderCount > 0) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.softSkyBorder),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.filter_alt_outlined, size: 14, color: AppTheme.slateBlue),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Soldy AI menyaring ${widget.result.filteredNonSolderCount} kaki komponen utuh / non-solder',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.slateBlueDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Kartu Analisa Soldy AI Interaktif (Mood & Kiat Perbaikan)
                  FadeSlideIn(
                    index: 1,
                    child: SoldyCoachBanner(
                      mood: isPass
                          ? SoldyMood.happy
                          : (isUncertain ? SoldyMood.warning : SoldyMood.alert),
                      badge: 'ANALISIS SOLDY AI',
                      messages: isPass
                          ? [
                              'Mantap! Seluruh ${insp.totalJoints} sambungan timah tampak bersih, cekung, dan menempel kuat di pad PCB.',
                              'Kamu tetap dapat mengetuk kartu kaki di bawah jika ingin mengoreksi atau menyimpan log inspeksi.',
                            ]
                          : [
                              'Soldy menemukan ${insp.failCount} titik perlu diperbaiki. Ketuk kartu titik mana pun untuk melihat atau koreksi status manual.',
                              'Setelah merapikan solder dengan flux/wick, bersihkan sisa flux dengan IPA lalu gunakan tombol Foto Ulang Rework.',
                            ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Tiga Kotak Metrik Ringkasan
                  FadeSlideIn(
                    index: 1,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildMetricBox(
                            title: 'TOTAL TITIK',
                            numericValue: insp.totalJoints,
                            subtitle: 'Kaki diperiksa',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricBox(
                            title: 'OPTIMAL',
                            numericValue: insp.passCount,
                            subtitle: '${insp.yieldRate.toStringAsFixed(0)}% Sesuai',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricBox(
                            title: 'PERLU REWORK',
                            numericValue: insp.failCount,
                            subtitle: insp.failCount > 0 ? 'Perlu perbaikan' : 'Nol defek',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Citra Hasil Foto jika ada (ketuk untuk perbesar interaktif)
                  if (insp.imagePath.isNotEmpty && File(insp.imagePath).existsSync()) ...[
                    FadeSlideIn(
                      index: 2,
                      child: PressableScale(
                        onTap: () => _openFullImageDialog(context, insp.imagePath),
                        child: Container(
                          width: double.infinity,
                          height: 180,
                          decoration: AppTheme.cardDecoration(),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(insp.imagePath),
                                fit: BoxFit.cover,
                              ),
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
                    const SizedBox(height: 20),
                  ],

                  // 4. Daftar Rework / Rincian Titik Solder
                  Text(
                    insp.failCount > 0 ? 'TITIK SAMBUNGAN PERLU REWORK' : 'RINCIAN SEMUA SAMBUNGAN',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlue,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),

                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: insp.joints.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final joint = insp.joints[index];
                      return FadeSlideIn(
                        index: 3 + (index % 8),
                        child: _buildJointCard(joint, index),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 5. Prosedur Verifikasi Ulang
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.cardDecoration(
                      backgroundColor: Colors.white,
                      borderColor: AppTheme.softSkyBorder,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppTheme.slateBlue, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PROSEDUR VERIFIKASI ULANG',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slateBlue,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Setelah menyolder ulang titik di atas, bersihkan residu pasta flux dengan alkohol isopropil (IPA) lalu lakukan foto ulang untuk memastikan akseptansi mutu.',
                                style: TextStyle(
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
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Bottom Action Dock
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.softSkyBorder, width: 1)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _handleRetakeOrRework,
                        icon: Icon(isPass ? Icons.add_a_photo_outlined : Icons.build_circle_outlined, size: 18),
                        label: Text(
                          isPass ? 'Foto PCB Lain' : 'Foto Ulang Rework',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isPass ? AppTheme.slateBlue : AppTheme.failRed,
                          side: BorderSide(color: isPass ? AppTheme.softSkyBorder : AppTheme.failRed, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: (_isSaved || _isSaving) ? null : _saveToDatabase,
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : _isSaved
                                ? const PopIn(child: Icon(Icons.check_circle_rounded, size: 18))
                                : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _isSaving ? 'Menyimpan...' : (_isSaved ? 'Tersimpan ✓' : 'Simpan ke Log →'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isSaved ? AppTheme.slateBlue : AppTheme.slateBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullImageDialog(BuildContext context, String imagePath) {
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

  Widget _buildMetricBox({required String title, required int numericValue, required String subtitle}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          CountUpText(
            value: numericValue.toDouble(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.slateBlueDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJointCard(InspectionJointModel joint, int index) {
    final isJointPass = joint.isPass;
    final isJointUncertain = joint.isUncertain;
    final Color cardBorder = isJointPass
        ? AppTheme.softSkyBorder
        : (isJointUncertain ? const Color(0xFFFDE68A) : AppTheme.reworkBadgeBorder);
    final Color iconBg = isJointPass
        ? AppTheme.softSky
        : (isJointUncertain ? const Color(0xFFFEF3C7) : AppTheme.reworkBadgeBg);
    final Color iconColor = isJointPass
        ? AppTheme.slateBlue
        : (isJointUncertain ? const Color(0xFFB45309) : AppTheme.failRed);
    final IconData iconData = isJointPass
        ? Icons.check_circle_outline_rounded
        : (isJointUncertain ? Icons.help_outline_rounded : Icons.build_circle_outlined);

    return InkWell(
      onTap: () => _overrideJointStatus(index),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(
          backgroundColor: Colors.white,
          borderColor: cardBorder,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                iconData,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Kaki #${joint.jointIndex} • Pad Sambungan',
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
                        status: joint.result,
                        fontSize: 10,
                        useIndonesian: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          joint.defectType?.defectName ??
                              (isJointPass
                                  ? 'Meniskus Cekung Ideal (< 90°)'
                                  : (isJointUncertain ? 'Perlu Verifikasi Operator' : 'Perlu Rework')),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isJointPass ? AppTheme.textSecondary : iconColor,
                          ),
                        ),
                      ),
                      Text(
                        '${(joint.confidence * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isJointUncertain
                        ? 'Keyakinan AI di bawah ambang. Ketuk kartu ini untuk menetapkan status manual.'
                        : _getReworkRecommendation(joint.defectCode, isJointPass),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Ketuk untuk verifikasi / koreksi status',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.slateBlue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getReworkRecommendation(String? defectCode, bool isPass) {
    if (isPass) return 'Permukaan timah mengilap & membasahi pad dengan sempurna.';
    switch (defectCode) {
      case 'D1_BRIDGE':
        return 'Tindakan: Gunakan desoldering wick / atraktor untuk memisahkan timah yang menyatu.';
      case 'D2_COLD':
        return 'Tindakan: Beri sedikit pasta flux lalu panaskan pad selama 2-3 detik hingga timah mengalir rata.';
      case 'D3_INSUFFICIENT':
        return 'Tindakan: Tambahkan sedikit timah 0.8mm berinti flux dan panaskan pad selama 1 detik.';
      case 'D4_EXCESS':
        return 'Tindakan: Sentuh mata solder hangat ke pad dan serap timah berlebih menggunakan copper wick.';
      default:
        return 'Tindakan: Lakukan solder ulang sesuai kriteria IPC-A-610.';
    }
  }
}
