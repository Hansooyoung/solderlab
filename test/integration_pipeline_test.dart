// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/utils/image_quality_checker.dart';
import 'package:qc_solder/data/database/app_database.dart';
import 'package:qc_solder/data/models/defect_type_model.dart';
import 'package:qc_solder/data/repositories/inspection_repository.dart';
import 'package:qc_solder/services/ai/ai_inference_service.dart';
import 'package:qc_solder/services/ai/solder_localizer_service.dart';
import 'package:qc_solder/services/export/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.customDbName = inMemoryDatabasePath;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (MethodCall methodCall) async {
    return Directory.systemTemp.path;
  });

  test('END-TO-END PIPELINE: Image -> Detection -> AI Inference -> SQLite -> Export', () async {
    print('1. Menguji Pembuatan Citra PCB Sintetis & Quality Checker...');
    // Buat citra uji sintetis 600x600 dengan 4 solder pad
    final testImg = img.Image(width: 600, height: 600);
    img.fill(testImg, color: img.ColorRgb8(45, 95, 60)); // PCB Green (Normal lighting)

    // Gambar 4 pad solder (2 normal, 1 excess, 1 insufficient)
    // Pad 1: Normal
    img.fillCircle(testImg, x: 200, y: 200, radius: 40, color: img.ColorRgb8(184, 115, 51)); // Copper
    img.fillCircle(testImg, x: 200, y: 200, radius: 25, color: img.ColorRgb8(210, 215, 220)); // Tin
    img.fillCircle(testImg, x: 200, y: 200, radius: 6, color: img.ColorRgb8(20, 20, 20)); // Pin

    // Pad 2: Excess (Bulky tin)
    img.fillCircle(testImg, x: 400, y: 200, radius: 40, color: img.ColorRgb8(184, 115, 51));
    img.fillCircle(testImg, x: 400, y: 200, radius: 38, color: img.ColorRgb8(250, 250, 250)); // Excess white shiny tin
    img.fillCircle(testImg, x: 400, y: 200, radius: 4, color: img.ColorRgb8(20, 20, 20));

    // Pad 3: Insufficient (dark/empty copper)
    img.fillCircle(testImg, x: 200, y: 400, radius: 40, color: img.ColorRgb8(140, 70, 30));
    img.fillCircle(testImg, x: 200, y: 400, radius: 10, color: img.ColorRgb8(80, 80, 80)); // Little tin

    // Pad 4: Normal
    img.fillCircle(testImg, x: 400, y: 400, radius: 40, color: img.ColorRgb8(184, 115, 51));
    img.fillCircle(testImg, x: 400, y: 400, radius: 25, color: img.ColorRgb8(210, 215, 220));
    img.fillCircle(testImg, x: 400, y: 400, radius: 6, color: img.ColorRgb8(20, 20, 20));

    // Uji Quality Gate
    final quality = ImageQualityChecker.evaluateImage(testImg);
    print('   - Quality status: ${quality.status} (Brightness: ${quality.brightnessScore.toStringAsFixed(1)})');
    expect(quality.isAcceptable, isTrue);

    print('2. Menguji Deteksi Multi-Solder Pad (Localizer)...');
    final detectedBoxes = SolderLocalizerService.detectSolderJoints(testImg, maxJoints: 10);
    print('   - Bounding boxes terdeteksi: ${detectedBoxes.length} titik pad');
    expect(detectedBoxes.isNotEmpty, isTrue);

    print('3. Menguji AI Classification Engine...');
    final defectTypes = [
      const DefectTypeModel(id: 1, defectCode: 'PASS_NORMAL', defectName: 'Normal Solder', description: 'Meniskus cekung', category: 'CONFORMANCE', qualityStatus: 'PASS'),
      const DefectTypeModel(id: 2, defectCode: 'D1_BRIDGE', defectName: 'Bridging', description: 'Short circuit', category: 'VOLUME', qualityStatus: 'FAIL'),
      const DefectTypeModel(id: 3, defectCode: 'D2_COLD', defectName: 'Cold Solder', description: 'Defisit panas', category: 'THERMAL', qualityStatus: 'FAIL'),
      const DefectTypeModel(id: 4, defectCode: 'D3_INSUFFICIENT', defectName: 'Insufficient Solder', description: 'Timah tipis', category: 'WETTING', qualityStatus: 'FAIL'),
      const DefectTypeModel(id: 5, defectCode: 'D4_EXCESS', defectName: 'Excess Solder', description: 'Gumpalan timah', category: 'VOLUME', qualityStatus: 'FAIL'),
      const DefectTypeModel(id: 6, defectCode: 'D5_PINHOLE', defectName: 'Pinhole', description: 'Rongga gas', category: 'THERMAL', qualityStatus: 'FAIL'),
    ];

    final aiService = AIInferenceService(defectTypes: defectTypes);
    final rawJpg = img.encodeJpg(testImg);

    final aiResult = await aiService.processMultiJointInspection(
      rawImageBytes: rawJpg,
      jointBoxes: detectedBoxes,
      boardType: AppConstants.boardGeneralPcb,
    );

    print('   - AI Latency: ${aiResult.totalLatencyMs} ms');
    print('   - Total Pad Diuji: ${aiResult.inspection?.totalJoints}');
    print('   - Hasil Keseluruhan: ${aiResult.inspection?.overallResult}');
    print('   - Jumlah Lolos: ${aiResult.inspection?.passCount}');
    print('   - Jumlah Cacat: ${aiResult.inspection?.failCount}');
    expect(aiResult.isQualityPass, isTrue);
    expect(aiResult.inspection, isNotNull);

    print('4. Menguji Persistensi Basis Data SQLite...');
    final repo = InspectionRepository();
    final inspectionId = await repo.saveInspection(aiResult.inspection!);
    print('   - Tersimpan di SQLite dengan ID: $inspectionId');
    expect(inspectionId, greaterThan(0));

    final fetched = await repo.getInspectionById(inspectionId);
    expect(fetched, isNotNull);
    expect(fetched!.totalJoints, equals(aiResult.inspection!.totalJoints));
    print('   - Data terbaca kembali dari SQLite: ${fetched.inspectionCode} (${fetched.joints.length} joints)');

    print('5. Menguji Kalkulasi Statistik Nyata SQLite...');
    final stats = await repo.calculateStatistics();
    print('   - Total Sesi: ${stats.totalInspections}, Total Pad: ${stats.totalJointsInspected}, Yield Rate: ${stats.overallYieldRate.toStringAsFixed(1)}%');
    expect(stats.totalInspections, greaterThanOrEqualTo(1));

    print('6. Menguji Generator Ekspor CSV...');
    final csvPath = await ExportService.exportToCsv([fetched]);
    print('   - CSV terbuat: $csvPath (Ukuran: ${File(csvPath).lengthSync()} bytes)');
    expect(File(csvPath).existsSync(), isTrue);

    print('7. Menguji Generator Ekspor PDF...');
    final pdfPath = await ExportService.exportInspectionToPdf(fetched);
    print('   - PDF terbuat: $pdfPath (Ukuran: ${File(pdfPath).lengthSync()} bytes)');
    expect(File(pdfPath).existsSync(), isTrue);

    print('\n>>> SEMUA TAHAP END-TO-END PIPELINE BERJALAN 100% SUKSES! <<<');
  });
}
