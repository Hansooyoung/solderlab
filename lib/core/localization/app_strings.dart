/// Multi-Language Translation Dictionary (English default & Indonesian)
class AppStrings {
  static const Map<String, Map<String, String>> _translations = {
    // APP GENERAL
    'appName': {
      'en': 'SolderLab',
      'id': 'SolderLab',
    },
    'appSubtitle': {
      'en': 'ELECTRONIC SOLDER INSPECTION & PRACTICE',
      'id': 'ASISTEN INSPEKSI & PRAKTIK SOLDER ELEKTRONIKA',
    },
    'systemReady': {
      'en': 'System Ready • Solder Quality Standard',
      'id': 'Sistem Siap Digunakan • Standar Mutu Solder',
    },

    // SPLASH SCREEN
    'allocatingCache': {
      'en': 'Preparing local memory cache...',
      'id': 'Menyiapkan memori kerja lokal perangkat...',
    },
    'checkingDatabase': {
      'en': 'Verifying solder quality database...',
      'id': 'Memverifikasi basis data standar mutu solder...',
    },
    'loadingAI': {
      'en': 'Loading local AI inspection engine...',
      'id': 'Memuat mesin kecerdasan buatan on-device...',
    },
    'systemReadySplash': {
      'en': 'SolderLab system is ready.',
      'id': 'Sistem SolderLab siap digunakan.',
    },
    'completedPercent': {
      'en': 'Completed',
      'id': 'Selesai',
    },

    // PERMISSIONS SCREEN
    'deviceAccessRequired': {
      'en': 'DEVICE ACCESS REQUIRED',
      'id': 'AKSES PERANGKAT DIPERLUKAN',
    },
    'permissionDesc': {
      'en': 'SolderLab requires hardware permissions to scan circuit boards and store inspection records.',
      'id': 'SolderLab memerlukan akses perangkat keras untuk memindai papan sirkuit dan mencatat data inspeksi.',
    },
    'cameraPermissionTitle': {
      'en': 'Camera Hardware Access',
      'id': 'Izin Kamera Perangkat',
    },
    'cameraPermissionDesc': {
      'en': 'Used to capture solder joints on through-hole components and detect multiple pads in real-time.',
      'id': 'Digunakan untuk membidik sambungan solder kaki komponen through-hole dan mendeteksi multi-titik pad.',
    },
    'storagePermissionTitle': {
      'en': 'Storage & Directory Access',
      'id': 'Izin Penyimpanan & Direktori',
    },
    'storagePermissionDesc': {
      'en': 'Used to save inspection evidence images, local SQLite database tables, and PDF/CSV reports.',
      'id': 'Digunakan untuk menyimpan file bukti foto inspeksi, tabel basis data riwayat, dan berkas ekspor PDF/CSV.',
    },
    'privacyGuarantee': {
      'en': 'This application does not run in the background when minimized or closed. All camera feeds and computing processes are automatically released for battery efficiency and privacy.',
      'id': 'Aplikasi tidak berjalan di latar belakang saat diminimalkan atau ditutup. Seluruh proses kamera dan komputasi otomatis dibebaskan demi efisiensi baterai dan privasi.',
    },
    'grantAndContinue': {
      'en': 'GRANT & ENTER APPLICATION',
      'id': 'SETUJUI & MASUK KE APLIKASI',
    },

    // DASHBOARD
    'totalJointsTested': {
      'en': 'Total Joints Tested',
      'id': 'Total Titik Diuji',
    },
    'yieldRate': {
      'en': 'Optimal Rate',
      'id': 'Tingkat Kerapian',
    },
    'startScan': {
      'en': 'START MULTI-SOLDER SCAN',
      'id': 'MULAI PINDAI MULTI-SOLDER',
    },
    'recentInspections': {
      'en': 'RECENT INSPECTION HISTORY',
      'id': 'RIWAYAT PEMERIKSAAN TERAKHIR',
    },
    'viewAll': {
      'en': 'View All',
      'id': 'Lihat Semua',
    },
    'noHistoryYet': {
      'en': 'No inspection history yet.',
      'id': 'Belum ada data riwayat inspeksi.',
    },
    'pressAboveToStart': {
      'en': 'Tap the button above to begin camera scanning.',
      'id': 'Tekan tombol di atas untuk memulai pemindaian.',
    },
    'passLabel': {
      'en': 'PASS',
      'id': 'LULUS',
    },
    'failLabel': {
      'en': 'REWORK',
      'id': 'REWORK',
    },
    'reviewLabel': {
      'en': 'REVIEW',
      'id': 'REVIEW',
    },

    // CAMERA VIEW & PRE-CAPTURE VALIDATION
    'multiJointMode': {
      'en': 'Scan Multi-Solder PCB',
      'id': 'Scan Multi-Solder PCB',
    },
    'singleMacroMode': {
      'en': 'Macro Joint Inspection',
      'id': 'Scan Makro Sambungan',
    },
    'multiInstruction': {
      'en': 'Point camera at the PCB solder side. System detects multiple joints automatically.',
      'id': 'Arahkan kamera ke area sambungan solder PCB. Sistem mendeteksi multi-titik otomatis.',
    },
    'macroInstruction': {
      'en': 'Center one solder joint or pad inside the guide box.',
      'id': 'Pusatkan satu kaki komponen/pad solder pada kotak panduan.',
    },
    'analyzingJoints': {
      'en': 'Analyzing Solder Joints...',
      'id': 'Menganalisis Titik Solder Elektronika...',
    },
    'statusLightingOk': {
      'en': 'Light: Optimal',
      'id': 'Cahaya: Optimal',
    },
    'statusLightingDark': {
      'en': 'Light: Too Dark (Turn on Flash)',
      'id': 'Cahaya: Terlalu Gelap (Nyalakan Flash)',
    },
    'statusLightingGlare': {
      'en': 'Light: Glare Detected',
      'id': 'Cahaya: Silau Berlebih',
    },
    'statusFocusSharp': {
      'en': 'Focus: Sharp',
      'id': 'Fokus: Tajam',
    },
    'statusFocusBlur': {
      'en': 'Focus: Blurry / Hold Steady',
      'id': 'Fokus: Buram / Tahan Stabil',
    },
    'statusSolderFound': {
      'en': 'Joints Detected',
      'id': 'Titik Solder Terdeteksi',
    },
    'statusNoSolder': {
      'en': 'No Solder Joints In Frame',
      'id': 'Belum Terdeteksi Sambungan Solder',
    },
    'retakeNeeded': {
      'en': 'Photo Needs Retake',
      'id': 'Foto Perlu Diulang',
    },
    'retakeButton': {
      'en': 'RETAKE',
      'id': 'AMBIL ULANG',
    },

    // INSPECTION RESULT
    'inspectionResultTitle': {
      'en': 'Inspection Results',
      'id': 'Hasil Inspeksi Solder',
    },
    'passResultTitle': {
      'en': 'PASSED CONFORMANCE',
      'id': 'LULUS STANDAR OPTIMAL',
    },
    'failResultTitle': {
      'en': 'REWORK REQUIRED',
      'id': 'PERLU REWORK',
    },
    'passResultDesc': {
      'en': 'All solder pads satisfy visual concave meniscus criteria.',
      'id': 'Seluruh titik pad memenuhi kriteria meniskus cekung standar visual.',
    },
    'failResultDescPrefix': {
      'en': 'Found',
      'id': 'Ditemukan',
    },
    'failResultDescSuffix': {
      'en': 'defective joints out of total inspected pads.',
      'id': 'titik cacat dari total titik solder yang diperiksa.',
    },
    'rescan': {
      'en': 'RESCAN',
      'id': 'PINDAI ULANG',
    },
    'saveToDatabase': {
      'en': 'SAVE TO DATABASE',
      'id': 'SIMPAN KE BASIS DATA',
    },
    'saved': {
      'en': 'SAVED',
      'id': 'TERSAMPAN',
    },
    'saving': {
      'en': 'SAVING...',
      'id': 'MENYIMPAN...',
    },
    'exportPdf': {
      'en': 'Export PDF',
      'id': 'Ekspor PDF',
    },
    'exportCsv': {
      'en': 'Export CSV',
      'id': 'Ekspor CSV',
    },

    // STATISTICS
    'statisticsTitle': {
      'en': 'Solder Quality Statistics',
      'id': 'Statistik Mutu Solder',
    },
    'defectDistributionTitle': {
      'en': 'SOLDER DEFECT BREAKDOWN (D1 - D5)',
      'id': 'DISTRIBUSI KATEGORI CACAT SOLDER (D1 - D5)',
    },
    'engineeringNotes': {
      'en': 'Quality Engineering Diagnostics',
      'id': 'Catatan Rekayasa Kendali Mutu',
    },

    // SETTINGS
    'settingsTitle': {
      'en': 'Settings & AI Model',
      'id': 'Pengaturan & AI Model',
    },
    'languageSection': {
      'en': 'LANGUAGE / BAHASA',
      'id': 'PILIHAN BAHASA / LANGUAGE',
    },
    'englishOption': {
      'en': 'English (Default)',
      'id': 'English (Default)',
    },
    'indonesianOption': {
      'en': 'Bahasa Indonesia',
      'id': 'Bahasa Indonesia',
    },
    'aiModelInfoSection': {
      'en': 'LOCAL AI MODEL SPECIFICATIONS',
      'id': 'INFORMASI MODEL AI LOKAL',
    },
    'toleranceSection': {
      'en': 'INSPECTION TOLERANCE THRESHOLDS',
      'id': 'AMBANG BATAS INFERENSI & OPTIK',
    },
    'scanModeSection': {
      'en': 'DEFAULT SCANNING MODE',
      'id': 'MODE PEMINDAIAN DEFAULT',
    },
    'diagnosticsSection': {
      'en': 'DATA & DIAGNOSTICS',
      'id': 'DATA PEMERIKSAAN & DIAGNOSTIK',
    },
  };

  /// Ambil string terjemahan berdasarkan key dan locale code ('en' atau 'id')
  static String tr(String key, String locale) {
    final entry = _translations[key];
    if (entry == null) return key;
    return entry[locale] ?? entry['en'] ?? key;
  }
}
