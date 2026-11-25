import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:qc_solder/core/constants/app_constants.dart';
import 'package:qc_solder/core/localization/locale_provider.dart';
import 'package:qc_solder/core/utils/bounding_box.dart';
import 'package:qc_solder/data/database/app_database.dart';
import 'package:qc_solder/data/models/inspection_joint_model.dart';
import 'package:qc_solder/data/models/inspection_model.dart';
import 'package:qc_solder/data/repositories/inspection_repository.dart';
import 'package:qc_solder/features/shared/widgets/soldy_avatar_animated.dart';
import 'package:qc_solder/features/shared/widgets/soldy_coach_banner.dart';
import 'package:qc_solder/presentation/screens/inspection_detail_screen.dart';
import 'package:qc_solder/services/ai/ai_inference_service.dart';
import 'package:qc_solder/services/ai/solder_localizer_service.dart';
import 'package:qc_solder/services/ai/solder_model_engine.dart';

/// Membuat citra papan PCB sintetis dengan kaki kawat komponen lurus yang belum dipotong
/// (garis metalik tipis memanjang melintasi papan hijau/merah tanpa kerucut timah).
img.Image _buildSyntheticUncutLeadBoard({bool redMask = false}) {
  final board = img.Image(width: 640, height: 480);
  final bg = redMask ? img.ColorRgb8(135, 30, 32) : img.ColorRgb8(36, 98, 56);
  img.fill(board, color: bg);

  // Gambar 4 kaki kawat komponen utuh memanjang miring/vertikal melintasi PCB
  final silver = img.ColorRgb8(232, 236, 240);
  img.drawLine(board, x1: 140, y1: 60, x2: 148, y2: 380, color: silver, thickness: 4);
  img.drawLine(board, x1: 260, y1: 80, x2: 390, y2: 340, color: silver, thickness: 4);
  img.drawLine(board, x1: 420, y1: 90, x2: 422, y2: 400, color: silver, thickness: 3);
  img.drawLine(board, x1: 110, y1: 240, x2: 520, y2: 246, color: silver, thickness: 3);
  return board;
}

