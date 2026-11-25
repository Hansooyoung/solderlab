import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/bounding_box.dart';
import '../../core/utils/image_quality_checker.dart';
import '../../data/models/defect_type_model.dart';
import '../../data/models/inspection_joint_model.dart';
import '../../data/models/inspection_model.dart';
import 'solder_localizer_service.dart';
import 'solder_model_engine.dart';

/// Hasil prapemeriksaan tangkapan kamera + deteksi titik bebas kaki komponen di background Isolate.
class CapturePrecheckResult {
  final bool isQualityPass;
  final String qualityMessage;
  final List<NormalizedBoundingBox> detectedBoxes;
  final int rawCandidatesCount;
  final int filteredNonSolderCount;
  final String? optimizedImagePath;
  final int detectLatencyMs;

  const CapturePrecheckResult({
    required this.isQualityPass,
    required this.qualityMessage,
    required this.detectedBoxes,
    this.rawCandidatesCount = 0,
    this.filteredNonSolderCount = 0,
    this.optimizedImagePath,
    required this.detectLatencyMs,
  });
}

/// Hasil Lengkap Pipeline Inferensi Multi-Sambungan Solder pada Satu Papan PCB
class MultiSolderInferenceResult {
  final bool isQualityPass;
  final String qualityMessage;
  final InspectionModel? inspection;
  final String? annotatedImagePath;
  final int totalLatencyMs;
  final int filteredNonSolderCount;

  const MultiSolderInferenceResult({
    required this.isQualityPass,
    required this.qualityMessage,
    this.inspection,
    this.annotatedImagePath,
    required this.totalLatencyMs,
    this.filteredNonSolderCount = 0,
  });
}

/// Service AI Inferensi Solder (`Soldy-Net-V6` + Background Isolate Execution)
class AIInferenceService {
  final List<DefectTypeModel> defectTypes;
  final SolderModelEngine modelEngine;

  AIInferenceService({
    required this.defectTypes,
    SolderModelEngine? modelEngine,
  }) : modelEngine = modelEngine ?? SolderModelEngine(metadata: SolderModelMetadata.defaultEmbedded());

