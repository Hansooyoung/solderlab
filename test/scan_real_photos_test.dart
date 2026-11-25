// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/utils/image_quality_checker.dart';
import 'package:qc_solder/data/database/app_database.dart';
import 'package:qc_solder/data/repositories/inspection_repository.dart';
import 'package:qc_solder/services/ai/ai_inference_service.dart';
import 'package:qc_solder/services/ai/solder_localizer_service.dart';
import 'package:qc_solder/services/ai/solder_model_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.customDbName = inMemoryDatabasePath;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => Directory.systemTemp.path,
  );

  test(
    'PEMINDAIAN CITRA NYATA: Scan Multi-Fixture PCB Through-Hole & Quality Gate',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final repository = InspectionRepository();
      final defectTypes = await repository.getAllDefectTypes();
      final metadata = await SolderModelMetadata.load();
      final aiService = AIInferenceService(
        defectTypes: defectTypes,
        modelEngine: SolderModelEngine(metadata: metadata),
      );

      final List<Map<String, String>> photoTestCases = [
        {
          'id': 'PCB-FIXTURE-01 (THT Standard Board)',
          'path': 'test/fixtures/sample_tht_pcb_pass.jpg',
        },
        {
          'id': 'PCB-FIXTURE-02 (THT Multi-Joint Board)',
          'path': 'test/fixtures/sample_tht_pcb_defect.jpg',
        },
        {
          'id': 'PCB-FIXTURE-03 (Optical Blur Gate Test)',
          'path': 'test/fixtures/sample_blur_pcb.jpg',
        },
      ];

      int grandTotalScans = 0;
      int grandTotalJoints = 0;

      for (final testCase in photoTestCases) {
        final name = testCase['id']!;
        final filePath = testCase['path']!;
        final file = File(filePath);
        expect(file.existsSync(), isTrue, reason: 'Berkas foto $filePath harus ada');

        final bytes = file.readAsBytesSync();
        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull);

        final quality = ImageQualityChecker.evaluateImage(decoded!);
        final detectedBoxes = SolderLocalizerService.detectSolderJoints(decoded);
        print(
          'FOTO: $name | ${decoded.width}x${decoded.height} | '
          'Quality=${quality.status} (${quality.blurScore.toStringAsFixed(1)}) | '
          'CV Boxes=${detectedBoxes.length}',
        );

        final inferenceResult = await aiService.processMultiJointInspection(
          rawImageBytes: bytes,
          jointBoxes: detectedBoxes,
          boardType: AppConstants.boardGeneralPcb,
        );

        if (!quality.isAcceptable) {
          expect(inferenceResult.isQualityPass, isFalse);
          grandTotalScans++;
          continue;
        }

        expect(inferenceResult.isQualityPass, isTrue);
        expect(inferenceResult.inspection, isNotNull);
        final inspection = inferenceResult.inspection!;
        expect(inspection.totalJoints, greaterThan(0));

        final savedId = await repository.saveInspection(inspection);
        expect(savedId, greaterThan(0));

        grandTotalScans++;
        grandTotalJoints += inspection.totalJoints;
      }

      expect(grandTotalScans, equals(photoTestCases.length));
      expect(grandTotalJoints, greaterThanOrEqualTo(10));
    },
  );
}
