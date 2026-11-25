import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/constants/app_constants.dart';

/// Database Helper SQLite Lokal untuk QC Solder
class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;
  static String customDbName = AppConstants.dbName;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(customDbName);
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final path = filePath == inMemoryDatabasePath
        ? inMemoryDatabasePath
        : join(await getDatabasesPath(), filePath);

    return await openDatabase(
      path,
      version: AppConstants.dbVersion,
      onConfigure: _onConfigure,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE inspections ADD COLUMN is_rework INTEGER NOT NULL DEFAULT 0');
        await db.execute('ALTER TABLE inspections ADD COLUMN parent_inspection_id INTEGER REFERENCES inspections(id) ON DELETE SET NULL');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_inspections_rework ON inspections(parent_inspection_id)');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          "UPDATE app_settings SET setting_value = '0.50' WHERE setting_key = 'confidence_threshold' AND setting_value IN ('0.70', '0.40')",
        );
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute(
          "UPDATE app_settings SET setting_value = 'Soldy-Net-V6' WHERE setting_key = 'active_model_version'",
        );
        await db.execute('UPDATE model_information SET is_active = 0');
        await db.insert(
          'model_information',
          {
            'model_name': 'Soldy-Net-V6',
            'version': 'Soldy-Net-V6',
            'model_path': 'assets/models/soldy_v6_model.json',
            'input_dimensions': '32x32x3 (48 fitur Soldy AI V6)',
            'training_date': '2026-11-25',
            'model_checksum': 'soldy-v6-mlp-extratrees',
            'is_active': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Defect Types
    await db.execute('''
      CREATE TABLE defect_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        defect_code TEXT NOT NULL UNIQUE,
        defect_name TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        quality_status TEXT NOT NULL
      )
    ''');

    // 2. Model Information
    await db.execute('''
      CREATE TABLE model_information (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model_name TEXT NOT NULL,
        version TEXT NOT NULL UNIQUE,
        model_path TEXT NOT NULL,
        input_dimensions TEXT NOT NULL DEFAULT '224x224x3',
        training_date TEXT NOT NULL,
        model_checksum TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
      )
    ''');

    // 3. Inspections (Parent)
    await db.execute('''
      CREATE TABLE inspections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inspection_code TEXT NOT NULL UNIQUE,
        inspected_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
        board_type TEXT NOT NULL DEFAULT 'GENERAL_PCB',
        total_joints INTEGER NOT NULL DEFAULT 1,
        pass_count INTEGER NOT NULL DEFAULT 0,
        fail_count INTEGER NOT NULL DEFAULT 0,
        uncertain_count INTEGER NOT NULL DEFAULT 0,
        overall_result TEXT NOT NULL CHECK (overall_result IN ('PASS', 'FAIL', 'UNCERTAIN', 'LULUS', 'REWORK')),
        image_path TEXT NOT NULL,
        model_version TEXT NOT NULL,
        total_inference_time_ms INTEGER NOT NULL,
        image_quality_status TEXT NOT NULL DEFAULT 'OPTIMAL',
        notes TEXT,
        manual_review_status INTEGER NOT NULL DEFAULT 0 CHECK (manual_review_status IN (0, 1)),
        is_rework INTEGER NOT NULL DEFAULT 0 CHECK (is_rework IN (0, 1)),
        parent_inspection_id INTEGER,
        FOREIGN KEY (model_version) REFERENCES model_information (version) ON UPDATE CASCADE ON DELETE RESTRICT,
        FOREIGN KEY (parent_inspection_id) REFERENCES inspections (id) ON DELETE SET NULL
      )
    ''');

    // 4. Inspection Joints (Child / Multi-Joint)
    await db.execute('''
      CREATE TABLE inspection_joints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inspection_id INTEGER NOT NULL,
        joint_index INTEGER NOT NULL,
        bbox_x REAL NOT NULL,
        bbox_y REAL NOT NULL,
        bbox_w REAL NOT NULL,
        bbox_h REAL NOT NULL,
        result TEXT NOT NULL CHECK (result IN ('PASS', 'FAIL', 'UNCERTAIN')),
        defect_type_id INTEGER,
        confidence REAL NOT NULL CHECK (confidence >= 0.0 AND confidence <= 1.0),
        crop_image_path TEXT,
        FOREIGN KEY (inspection_id) REFERENCES inspections (id) ON DELETE CASCADE,
        FOREIGN KEY (defect_type_id) REFERENCES defect_types (id) ON UPDATE CASCADE ON DELETE SET NULL
      )
    ''');

    // 5. App Settings
    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        setting_key TEXT NOT NULL UNIQUE,
        setting_value TEXT NOT NULL
      )
    ''');

    // Indeks Performa
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspections_inspected_at ON inspections(inspected_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspections_overall_result ON inspections(overall_result)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspections_code ON inspections(inspection_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspections_rework ON inspections(parent_inspection_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspection_joints_insp_id ON inspection_joints(inspection_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspection_joints_result ON inspection_joints(result)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspection_joints_defect ON inspection_joints(defect_type_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_inspection_joints_comp ON inspection_joints(inspection_id, result)');

    // Seed Data Defect Types
    final List<Map<String, dynamic>> initialDefects = [
      {
        'id': 1,
        'defect_code': 'PASS_NORMAL',
        'defect_name': 'Normal Solder Joint',
        'description': 'Sambungan memenuhi kriteria standar visual: meniskus cekung, sudut kontak <= 90 derajat, barrel fill >= 75%, cakupan pad melingkar penuh.',
        'category': 'CONFORMANCE',
        'quality_status': 'PASS',
      },
      {
        'id': 2,
        'defect_code': 'D1_BRIDGE',
        'defect_name': 'Solder Bridging',
        'description': 'Jembatan logam timah abnormal yang menghubungkan dua pad/konduktor terisolasi berdekatan.',
        'category': 'VOLUME',
        'quality_status': 'FAIL',
      },
      {
        'id': 3,
        'defect_code': 'D2_COLD',
        'defect_name': 'Cold / Disturbed Solder',
        'description': 'Sambungan kusam, berpori, berbutir, atau retak mikro akibat defisit panas atau getaran saat pembekuan.',
        'category': 'THERMAL',
        'quality_status': 'FAIL',
      },
      {
        'id': 4,
        'defect_code': 'D3_INSUFFICIENT',
        'defect_name': 'Insufficient Wetting / Solder',
        'description': 'Timah gagal membasahi kaki komponen atau pad sirkuit (sudut kontak > 90 derajat atau barrel fill < 75%).',
        'category': 'WETTING',
        'quality_status': 'FAIL',
      },
      {
        'id': 5,
        'defect_code': 'D4_EXCESS',
        'defect_name': 'Excess Solder',
        'description': 'Gumpalan timah cembung bulat berlebih melampaui perimeter pad atau terdapat butiran timah liar.',
        'category': 'VOLUME',
        'quality_status': 'FAIL',
      },
      {
        'id': 6,
        'defect_code': 'D5_PINHOLE',
        'defect_name': 'Pin Holes / Blow Holes',
        'description': 'Rongga gas mikro atau kawah berlubang pada permukaan meniskus fillet solder akibat uap kelembapan PCB.',
        'category': 'THERMAL',
        'quality_status': 'FAIL',
      },
    ];

    for (var defect in initialDefects) {
      await db.insert('defect_types', defect);
    }

    // Seed Data Model Info
    await db.insert('model_information', {
      'id': 1,
      'model_name': 'Soldy-Net-V6',
      'version': 'Soldy-Net-V6',
      'model_path': 'assets/models/soldy_v6_model.json',
      'input_dimensions': '32x32x3 (48 fitur Soldy AI V6)',
      'training_date': '2026-11-25',
      'model_checksum': 'soldy-v6-mlp-extratrees',
      'is_active': 1,
    });

    // Seed App Settings
    await db.insert('app_settings', {'setting_key': 'confidence_threshold', 'setting_value': '0.50'});
    await db.insert('app_settings', {'setting_key': 'blur_threshold', 'setting_value': '20.0'});
    await db.insert('app_settings', {'setting_key': 'detection_mode', 'setting_value': 'MULTI_JOINT'});
    await db.insert('app_settings', {'setting_key': 'active_model_version', 'setting_value': 'Soldy-Net-V6'});
    await db.insert('app_settings', {'setting_key': 'operator_name', 'setting_value': 'Teknisi QC'});
    await db.insert('app_settings', {'setting_key': 'app_locale', 'setting_value': 'id'});
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