  /// Pra-analisis tangkapan kamera pada background Isolate:
  /// decode tunggal, cek kualitas optik, downscale maks 1600px, lokalisasi PCB, & prafilter kaki komponen.
  static Future<CapturePrecheckResult> precheckAndDetectCapture({
    required Uint8List rawBytes,
    required String stagingDirPath,
    double blurThreshold = AppConstants.defaultBlurThreshold,
    SolderModelMetadata? metadata,
  }) async {
    return Isolate.run(() {
      final sw = Stopwatch()..start();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        return CapturePrecheckResult(
          isQualityPass: false,
          qualityMessage: 'Gagal membaca piksel citra kamera.',
          detectedBoxes: const [],
          detectLatencyMs: sw.elapsedMilliseconds,
        );
      }

      final oriented = img.bakeOrientation(decoded);
      final quality = ImageQualityChecker.evaluateImage(oriented, blurThreshold: blurThreshold);
      if (!quality.isAcceptable) {
        return CapturePrecheckResult(
          isQualityPass: false,
          qualityMessage: quality.message,
          detectedBoxes: const [],
          detectLatencyMs: sw.elapsedMilliseconds,
        );
      }

      // Resample maks 1600px sisi panjang untuk menghindari decode ulang 12MP yang lambat
      final longSide = math.max(oriented.width, oriented.height);
      final img.Image working = longSide > 1600
          ? img.copyResize(
              oriented,
              width: oriented.width >= oriented.height ? 1600 : (oriented.width * 1600 / longSide).round(),
              height: oriented.height > oriented.width ? 1600 : (oriented.height * 1600 / longSide).round(),
              interpolation: img.Interpolation.linear,
            )
          : oriented;

      final stagingDir = Directory(stagingDirPath);
      if (!stagingDir.existsSync()) stagingDir.createSync(recursive: true);
      final optimizedPath = p.join(stagingDirPath, 'capture_opt_${DateTime.now().millisecondsSinceEpoch}.jpg');
      File(optimizedPath).writeAsBytesSync(img.encodeJpg(working, quality: 90));

      final rawBoxes = SolderLocalizerService.detectSolderJoints(working);
      final keptBoxes = <NormalizedBoundingBox>[];
      int filtered = 0;

      if (metadata != null && metadata.isV6 && rawBoxes.isNotEmpty) {
        final engine = SolderModelEngine(metadata: metadata);
        for (final box in rawBoxes) {
          final crop = _cropWithContext(working, box, padRatio: 1.0);
          final pred = engine.predict(crop, 0.45);
          if (!pred.isSolderJoint) {
            filtered++;
          } else {
            keptBoxes.add(box);
          }
        }
      } else {
        keptBoxes.addAll(rawBoxes);
      }

      return CapturePrecheckResult(
        isQualityPass: true,
        qualityMessage: quality.message,
        detectedBoxes: keptBoxes,
        rawCandidatesCount: rawBoxes.length,
        filteredNonSolderCount: filtered,
        optimizedImagePath: optimizedPath,
        detectLatencyMs: sw.elapsedMilliseconds,
      );
    });
  }

  /// Wrapper kompatibel dengan pemanggilan antarmuka pemindaian
  Future<MultiSolderInferenceResult> analyzeMultiJoints({
    required Uint8List imageBytes,
    required String originalImagePath,
    required String boardType,
    required List<NormalizedBoundingBox> boxes,
    bool isRework = false,
    int? parentInspectionId,
    double confidenceThreshold = AppConstants.defaultConfidenceThreshold,
    double blurThreshold = AppConstants.defaultBlurThreshold,
    List<bool>? manualBoxFlags,
    void Function(int done, int total)? onProgress,
  }) {
    return processMultiJointInspection(
      rawImageBytes: imageBytes,
      jointBoxes: boxes,
      boardType: boardType,
      isRework: isRework,
      parentInspectionId: parentInspectionId,
      confidenceThreshold: confidenceThreshold,
      blurThreshold: blurThreshold,
      manualBoxFlags: manualBoxFlags,
      onProgress: onProgress,
    );
  }

  /// Pipeline inspeksi penuh pada background Isolate (`Isolate.run`):
  /// nol freeze pada UI thread & bebas decode ganda 12MP.
  Future<MultiSolderInferenceResult> processMultiJointInspection({
    required Uint8List rawImageBytes,
    required List<NormalizedBoundingBox> jointBoxes,
    String boardType = AppConstants.boardGeneralPcb,
    double confidenceThreshold = AppConstants.defaultConfidenceThreshold,
    bool isRework = false,
    int? parentInspectionId,
    double blurThreshold = AppConstants.defaultBlurThreshold,
    List<bool>? manualBoxFlags,
    void Function(int done, int total)? onProgress,
  }) async {
    final appDir = await getApplicationDocumentsDirectory();
    final stagingDir = p.join(appDir.path, 'qc_staging');
    final metadata = modelEngine.metadata;
    final defectList = defectTypes;
    final uuid = const Uuid().v4();
    final now = DateTime.now();

    onProgress?.call(0, math.max(1, jointBoxes.length));

    final result = await Isolate.run(() {
      return _executePipelineSync(
        rawImageBytes: rawImageBytes,
        jointBoxes: jointBoxes,
        boardType: boardType,
        confidenceThreshold: confidenceThreshold,
        isRework: isRework,
        parentInspectionId: parentInspectionId,
        blurThreshold: blurThreshold,
        stagingDirPath: stagingDir,
        metadata: metadata,
        defectTypes: defectList,
        uuid: uuid,
        nowIso: now.toIso8601String(),
        dateTag: DateFormat('yyyyMMdd').format(now),
        manualBoxFlags: manualBoxFlags,
      );
    });

    final count = result.inspection?.totalJoints ?? jointBoxes.length;
    onProgress?.call(count, math.max(1, count));
    return result;
  }

  static MultiSolderInferenceResult _executePipelineSync({
    required Uint8List rawImageBytes,
    required List<NormalizedBoundingBox> jointBoxes,
    required String boardType,
    required double confidenceThreshold,
    required bool isRework,
    int? parentInspectionId,
    required double blurThreshold,
    required String stagingDirPath,
    required SolderModelMetadata metadata,
    required List<DefectTypeModel> defectTypes,
    required String uuid,
    required String nowIso,
    required String dateTag,
    List<bool>? manualBoxFlags,
  }) {
    final stopwatch = Stopwatch()..start();

    final decoded = img.decodeImage(rawImageBytes);
    if (decoded == null) {
      return MultiSolderInferenceResult(
        isQualityPass: false,
        qualityMessage: 'Gagal mendekode piksel gambar.',
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    final originalImage = img.bakeOrientation(decoded);
    final qualityCheck = ImageQualityChecker.evaluateImage(originalImage, blurThreshold: blurThreshold);
    if (!qualityCheck.isAcceptable) {
      return MultiSolderInferenceResult(
        isQualityPass: false,
        qualityMessage: qualityCheck.message,
        totalLatencyMs: stopwatch.elapsedMilliseconds,
      );
    }

    final engine = SolderModelEngine(metadata: metadata);
    final stagingDir = Directory(stagingDirPath);
    if (!stagingDir.existsSync()) stagingDir.createSync(recursive: true);

    final sessionPrefix = '${DateTime.now().millisecondsSinceEpoch}_${uuid.substring(0, 6)}';
    final longSide = math.max(originalImage.width, originalImage.height);
    final img.Image annotatedImage = longSide > 1600
        ? img.copyResize(
            originalImage,
            width: originalImage.width >= originalImage.height ? 1600 : (originalImage.width * 1600 / longSide).round(),
            height: originalImage.height > originalImage.width ? 1600 : (originalImage.height * 1600 / longSide).round(),
            interpolation: img.Interpolation.linear,
          )
        : img.Image.from(originalImage);

    final jointsList = <InspectionJointModel>[];
    int passCount = 0;
    int failCount = 0;
    int uncertainCount = 0;
    int filteredNonSolderCount = 0;

    final int limit = math.min(jointBoxes.length, AppConstants.maxJointsPerScan);
    int jointIndex = 0;

    for (int i = 0; i < limit; i++) {
      final box = jointBoxes[i];
      final bool isManual = manualBoxFlags != null && i < manualBoxFlags.length && manualBoxFlags[i];

      final cropPatch = _cropWithContext(originalImage, box, padRatio: 1.0);
      final prediction = engine.predict(cropPatch, confidenceThreshold, boardType: boardType);

      // Saring otomatis komponen non-solder / kaki kawat belum potong jika bukan titik manual pengguna
      if (!isManual && !prediction.isSolderJoint) {
        filteredNonSolderCount++;
        continue;
      }

      jointIndex++;
      final cropPath = p.join(stagingDirPath, 'joint_${sessionPrefix}_$jointIndex.jpg');
      File(cropPath).writeAsBytesSync(img.encodeJpg(cropPatch, quality: 85));

      String finalResult = prediction.result;
      int? finalDefectId = prediction.defectTypeId;
      if (!prediction.isSolderJoint && isManual) {
        // Jika manual tetapi terdeteksi non-solder, tandai UNCERTAIN agar teknisi tetap memeriksa
        finalResult = AppConstants.statusUncertain;
        finalDefectId = null;
      }

      if (finalResult == AppConstants.statusPass) {
        passCount++;
      } else if (finalResult == AppConstants.statusFail) {
        failCount++;
      } else {
        uncertainCount++;
      }

      DefectTypeModel? matchedDefect;
      if (finalDefectId != null) {
        matchedDefect = defectTypes.cast<DefectTypeModel?>().firstWhere(
              (d) => d?.id == finalDefectId,
              orElse: () => null,
            );
      }

      jointsList.add(
        InspectionJointModel(
          jointIndex: jointIndex,
          bbox: box,
          result: finalResult,
          defectTypeId: finalDefectId,
          defectType: matchedDefect,
          confidence: prediction.confidence,
          cropImagePath: cropPath,
        ),
      );

      _drawAnnotationBox(
        annotatedImage,
        box,
        jointIndex,
        finalResult,
      );
    }

    final annotatedImagePath = p.join(stagingDirPath, 'pcb_result_$sessionPrefix.jpg');
    File(annotatedImagePath).writeAsBytesSync(img.encodeJpg(annotatedImage, quality: 85));

    String overallResult = AppConstants.statusPass;
    if (failCount > 0) {
      overallResult = AppConstants.statusFail;
    } else if (uncertainCount > 0 || jointsList.isEmpty) {
      overallResult = AppConstants.statusUncertain;
    }

    final String? notesText = filteredNonSolderCount > 0
        ? 'Soldy AI menyaring $filteredNonSolderCount objek non-solder / kaki komponen utuh.'
        : null;

    stopwatch.stop();
    final inspectionCode = 'QC-$dateTag-${uuid.substring(0, 6).toUpperCase()}';

    final inspection = InspectionModel(
      inspectionCode: inspectionCode,
      inspectedAt: nowIso,
      boardType: boardType,
      totalJoints: jointsList.length,
      passCount: passCount,
      failCount: failCount,
      uncertainCount: uncertainCount,
      overallResult: overallResult,
      imagePath: annotatedImagePath,
      modelVersion: metadata.modelName,
      totalInferenceTimeMs: stopwatch.elapsedMilliseconds,
      imageQualityStatus: qualityCheck.status,
      manualReviewStatus: false,
      isRework: isRework,
      parentInspectionId: parentInspectionId,
      notes: notesText,
      joints: jointsList,
    );

    return MultiSolderInferenceResult(
      isQualityPass: true,
      qualityMessage: qualityCheck.message,
      inspection: inspection,
      annotatedImagePath: annotatedImagePath,
      totalLatencyMs: stopwatch.elapsedMilliseconds,
      filteredNonSolderCount: filteredNonSolderCount,
    );
  }

  static img.Image _cropWithContext(img.Image src, NormalizedBoundingBox box, {double padRatio = 1.25}) {
    final rect = box.toPixelRect(Size(src.width.toDouble(), src.height.toDouble()));
    final int pw = (rect.width * padRatio).round().clamp(16, src.width);
    final int ph = (rect.height * padRatio).round().clamp(16, src.height);
    final int x = (rect.left + rect.width * 0.5 - pw * 0.5).round().clamp(0, math.max(0, src.width - pw));
    final int y = (rect.top + rect.height * 0.5 - ph * 0.5).round().clamp(0, math.max(0, src.height - ph));
    return img.copyCrop(src, x: x, y: y, width: pw, height: ph);
  }

  static void _drawAnnotationBox(
    img.Image image,
    NormalizedBoundingBox box,
    int index,
    String status,
  ) {
    final rect = box.toPixelRect(Size(image.width.toDouble(), image.height.toDouble()));
    final int x = rect.left.round();
    final int y = rect.top.round();
    final int w = rect.width.round();
    final int h = rect.height.round();

    final img.ColorRgb8 color = status == AppConstants.statusPass
        ? img.ColorRgb8(22, 163, 74)
        : (status == AppConstants.statusFail ? img.ColorRgb8(220, 38, 38) : img.ColorRgb8(217, 119, 6));

    final int x1 = (x + w).clamp(0, image.width - 1);
    final int y1 = (y + h).clamp(0, image.height - 1);

    for (int t = 0; t < 3; t++) {
      final int x0 = (x - t).clamp(0, image.width - 1);
      final int y0 = (y - t).clamp(0, image.height - 1);
      img.drawRect(image, x1: x0, y1: y0, x2: x1, y2: y1, color: color);
    }
  }
}