/// Membuat citra PCB sintetis berisi titik solder melingkar asli (cincin tembaga + kerucut timah + pin tengah).
img.Image _buildSyntheticTrueSolderBoard() {
  final board = img.Image(width: 640, height: 480);
  img.fill(board, color: img.ColorRgb8(34, 96, 54));

  final centers = [
    (160, 160),
    (320, 160),
    (480, 160),
    (240, 320),
    (400, 320),
  ];
  for (final (cx, cy) in centers) {
    img.fillCircle(board, x: cx, y: cy, radius: 12, color: img.ColorRgb8(184, 118, 54));
    img.fillCircle(board, x: cx, y: cy, radius: 9, color: img.ColorRgb8(232, 236, 240));
    img.fillCircle(board, x: cx, y: cy, radius: 2, color: img.ColorRgb8(45, 48, 52));
  }
  return board;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.customDbName = inMemoryDatabasePath;

  late Directory tempTestDir;
  late SolderModelMetadata v6Meta;

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('solderlab_v1_verify_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempTestDir.path,
    );
    v6Meta = await SolderModelMetadata.load();
  });

  tearDownAll(() {
    if (tempTestDir.existsSync()) {
      tempTestDir.deleteSync(recursive: true);
    }
  });

  group('Soldy-Net-V6, Uncut Lead Rejection & Performance v1.0', () {
    test('1. Model Soldy-Net-V6 & taksonomi NON_SOLDER dimuat utuh', () {
      expect(v6Meta.isV6, isTrue);
      expect(v6Meta.modelName, equals(AppConstants.defaultModelVersion));
      expect(v6Meta.classes, containsAll([
        'PASS_NORMAL',
        'D1_BRIDGE',
        'D2_COLD',
        'D3_INSUFFICIENT',
        'D4_EXCESS',
        'D5_PINHOLE',
        'NON_SOLDER',
      ]));
    });

    test('2. Menolak kaki komponen belum dipotong (sintetis + foto lapangan Proses_Solder)', () async {
      // A. Uji papan sintetis hijau & merah dengan kawat komponen belum dipotong
      for (final red in [false, true]) {
        final uncutImg = _buildSyntheticUncutLeadBoard(redMask: red);
        final cvBoxes = SolderLocalizerService.detectSolderJoints(uncutImg);
        expect(
          cvBoxes,
          isEmpty,
          reason:
              'CV 16-ray filter harus menolak garis kawat lurus (redMask=$red): '
              '${cvBoxes.map((b) => "(${(b.x * 640).round()},${(b.y * 480).round()} ${(b.width * 640).round()}x${(b.height * 480).round()})").join(", ")}',
        );

        // Uji juga langsung engine AI pada crop potongan kawat lurus di posisi tengah kawat
        final wireCrop = img.copyCrop(uncutImg, x: 108, y: 180, width: 72, height: 72);
        final engine = SolderModelEngine(metadata: v6Meta);
        final wirePred = engine.predict(wireCrop, AppConstants.defaultConfidenceThreshold);
        expect(
          wirePred.isSolderJoint,
          isFalse,
          reason: 'Soldy-Net-V6 harus menandai crop kawat lurus sebagai NON_SOLDER '
              '(code=${wirePred.defectCode}, nonSolderScore=${wirePred.nonSolderScore}).',
        );
      }

      // B. Uji papan sintetis dengan titik solder melingkar asli -> harus tetap terdeteksi
      final trueBoard = _buildSyntheticTrueSolderBoard();
      final trueBytes = Uint8List.fromList(img.encodeJpg(trueBoard, quality: 92));
      final truePrecheck = await AIInferenceService.precheckAndDetectCapture(
        rawBytes: trueBytes,
        stagingDirPath: p.join(tempTestDir.path, 'qc_staging'),
        metadata: v6Meta,
      );
      expect(truePrecheck.isQualityPass, isTrue);
      expect(truePrecheck.detectedBoxes.length, greaterThanOrEqualTo(3));

      // C. Uji foto fixture nyata papan PCB dengan kawat kaki komponen belum dipotong
      final uncutFixture = File(p.join('test', 'fixtures', 'sample_uncut_leads.jpg'));
      expect(uncutFixture.existsSync(), isTrue, reason: 'Fixture uncut leads wajib ada');
      final uncutRes = await AIInferenceService.precheckAndDetectCapture(
        rawBytes: await uncutFixture.readAsBytes(),
        stagingDirPath: p.join(tempTestDir.path, 'qc_staging'),
        metadata: v6Meta,
      );
      expect(
        uncutRes.detectedBoxes,
        isEmpty,
        reason: 'Fixture PCB kaki komponen belum dipotong wajib 0 deteksi palsu, terbaca: '
            '${uncutRes.detectedBoxes.length}.',
      );
    });

    test('3. Benchmark performa: live frame 640x480 (<20ms steady) & pipeline Isolate 12MP real (<5000ms)', () async {
      // A. Live camera Y-plane 640x480 (1 warmup JIT + 5 steady frames)
      final yPlane = Uint8List(640 * 480);
      for (int y = 0; y < 480; y++) {
        for (int x = 0; x < 640; x++) {
          final dx = x - 320;
          final dy = y - 240;
          yPlane[y * 640 + x] = (dx * dx + dy * dy < 14 * 14) ? 235 : 88;
        }
      }
      final swCold = Stopwatch()..start();
      var liveAnalysis = SolderLocalizerService.analyzeLiveLuminanceFrame(
        yPlaneBytes: yPlane,
        width: 640,
        height: 480,
        bytesPerRow: 640,
      );
      swCold.stop();

      final swWarm = Stopwatch()..start();
      for (int i = 0; i < 5; i++) {
        liveAnalysis = SolderLocalizerService.analyzeLiveLuminanceFrame(
          yPlaneBytes: yPlane,
          width: 640,
          height: 480,
          bytesPerRow: 640,
        );
      }
      swWarm.stop();
      final warmAvgMs = swWarm.elapsedMilliseconds / 5.0;
      // ignore: avoid_print
      print(
        'PERF LiveFrame 640x480: cold=${swCold.elapsedMilliseconds} ms, '
        'steadyAvg=${warmAvgMs.toStringAsFixed(2)} ms | '
        'light=${liveAnalysis.lightStatus} focus=${liveAnalysis.focusStatus}',
      );
      expect(warmAvgMs, lessThan(25.0));

      // B. Pipeline penuh background Isolate pada fixture PCB nyata (Sample A & Sample B)
      final sampleAFile = File(p.join('test', 'fixtures', 'sample_tht_pcb_pass.jpg'));
      expect(sampleAFile.existsSync(), isTrue);
      final rawBytes = await sampleAFile.readAsBytes();

      final precheck = await AIInferenceService.precheckAndDetectCapture(
        rawBytes: rawBytes,
        stagingDirPath: p.join(tempTestDir.path, 'qc_staging'),
        metadata: v6Meta,
      );
      expect(precheck.isQualityPass, isTrue);
      expect(precheck.detectedBoxes.length, greaterThanOrEqualTo(5));

      final sampleBFile = File(p.join('test', 'fixtures', 'sample_tht_pcb_defect.jpg'));
      expect(sampleBFile.existsSync(), isTrue);
      final sampleBPrecheck = await AIInferenceService.precheckAndDetectCapture(
        rawBytes: await sampleBFile.readAsBytes(),
        stagingDirPath: p.join(tempTestDir.path, 'qc_staging'),
        metadata: v6Meta,
      );
      expect(sampleBPrecheck.isQualityPass, isTrue);
      expect(sampleBPrecheck.detectedBoxes.length, greaterThanOrEqualTo(15));
      for (final box in precheck.detectedBoxes) {
        expect(box.x, inInclusiveRange(0.0, 1.0));
        expect(box.y, inInclusiveRange(0.0, 1.0));
        expect(box.width, greaterThan(0.0));
        expect(box.height, greaterThan(0.0));
      }

      final repo = InspectionRepository(dbProvider: AppDatabase.instance);
      final defectTypes = await repo.getAllDefectTypes();
      final service = AIInferenceService(
        defectTypes: defectTypes,
        modelEngine: SolderModelEngine(metadata: v6Meta),
      );

      final optBytes = precheck.optimizedImagePath != null
          ? await File(precheck.optimizedImagePath!).readAsBytes()
          : rawBytes;

      final fullRes = await service.processMultiJointInspection(
        rawImageBytes: optBytes,
        jointBoxes: precheck.detectedBoxes,
        boardType: AppConstants.boardGeneralPcb,
      );
      expect(fullRes.isQualityPass, isTrue);
      expect(fullRes.inspection, isNotNull);
      expect(fullRes.inspection!.modelVersion, equals(AppConstants.defaultModelVersion));
      expect(fullRes.inspection!.joints, isNotEmpty);

      // ignore: avoid_print
      print(
        'PERF PCB Fixture A: precheck+detect=${precheck.detectLatencyMs} ms '
        '(${precheck.detectedBoxes.length} pads kept, ${precheck.filteredNonSolderCount} non-solder filtered), '
        'V6 inference=${fullRes.totalLatencyMs} ms',
      );
      expect(precheck.detectLatencyMs, lessThan(5000));
      expect(fullRes.totalLatencyMs, lessThan(5000));
    });
  });

  group('Arsitektur, Persistensi SQLite, UI Interaktif & Identitas Bersih', () {
    test('4. Database v4 default Soldy-Net-V6 & pencarian board_type + persistensi Locale', () async {
      final repo = InspectionRepository(dbProvider: AppDatabase.instance);
      final activeModel = await repo.getStringSetting('active_model_version', '');
      final defaultLocale = await repo.getStringSetting('app_locale', '');
      expect(activeModel, equals(AppConstants.defaultModelVersion));
      expect(defaultLocale, equals('id'));

      // Uji pencarian SQL berdasarkan board_type
      final nowIso = DateTime.now().toIso8601String();
      await repo.saveInspection(InspectionModel(
        inspectionCode: 'SL-SMD-001',
        inspectedAt: nowIso,
        boardType: AppConstants.boardSmdMixed,
        totalJoints: 1,
        passCount: 1,
        failCount: 0,
        uncertainCount: 0,
        overallResult: AppConstants.statusPass,
        imagePath: '',
        modelVersion: AppConstants.defaultModelVersion,
        totalInferenceTimeMs: 120,
        imageQualityStatus: 'OPTIMAL',
        manualReviewStatus: false,
        joints: const [
          InspectionJointModel(
            jointIndex: 1,
            bbox: NormalizedBoundingBox(x: 0.4, y: 0.4, width: 0.1, height: 0.1),
            result: AppConstants.statusPass,
            defectTypeId: 1,
            confidence: 0.94,
          ),
        ],
      ));
      await repo.saveInspection(InspectionModel(
        inspectionCode: 'SL-THT-002',
        inspectedAt: nowIso,
        boardType: AppConstants.boardFlipFlopTht,
        totalJoints: 1,
        passCount: 0,
        failCount: 1,
        uncertainCount: 0,
        overallResult: AppConstants.statusFail,
        imagePath: '',
        modelVersion: AppConstants.defaultModelVersion,
        totalInferenceTimeMs: 140,
        imageQualityStatus: 'OPTIMAL',
        manualReviewStatus: false,
        joints: const [
          InspectionJointModel(
            jointIndex: 1,
            bbox: NormalizedBoundingBox(x: 0.2, y: 0.2, width: 0.1, height: 0.1),
            result: AppConstants.statusFail,
            defectTypeId: 2,
            confidence: 0.91,
          ),
        ],
      ));

      final smdMatches = await repo.getInspections(searchQuery: 'SMD');
      expect(smdMatches.length, equals(1));
      expect(smdMatches.first.inspectionCode, equals('SL-SMD-001'));
    });

    testWidgets('5. Koreksi manual 1-ketuk di InspectionDetailScreen memperbarui SQLite', (tester) async {
      final repo = InspectionRepository(dbProvider: AppDatabase.instance);
      late int savedId;
      await tester.runAsync(() async {
        final defectTypes = await repo.getAllDefectTypes();
        final d4Type = defectTypes.firstWhere((e) => e.defectCode == AppConstants.defectD4);
        savedId = await repo.saveInspection(InspectionModel(
          inspectionCode: 'SL-REV-101',
          inspectedAt: DateTime.now().toIso8601String(),
          boardType: AppConstants.boardGeneralPcb,
          totalJoints: 1,
          passCount: 0,
          failCount: 1,
          uncertainCount: 0,
          overallResult: AppConstants.statusFail,
          imagePath: '',
          modelVersion: AppConstants.defaultModelVersion,
          totalInferenceTimeMs: 95,
          imageQualityStatus: 'OPTIMAL',
          manualReviewStatus: false,
          joints: [
            InspectionJointModel(
              jointIndex: 1,
              bbox: const NormalizedBoundingBox(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
              result: AppConstants.statusFail,
              defectTypeId: d4Type.id,
              confidence: 0.88,
              defectType: d4Type,
            ),
          ],
        ));
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Verifikasi default locale 'id' & persistensi switch bahasa
      expect(container.read(localeProvider), equals('id'));
      container.read(localeProvider.notifier).setLocale('en');
      await tester.pump();
      late String persistedLocale;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        persistedLocale = await repo.getStringSetting('app_locale', 'id');
      });
      expect(persistedLocale, equals('en'));
      container.read(localeProvider.notifier).setLocale('id');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InspectionDetailScreen(inspectionId: savedId),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 220)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('#SL-REV-101'), findsOneWidget);
      expect(find.text('Titik Solder #1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Titik Solder #1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Titik Solder #1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Koreksi Manual • Titik #1'), findsOneWidget);
      await tester.tap(find.text(AppConstants.defectPass));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 220)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      expect(find.text('Titik #1 diperbarui ke PASS_NORMAL.'), findsOneWidget);
      InspectionModel? updated;
      await tester.runAsync(() async {
        updated = await repo.getInspectionById(savedId);
      });
      expect(updated, isNotNull);
      expect(updated!.manualReviewStatus, isTrue);
      expect(updated!.passCount, equals(1));
      expect(updated!.failCount, equals(0));
      expect(updated!.overallResult, equals(AppConstants.statusPass));
    });

    testWidgets('6. Animasi SoldyAvatarAnimated & SoldyCoachBanner anti-overflow di layar sempit', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SoldyAvatarAnimated(
                      size: 80,
                      mood: SoldyMood.happy,
                      forceAmbientAnimationInTest: true,
                      onTap: () => tapCount++,
                    ),
                    const SizedBox(height: 12),
                    const SoldyCoachBanner(
                      mood: SoldyMood.warning,
                      badge: 'PANDUAN SOLDY SEBELUM MEMBIDIK PCB',
                      messages: ['Tip pertama pemeriksaan.', 'Tip kedua pencahayaan.'],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Pump beberapa frame animasi napas & kedip agar dipastikan bebas leak / error
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);

      expect(find.text('Ketuk tip (1/2)'), findsOneWidget);
      expect(find.text('Tip pertama pemeriksaan.'), findsOneWidget);

      await tester.tap(find.byType(SoldyAvatarAnimated).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tapCount, equals(1));

      await tester.tap(find.text('Ketuk tip (1/2)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ketuk tip (2/2)'), findsOneWidget);
      expect(find.text('Tip kedua pencahayaan.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('7. Identitas SolderLab v1.0 bebas total dari kebocoran proyek lain & path lokal', () {
      final forbidden = RegExp(
        r'01_DATA_LAPANGAN|Mahasiswa_|C:/Users/|C:\\Users\\|220\s*pad|220\s*lubang|TIM\s*KERTAS',
        caseSensitive: false,
      );
      final scanDirs = [
        Directory('lib'),
        Directory('assets/branding'),
        Directory('assets/models'),
        Directory('ai_training'),
      ];
      final leaks = <String>[];

      void checkFile(File file) {
        if (!file.existsSync()) return;
        final content = file.readAsStringSync();
        final match = forbidden.firstMatch(content);
        if (match != null) {
          leaks.add('${file.path}: ${match.group(0)}');
        }
      }

      checkFile(File('pubspec.yaml'));
      checkFile(File('README.md'));
      for (final dir in scanDirs) {
        if (!dir.existsSync()) continue;
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File &&
              (entity.path.endsWith('.dart') ||
                  entity.path.endsWith('.py') ||
                  entity.path.endsWith('.md') ||
                  entity.path.endsWith('.svg') ||
                  entity.path.endsWith('.txt') ||
                  entity.path.endsWith('.json'))) {
            checkFile(entity);
          }
        }
      }
      expect(leaks, isEmpty, reason: 'Ditemukan referensi proyek/path sensitif: $leaks');
    });
  });
}
