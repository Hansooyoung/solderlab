import 'dart:developer' as developer;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/defect_type_model.dart';
import '../models/inspection_joint_model.dart';
import '../models/inspection_model.dart';

/// Ringkasan Metrik Statistik Riwayat Inspeksi
class QCStatistics {
  final int totalInspections;
  final int totalJointsInspected;
  final int totalPassJoints;
  final int totalFailJoints;
  final int totalUncertainJoints;
  final double overallYieldRate; // persentase lolos
  final Map<String, int> defectBreakdown; // D1 s.d. D5 counts

  const QCStatistics({
    required this.totalInspections,
    required this.totalJointsInspected,
    required this.totalPassJoints,
    required this.totalFailJoints,
    required this.totalUncertainJoints,
    required this.overallYieldRate,
    required this.defectBreakdown,
  });
}

/// Repository Pengelolaan Data Inspeksi QC Solder
class InspectionRepository {
  final AppDatabase _dbProvider;

  InspectionRepository({AppDatabase? dbProvider})
      : _dbProvider = dbProvider ?? AppDatabase.instance;

  /// Simpan Sesi Inspeksi Beserta Rincian Seluruh Titik Sambungan (Atomic Transaction)
  /// Menyalin citra dari staging/cache sementara ke direktori permanen hanya saat dikomit
  Future<int> saveInspection(InspectionModel inspection) async {
    final db = await _dbProvider.database;

    String permanentImagePath = inspection.imagePath;
    final List<InspectionJointModel> permanentJoints = [];

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final permDir = Directory('${appDir.path}/qc_inspections');
      if (!await permDir.exists()) {
        await permDir.create(recursive: true);
      }

      // Salin foto utama beranotasi ke dokumen permanen jika berada di staging/temp
      final origMainFile = File(inspection.imagePath);
      if (await origMainFile.exists()) {
        final targetPath = '${permDir.path}/full_${inspection.inspectionCode}.jpg';
        if (origMainFile.path != targetPath) {
          await origMainFile.copy(targetPath);
          permanentImagePath = targetPath;
        }
      }

      // Salin thumbnail crop tiap titik solder
      for (final joint in inspection.joints) {
        String? permCropPath = joint.cropImagePath;
        if (joint.cropImagePath != null) {
          final origCropFile = File(joint.cropImagePath!);
          if (await origCropFile.exists()) {
            final targetCrop = '${permDir.path}/crop_${inspection.inspectionCode}_j${joint.jointIndex}.jpg';
            if (origCropFile.path != targetCrop) {
              await origCropFile.copy(targetCrop);
              permCropPath = targetCrop;
            }
          }
        }
        permanentJoints.add(joint.copyWith(cropImagePath: permCropPath));
      }
    } catch (e, st) {
      // Fallback: path cache tetap dipakai, tetapi kegagalan salin dicatat (tidak lagi senyap)
      developer.log('Gagal menyalin citra ke penyimpanan permanen: $e', name: 'InspectionRepository', stackTrace: st);
    }

    final inspectionToSave = permanentJoints.isNotEmpty
        ? inspection.copyWith(imagePath: permanentImagePath, joints: permanentJoints)
        : inspection;

