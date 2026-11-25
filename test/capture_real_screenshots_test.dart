import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/theme/app_theme.dart';
import 'package:qc_solder/core/utils/bounding_box.dart';
import 'package:qc_solder/data/database/app_database.dart';
import 'package:qc_solder/data/models/defect_type_model.dart';
import 'package:qc_solder/data/models/inspection_joint_model.dart';
import 'package:qc_solder/data/models/inspection_model.dart';
import 'package:qc_solder/presentation/screens/inspection_result_screen.dart';
import 'package:qc_solder/presentation/screens/joint_review_screen.dart';
import 'package:qc_solder/presentation/screens/main_navigation_scaffold.dart';
import 'package:qc_solder/presentation/screens/splash_screen.dart';
import 'package:qc_solder/presentation/screens/workstation_setup_screen.dart';
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

  group('PENGAMBILAN SCREENSHOT NYATA APLIKASI SOLDERLAB (REAL ENGINE RENDER)', () {
    final outputDir = Directory('docs/preview/real_app_screenshots');
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    Future<void> captureWidget({
      required WidgetTester tester,
      required Widget widget,
      required String filename,
      Size size = const Size(390, 844), // iPhone 14 / Modern Android Standard
      double pixelRatio = 2.0,
    }) async {
      final key = GlobalKey();

      tester.view.physicalSize = Size(size.width * pixelRatio, size.height * pixelRatio);
      tester.view.devicePixelRatio = pixelRatio;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.solderLabTheme,
            home: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: widget,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 1300));

      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image? image;
      Uint8List? pngBytes;

      await tester.runAsync(() async {
        image = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await image!.toByteData(format: ui.ImageByteFormat.png);
        pngBytes = byteData!.buffer.asUint8List();
      });

      final file = File('${outputDir.path}/$filename');
      file.writeAsBytesSync(pngBytes!);
      // ignore: avoid_print
      print('Tersimpan Screenshot Real: ${file.path} (${image!.width}x${image!.height} px)');

      // Unmount widget & flush sqflite lock timeout timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 11));

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    testWidgets('1. Capture Splash Screen Real', (WidgetTester tester) async {
      await captureWidget(
        tester: tester,
        widget: const SplashScreen(autoStart: false),
        filename: '01_splash_screen.png',
      );
    });

    testWidgets('2. Capture Dashboard Home Screen Real', (WidgetTester tester) async {
      await captureWidget(
        tester: tester,
        widget: const MainNavigationScaffold(initialIndex: 0),
        filename: '02_dashboard_home.png',
      );
    });

    testWidgets('3. Capture Workstation Setup Checklist Screen Real', (WidgetTester tester) async {
      await captureWidget(
        tester: tester,
        widget: const WorkstationSetupScreen(),
        filename: '03_workstation_setup.png',
      );
    });

    testWidgets('4. Capture Joint Review & Calibration Screen Real', (WidgetTester tester) async {
      // Buat citra uji papan sirkuit
      final tempDir = Directory.systemTemp.createTempSync('qc_ss_');
      final pcbImg = img.Image(width: 600, height: 800);
      img.fill(pcbImg, color: img.ColorRgb8(45, 95, 60)); // Hijau PCB
      // Tambahkan beberapa pad solder
      for (int i = 0; i < 6; i++) {
        final cx = 150 + (i % 2) * 300;
        final cy = 200 + (i ~/ 2) * 200;
        img.fillCircle(pcbImg, x: cx, y: cy, radius: 45, color: img.ColorRgb8(184, 115, 51));
        img.fillCircle(pcbImg, x: cx, y: cy, radius: 30, color: img.ColorRgb8(220, 220, 225));
        img.fillCircle(pcbImg, x: cx, y: cy, radius: 8, color: img.ColorRgb8(30, 30, 30));
      }
      final testFile = File('${tempDir.path}/pcb_demo.png');
      testFile.writeAsBytesSync(img.encodePng(pcbImg));

      final demoBoxes = [
        const NormalizedBoundingBox(x: 0.25, y: 0.25, width: 0.15, height: 0.11),
        const NormalizedBoundingBox(x: 0.75, y: 0.25, width: 0.15, height: 0.11),
        const NormalizedBoundingBox(x: 0.25, y: 0.50, width: 0.15, height: 0.11),
        const NormalizedBoundingBox(x: 0.75, y: 0.50, width: 0.15, height: 0.11),
      ];

      await captureWidget(
        tester: tester,
        widget: JointReviewScreen(
          imagePath: testFile.path,
          initialBoxes: demoBoxes,
        ),
        filename: '04_joint_review_calibration.png',
      );
    });

    testWidgets('5. Capture Inspection Result Screen (IPC Analysis) Real', (WidgetTester tester) async {
      final now = DateTime.now().toIso8601String();
      final mockInspection = InspectionModel(
        id: 1,
        inspectionCode: 'QC-20261124-001',
        inspectedAt: now,
        boardType: AppConstants.boardGeneralPcb,
        totalJoints: 12,
        passCount: 10,
        failCount: 2,
        uncertainCount: 0,
        overallResult: 'FAIL',
        imagePath: '',
        modelVersion: 'QC-Solder-General-Linear-V5',
        totalInferenceTimeMs: 1420,
        imageQualityStatus: 'OPTIMAL',
        manualReviewStatus: false,
        joints: [
          InspectionJointModel(
            id: 1,
            inspectionId: 1,
            jointIndex: 1,
            bbox: const NormalizedBoundingBox(x: 0.2, y: 0.3, width: 0.1, height: 0.1),
            result: 'FAIL',
            confidence: 0.88,
            defectTypeId: 5,
            defectType: const DefectTypeModel(
              id: 5,
              defectCode: 'D4_EXCESS',
              defectName: 'Kelebihan Timah (Excess Solder)',
              description: 'Meniskus timah cembung berlebih melampaui perimeter pad',
              category: 'VOLUME',
              qualityStatus: 'FAIL',
            ),
          ),
          InspectionJointModel(
            id: 2,
            inspectionId: 1,
            jointIndex: 2,
            bbox: const NormalizedBoundingBox(x: 0.4, y: 0.3, width: 0.1, height: 0.1),
            result: 'FAIL',
            confidence: 0.79,
            defectTypeId: 4,
            defectType: const DefectTypeModel(
              id: 4,
              defectCode: 'D3_INSUFFICIENT',
              defectName: 'Kekurangan Timah (Insufficient Solder)',
              description: 'Timah gagal membasahi kaki komponen atau pad (barrel fill < 75%)',
              category: 'WETTING',
              qualityStatus: 'FAIL',
            ),
          ),
          InspectionJointModel(
            id: 3,
            inspectionId: 1,
            jointIndex: 3,
            bbox: const NormalizedBoundingBox(x: 0.6, y: 0.3, width: 0.1, height: 0.1),
            result: 'PASS',
            confidence: 0.94,
            defectType: const DefectTypeModel(
              id: 1,
              defectCode: 'PASS_NORMAL',
              defectName: 'Normal Solder Joint',
              description: 'Sambungan ideal meniskus cekung (< 90 derajat)',
              category: 'CONFORMANCE',
              qualityStatus: 'PASS',
            ),
          ),
        ],
      );

      final inferenceResult = MultiSolderInferenceResult(
        isQualityPass: true,
        qualityMessage: 'OPTIMAL',
        inspection: mockInspection,
        annotatedImagePath: null,
        totalLatencyMs: 1420,
      );

      await captureWidget(
        tester: tester,
        widget: InspectionResultScreen(
          result: inferenceResult,
          rawImageBytes: Uint8List(0),
        ),
        filename: '05_inspection_result_reject.png',
      );
    });

    testWidgets('6. Capture IPC Standard & OLS Regression Screen Real', (WidgetTester tester) async {
      await captureWidget(
        tester: tester,
        widget: const MainNavigationScaffold(initialIndex: 1),
        filename: '06_ipc_standard_screen.png',
      );
    });

    testWidgets('7. Capture Statistics & Pareto Analytics Screen Real', (WidgetTester tester) async {
      await captureWidget(
        tester: tester,
        widget: const MainNavigationScaffold(initialIndex: 2),
        filename: '07_statistics_analytics.png',
      );
    });
  });
}
