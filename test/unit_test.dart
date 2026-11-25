import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/utils/bounding_box.dart';
import 'package:qc_solder/data/models/defect_type_model.dart';
import 'package:qc_solder/data/models/inspection_joint_model.dart';
import 'package:qc_solder/data/models/inspection_model.dart';
import 'package:qc_solder/services/ai/solder_localizer_service.dart';
import 'package:qc_solder/services/ai/solder_model_engine.dart';

void main() {
  group('Unit Test: Bounding Box & IoU', () {
    test('Bounding box calculates IoU correctly', () {
      const boxA = NormalizedBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      const boxB = NormalizedBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2);
      expect(boxA.calculateIoU(boxB), closeTo(1.0, 0.001));

      const boxC = NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.2, height: 0.2);
      expect(boxA.calculateIoU(boxC), equals(0.0));
    });
  });

  group('Unit Test: Multi-Joint Inspection Aggregation', () {
    test('Calculates Pass and Fail rate correctly across multiple joints', () {
      final joints = [
        const InspectionJointModel(
          jointIndex: 1,
          bbox: NormalizedBoundingBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1),
          result: 'PASS',
          confidence: 0.95,
        ),
        const InspectionJointModel(
          jointIndex: 2,
          bbox: NormalizedBoundingBox(x: 0.3, y: 0.1, width: 0.1, height: 0.1),
          result: 'PASS',
          confidence: 0.90,
        ),
        const InspectionJointModel(
          jointIndex: 3,
          bbox: NormalizedBoundingBox(x: 0.5, y: 0.1, width: 0.1, height: 0.1),
          result: 'FAIL',
          defectTypeId: 3, // D2_COLD
          confidence: 0.88,
        ),
      ];

      final inspection = InspectionModel(
        inspectionCode: 'QC-TEST-001',
        inspectedAt: '2026-11-02T10:00:00',
        boardType: 'GENERAL_PCB',
        totalJoints: 3,
        passCount: 2,
        failCount: 1,
        uncertainCount: 0,
        overallResult: 'FAIL',
        imagePath: '',
        modelVersion: 'v1.0.0-int8',
        totalInferenceTimeMs: 45,
        imageQualityStatus: 'OPTIMAL',
        manualReviewStatus: false,
        joints: joints,
      );

      expect(inspection.totalJoints, equals(3));
      expect(inspection.passCount, equals(2));
      expect(inspection.failCount, equals(1));
      expect(inspection.isPass, isFalse);
      expect(inspection.isFail, isTrue);
      expect(inspection.passRate, closeTo(66.66, 0.1));
      expect(inspection.failRate, closeTo(33.33, 0.1));
    });
  });

  group('Unit Test: Defect Types IPC-A-610', () {
    test('Defect model recognizes pass and fail status correctly', () {
      const normalDefect = DefectTypeModel(
        id: 1,
        defectCode: 'PASS_NORMAL',
        defectName: 'Normal Solder',
        description: 'Meniskus cekung lolos',
        category: 'CONFORMANCE',
        qualityStatus: 'PASS',
      );
      expect(normalDefect.isPass, isTrue);

      const bridgeDefect = DefectTypeModel(
        id: 2,
        defectCode: 'D1_BRIDGE',
        defectName: 'Bridging',
        description: 'Short circuit',
        category: 'VOLUME',
        qualityStatus: 'FAIL',
      );
      expect(bridgeDefect.isPass, isFalse);
    });
  });

  group('Unit Test: General PCB Localizer & Confidence Threshold', () {
    test('Rejects white paper with black stroke lines and detects blue/green PCB pads', () {
      // 1. Kertas putih polos dengan garis tulisan hitam -> tidak boleh terdeteksi sebagai pad
      final paperImg = img.Image(width: 400, height: 400);
      img.fill(paperImg, color: img.ColorRgb8(235, 235, 235));
      img.fillRect(paperImg, x1: 80, y1: 180, x2: 320, y2: 192, color: img.ColorRgb8(30, 30, 30));
      final paperBoxes = SolderLocalizerService.detectSolderJoints(paperImg);
      expect(paperBoxes, isEmpty);

      // 2. PCB Biru umum dengan 3 pad logam solder -> semua 3 terdeteksi
      final bluePcb = img.Image(width: 600, height: 600);
      img.fill(bluePcb, color: img.ColorRgb8(20, 65, 130));
      for (final pos in [
        [180, 200],
        [300, 200],
        [420, 200],
      ]) {
        img.fillCircle(bluePcb, x: pos[0], y: pos[1], radius: 22, color: img.ColorRgb8(220, 224, 228));
        img.fillCircle(bluePcb, x: pos[0], y: pos[1], radius: 5, color: img.ColorRgb8(40, 40, 40));
      }
      final blueBoxes = SolderLocalizerService.detectSolderJoints(bluePcb);
      expect(blueBoxes.length, greaterThanOrEqualTo(3));
    });

    test('Marks low-confidence predictions as UNCERTAIN in both THT and SMD modes', () {
      final engine = SolderModelEngine(metadata: SolderModelMetadata.defaultEmbedded());
      final patch = img.Image(width: 64, height: 64);
      img.fill(patch, color: img.ColorRgb8(180, 180, 180));
      // Ambang sangat tinggi (0.999) wajib mengklasifikasikan sebagai UNCERTAIN
      final predTht = engine.predict(patch, 0.999, boardType: AppConstants.boardGeneralPcb);
      expect(predTht.result, equals(AppConstants.statusUncertain));

      final predSmd = engine.predict(patch, 0.999, boardType: AppConstants.boardSmdMixed);
      expect(predSmd.result, equals(AppConstants.statusUncertain));
    });
  });
}