    return await db.transaction<int>((txn) async {
      // 0. Pastikan versi model terdaftar (FK model_version -> model_information.version)
      await txn.insert(
        'model_information',
        {
          'model_name': inspectionToSave.modelVersion,
          'version': inspectionToSave.modelVersion,
          'model_path': 'embedded',
          'input_dimensions': '64x64 (11 fitur fotometri)',
          'training_date': DateTime.now().toIso8601String().substring(0, 10),
          'model_checksum': 'n/a',
          'is_active': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // 1. Simpan Parent Inspection
      final inspectionId = await txn.insert(
        'inspections',
        inspectionToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Simpan Rincian Tiap Titik Solder
      for (final joint in inspectionToSave.joints) {
        final jointMap = joint.toMap();
        jointMap['inspection_id'] = inspectionId;
        await txn.insert(
          'inspection_joints',
          jointMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      return inspectionId;
    });
  }

  /// Ambil Semua Riwayat Inspeksi dengan Filter & Pencarian (Optimasi Batch: Bebas N+1)
  Future<List<InspectionModel>> getInspections({
    String? resultFilter,
    String? searchQuery,
    int limit = 50,
    bool loadJoints = true,
  }) async {
    final db = await _dbProvider.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (resultFilter != null && resultFilter.isNotEmpty && resultFilter != 'ALL') {
      whereClause = 'overall_result = ?';
      whereArgs.add(resultFilter);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final queryParam = '%${searchQuery.trim()}%';
      const searchExpr = '(inspection_code LIKE ? OR board_type LIKE ? OR notes LIKE ?)';
      if (whereClause.isNotEmpty) {
        whereClause += ' AND $searchExpr';
      } else {
        whereClause = searchExpr;
      }
      whereArgs.addAll([queryParam, queryParam, queryParam]);
    }

    final List<Map<String, dynamic>> records = await db.query(
      'inspections',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'inspected_at DESC',
      limit: limit,
    );

    if (records.isEmpty) return [];

    if (!loadJoints) {
      return records.map((row) => InspectionModel.fromMap(row, joints: const [])).toList();
    }

    // Resolusi N+1: Single Batch Query untuk seluruh joints dalam satu roundtrip
    final inspectionIds = records.map((r) => r['id'] as int).toList();
    final placeholders = List.filled(inspectionIds.length, '?').join(',');
    final rawJoints = await db.rawQuery('''
      SELECT j.*, d.defect_code, d.defect_name, d.description, d.category, d.quality_status
      FROM inspection_joints j
      LEFT JOIN defect_types d ON j.defect_type_id = d.id
      WHERE j.inspection_id IN ($placeholders)
      ORDER BY j.joint_index ASC
    ''', inspectionIds);

    final Map<int, List<InspectionJointModel>> jointsMap = {};
    for (final row in rawJoints) {
      final inspId = row['inspection_id'] as int;
      DefectTypeModel? defect;
      if (row['defect_type_id'] != null && row['defect_code'] != null) {
        defect = DefectTypeModel(
          id: row['defect_type_id'] as int,
          defectCode: row['defect_code'] as String,
          defectName: row['defect_name'] as String,
          description: row['description'] as String,
          category: row['category'] as String,
          qualityStatus: row['quality_status'] as String,
        );
      }
      final joint = InspectionJointModel.fromMap(row, defectType: defect);
      jointsMap.putIfAbsent(inspId, () => []).add(joint);
    }

    final List<InspectionModel> results = [];
    for (final row in records) {
      final inspectionId = row['id'] as int;
      results.add(InspectionModel.fromMap(row, joints: jointsMap[inspectionId] ?? const []));
    }

    return results;
  }

  /// Ambil Rincian Inspeksi berdasarkan ID Lengkap dengan Joints & Defect Metadata
  Future<InspectionModel?> getInspectionById(int id) async {
    final db = await _dbProvider.database;

    final records = await db.query(
      'inspections',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (records.isEmpty) return null;

    final joints = await _getJointsForInspection(db, id);
    return InspectionModel.fromMap(records.first, joints: joints);
  }

  /// Ambil Rincian Titik Solder (Joints) untuk Sesi Tertentu
  Future<List<InspectionJointModel>> _getJointsForInspection(
    DatabaseExecutor db,
    int inspectionId,
  ) async {
    final rawJoints = await db.rawQuery('''
      SELECT j.*, d.defect_code, d.defect_name, d.description, d.category, d.quality_status
      FROM inspection_joints j
      LEFT JOIN defect_types d ON j.defect_type_id = d.id
      WHERE j.inspection_id = ?
      ORDER BY j.joint_index ASC
    ''', [inspectionId]);

    return rawJoints.map((row) {
      DefectTypeModel? defect;
      if (row['defect_type_id'] != null && row['defect_code'] != null) {
        defect = DefectTypeModel(
          id: row['defect_type_id'] as int,
          defectCode: row['defect_code'] as String,
          defectName: row['defect_name'] as String,
          description: row['description'] as String,
          category: row['category'] as String,
          qualityStatus: row['quality_status'] as String,
        );
      }
      return InspectionJointModel.fromMap(row, defectType: defect);
    }).toList();
  }

  /// Hapus Inspeksi Beserta File Gambarnya dari Disk
  Future<void> deleteInspection(int id) async {
    final db = await _dbProvider.database;

    final inspection = await getInspectionById(id);
    if (inspection != null) {
      // Hapus file foto utama
      try {
        final mainImg = File(inspection.imagePath);
        if (await mainImg.exists()) await mainImg.delete();
      } catch (_) {}

      // Hapus file crop titik solder
      for (final joint in inspection.joints) {
        if (joint.cropImagePath != null) {
          try {
            final cropImg = File(joint.cropImagePath!);
            if (await cropImg.exists()) await cropImg.delete();
          } catch (_) {}
        }
      }
    }

    await db.delete('inspections', where: 'id = ?', whereArgs: [id]);
  }

  /// Ambil Data Seluruh Taksonomi Cacat
  Future<List<DefectTypeModel>> getAllDefectTypes() async {
    final db = await _dbProvider.database;
    final records = await db.query('defect_types', orderBy: 'id ASC');
    return records.map((e) => DefectTypeModel.fromMap(e)).toList();
  }

  /// Hitung Statistik Riwayat Real-Time dari Tabel SQLite
  Future<QCStatistics> calculateStatistics() async {
    final db = await _dbProvider.database;

    // Total sesi inspeksi
    final totalSessionsCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM inspections'),
        ) ??
        0;

    // Agregat Titik Solder (Joints)
    final jointStats = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_joints,
        SUM(CASE WHEN result = 'PASS' THEN 1 ELSE 0 END) as total_pass,
        SUM(CASE WHEN result = 'FAIL' THEN 1 ELSE 0 END) as total_fail,
        SUM(CASE WHEN result = 'UNCERTAIN' THEN 1 ELSE 0 END) as total_uncertain
      FROM inspection_joints
    ''');

    int totalJoints = 0;
    int totalPass = 0;
    int totalFail = 0;
    int totalUncertain = 0;

    if (jointStats.isNotEmpty) {
      totalJoints = (jointStats.first['total_joints'] as num?)?.toInt() ?? 0;
      totalPass = (jointStats.first['total_pass'] as num?)?.toInt() ?? 0;
      totalFail = (jointStats.first['total_fail'] as num?)?.toInt() ?? 0;
      totalUncertain = (jointStats.first['total_uncertain'] as num?)?.toInt() ?? 0;
    }

    // Breakdown per jenis defect D1-D5
    final defectCountsRaw = await db.rawQuery('''
      SELECT d.defect_code, COUNT(j.id) as count
      FROM defect_types d
      LEFT JOIN inspection_joints j ON d.id = j.defect_type_id
      WHERE d.quality_status = 'FAIL'
      GROUP BY d.defect_code
      ORDER BY count DESC
    ''');

    final Map<String, int> defectBreakdown = {
      'D1_BRIDGE': 0,
      'D2_COLD': 0,
      'D3_INSUFFICIENT': 0,
      'D4_EXCESS': 0,
      'D5_PINHOLE': 0,
    };

    for (final row in defectCountsRaw) {
      final code = row['defect_code'] as String?;
      final count = (row['count'] as num?)?.toInt() ?? 0;
      if (code != null) defectBreakdown[code] = count;
    }

    final double yieldRate = totalJoints > 0 ? (totalPass / totalJoints) * 100.0 : 0.0;

    return QCStatistics(
      totalInspections: totalSessionsCount,
      totalJointsInspected: totalJoints,
      totalPassJoints: totalPass,
      totalFailJoints: totalFail,
      totalUncertainJoints: totalUncertain,
      overallYieldRate: yieldRate,
      defectBreakdown: defectBreakdown,
    );
  }

  /// Perbarui hasil inspeksi setelah verifikasi/koreksi manual operator
  Future<void> updateInspectionReview(InspectionModel updated) async {
    if (updated.id == null) return;
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.update(
        'inspections',
        {
          'pass_count': updated.passCount,
          'fail_count': updated.failCount,
          'uncertain_count': updated.uncertainCount,
          'overall_result': updated.overallResult,
          'manual_review_status': updated.manualReviewStatus ? 1 : 0,
          'notes': updated.notes,
        },
        where: 'id = ?',
        whereArgs: [updated.id],
      );

      for (final joint in updated.joints) {
        if (joint.id != null) {
          await txn.update(
            'inspection_joints',
            {
              'result': joint.result,
              'defect_type_id': joint.defectTypeId,
              'confidence': joint.confidence,
            },
            where: 'id = ?',
            whereArgs: [joint.id],
          );
        }
      }
    });
  }

  /// Tren tingkat lolos (%) per hari untuk [days] hari tercatat terakhir (urut lama -> baru)
  Future<List<double>> getDailyYieldTrend({int days = 7}) async {
    final db = await _dbProvider.database;
    final rows = await db.rawQuery('''
      SELECT substr(inspected_at, 1, 10) AS day,
             SUM(pass_count) AS pass_total,
             SUM(total_joints) AS joint_total
      FROM inspections
      GROUP BY day
      ORDER BY day DESC
      LIMIT ?
    ''', [days]);
    return rows.reversed
        .where((r) => ((r['joint_total'] as num?) ?? 0) > 0)
        .map((r) => ((r['pass_total'] as num).toDouble() / (r['joint_total'] as num).toDouble()) * 100.0)
        .toList();
  }

  /// Baca nilai pengaturan teks; kembalikan [fallback] jika belum ada
  Future<String> getStringSetting(String key, String fallback) async {
    final db = await _dbProvider.database;
    final res = await db.query('app_settings', where: 'setting_key = ?', whereArgs: [key]);
    if (res.isEmpty) return fallback;
    final val = '${res.first['setting_value'] ?? ''}'.trim();
    return val.isEmpty ? fallback : val;
  }

  /// Baca nilai pengaturan numerik; kembalikan [fallback] jika belum ada/tidak valid
  Future<double> getDoubleSetting(String key, double fallback) async {
    final db = await _dbProvider.database;
    final res = await db.query('app_settings', where: 'setting_key = ?', whereArgs: [key]);
    if (res.isEmpty) return fallback;
    return double.tryParse('${res.first['setting_value']}') ?? fallback;
  }

  /// Simpan nilai pengaturan (upsert)
  Future<void> setSetting(String key, String value) async {
    final db = await _dbProvider.database;
    await db.insert(
      'app_settings',
      {'setting_key': key, 'setting_value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Cek apakah perizinan sudah pernah disetujui sebelumnya
  Future<bool> isPermissionGranted() async {
    final db = await _dbProvider.database;
    final res = await db.query(
      'app_settings',
      where: 'setting_key = ?',
      whereArgs: ['permissions_granted'],
    );
    if (res.isNotEmpty && res.first['setting_value'] == 'true') {
      return true;
    }
    return false;
  }

  /// Simpan status perizinan agar tidak berulang setiap buka aplikasi
  Future<void> setPermissionGranted(bool granted) async {
    final db = await _dbProvider.database;
    await db.insert(
      'app_settings',
      {
        'setting_key': 'permissions_granted',
        'setting_value': granted ? 'true' : 'false',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
