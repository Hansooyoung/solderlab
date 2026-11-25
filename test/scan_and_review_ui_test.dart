import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/utils/bounding_box.dart';
import 'package:qc_solder/data/database/app_database.dart';
import 'package:qc_solder/data/models/defect_type_model.dart';
import 'package:qc_solder/data/models/inspection_joint_model.dart';
import 'package:qc_solder/data/models/inspection_model.dart';
import 'package:qc_solder/presentation/screens/inspection_result_screen.dart';
import 'package:qc_solder/presentation/screens/joint_review_screen.dart';
import 'package:qc_solder/services/ai/ai_inference_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.customDbName = inMemoryDatabasePath;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
  });

  group('PENGUJIAN UI & FITUR SCAN SOLDERLAB (SIAP LAUNCHING)', () {
    late String testImagePath;
    late Uint8List testImageBytes;

    setUp(() async {
      final tempDir = Directory.systemTemp.createTempSync('qc_ui_test_');
      final image = img.Image(width: 400, height: 400);
      img.fill(image, color: img.ColorRgb8(120, 120, 120));
      img.fillCircle(image, x: 200, y: 200, radius: 30, color: img.ColorRgb8(240, 240, 240));

      final file = File('${tempDir.path}/test_board.png');
      testImageBytes = Uint8List.fromList(img.encodePng(image));
      await file.writeAsBytes(testImageBytes);
      testImagePath = file.path;
    });

    testWidgets('1. Layar Kalibrasi JointReviewScreen: Render foto, interaksi tambah/kurang reticle pad', (WidgetTester tester) async {
      final initialBoxes = [
        const NormalizedBoundingBox(x: 0.5, y: 0.5, width: 0.15, height: 0.15),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: JointReviewScreen(
              imagePath: testImagePath,
              initialBoxes: initialBoxes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifikasi komponen UI utama ter-render
      expect(find.text('Konfirmasi Titik Solder (1 Pad)'), findsOneWidget);
      expect(find.text('1 PAD'), findsOneWidget);
      expect(find.text('Mulai Evaluasi Mutu (1 Titik) →'), findsOneWidget);

      // Ketuk area layar untuk menambahkan titik baru
      await tester.tapAt(const Offset(100, 150));
      await tester.pumpAndSettle();

      // Jumlah titik bertambah menjadi 2
      expect(find.text('Konfirmasi Titik Solder (2 Pad)'), findsOneWidget);
      expect(find.text('2 PAD'), findsOneWidget);

      // Ketuk kembali titik yang baru ditambahkan untuk menghapusnya
      await tester.tapAt(const Offset(100, 150));
      await tester.pumpAndSettle();

      // Jumlah titik kembali menjadi 1
      expect(find.text('Konfirmasi Titik Solder (1 Pad)'), findsOneWidget);
      expect(find.text('1 PAD'), findsOneWidget);
    });

    testWidgets('2. Layar Hasil Pemeriksaan InspectionResultScreen: Kalkulasi Metrik, Ringkasan IPC & Persistensi', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now().toIso8601String();
      final mockInspection = InspectionModel(
        id: 99,
        inspectionCode: 'QC-20261122-TEST99',
        inspectedAt: now,
        boardType: AppConstants.boardGeneralPcb,
        totalJoints: 2,
        passCount: 1,
        failCount: 1,
        uncertainCount: 0,
        overallResult: 'FAIL',
        imagePath: testImagePath,
        modelVersion: 'QC-Solder-General-Linear-V5',
        totalInferenceTimeMs: 1240,
        imageQualityStatus: 'OPTIMAL',
        manualReviewStatus: false,
        joints: [
          InspectionJointModel(
            id: 1,
            inspectionId: 99,
            jointIndex: 1,
            bbox: const NormalizedBoundingBox(x: 0.2, y: 0.3, width: 0.1, height: 0.1),
            result: 'FAIL',
            confidence: 0.88,
            defectTypeId: 5,
            defectType: const DefectTypeModel(
              id: 5,
              defectCode: 'D4_EXCESS',
              defectName: 'Kelebihan Timah (Excess Solder)',
              description: 'Meniskus timah cembung berlebih',
              category: 'VOLUME',
              qualityStatus: 'FAIL',
            ),
          ),
          InspectionJointModel(
            id: 2,
            inspectionId: 99,
            jointIndex: 2,
            bbox: const NormalizedBoundingBox(x: 0.4, y: 0.3, width: 0.1, height: 0.1),
            result: 'PASS',
            confidence: 0.95,
          ),
        ],
      );

      final inferenceResult = MultiSolderInferenceResult(
        isQualityPass: true,
        qualityMessage: 'OPTIMAL',
        inspection: mockInspection,
        annotatedImagePath: testImagePath,
        totalLatencyMs: 1240,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: InspectionResultScreen(
              result: inferenceResult,
              rawImageBytes: testImageBytes,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verifikasi Tampilan Status Utama SolderLab
      expect(find.text('Hasil Pemeriksaan Solder'), findsOneWidget);
      expect(find.text('REWORK'), findsWidgets);
      expect(find.text('#QC-20261122-TEST99 • PCB Umum'), findsOneWidget);
      expect(find.text('Terdapat 1 Titik Solder Perlu Rework'), findsOneWidget);

      // Verifikasi Metrik Kartu
      expect(find.text('TOTAL TITIK'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Total Joints
      expect(find.text('1'), findsWidgets); // Pass & Fail Count

      // Verifikasi Daftar Sambungan Solder
      expect(find.text('TITIK SAMBUNGAN PERLU REWORK'), findsOneWidget);
      expect(find.text('Kaki #1 • Pad Sambungan'), findsOneWidget);
      expect(find.text('Kelebihan Timah (Excess Solder)'), findsOneWidget);
      expect(find.text('Tindakan: Sentuh mata solder hangat ke pad dan serap timah berlebih menggunakan copper wick.'), findsOneWidget);

      // Uji Koreksi Manual pada Kaki #1 -> ubah menjadi PASS_NORMAL
      await tester.ensureVisible(find.text('Kaki #1 • Pad Sambungan'));
      await tester.tap(find.text('Kaki #1 • Pad Sambungan'));
      await tester.pumpAndSettle();
      expect(find.text('Koreksi Manual • Kaki #1'), findsOneWidget);
      await tester.tap(find.text('PASS_NORMAL'));
      await tester.pumpAndSettle();

      // Setelah koreksi manual seluruh titik menjadi LULUS
      expect(find.text('Lulus Standar: Solder Optimal'), findsOneWidget);

      // Verifikasi Tombol Simpan
      expect(find.text('Simpan ke Log →'), findsOneWidget);
      await tester.tap(find.text('Simpan ke Log →'));
      await tester.pump();

      // Tunggu hingga proses penyimpanan asinkron basis data selesai
      for (int i = 0; i < 30; i++) {
        if (find.text('Tersimpan ✓').evaluate().isNotEmpty) break;
        await tester.runAsync(() async {
          await Future.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
      }

      // Tombol berubah status menjadi tersimpan
      expect(find.text('Tersimpan ✓'), findsOneWidget);
    });
  });
}
