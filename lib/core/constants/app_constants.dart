/// Konstanta Global Aplikasi SolderLab
/// Asisten Belajar & Kendali Mutu Solder untuk Semua Teknisi Pemula
class AppConstants {
  static const String appName = 'SolderLab';
  static const String appVersion = '1.0.0';
  static const String dbName = 'solderlab.db';
  static const int dbVersion = 4;
  static const String defaultModelVersion = 'Soldy-Net-V6';

  // Status Inspeksi Utama
  static const String statusPass = 'PASS';
  static const String statusFail = 'FAIL';
  static const String statusUncertain = 'UNCERTAIN';

  // Kode Kategori Cacat Sambungan Solder
  static const String defectPass = 'PASS_NORMAL';
  static const String defectD1 = 'D1_BRIDGE';
  static const String defectD2 = 'D2_COLD';
  static const String defectD3 = 'D3_INSUFFICIENT';
  static const String defectD4 = 'D4_EXCESS';
  static const String defectD5 = 'D5_PINHOLE';
  static const String defectNonSolder = 'NON_SOLDER';

  // Ambang Batas Default Quality Assessment
  static const double defaultConfidenceThreshold = 0.50;
  static const double defaultBlurThreshold = 20.0;
  static const double defaultBrightnessMin = 40.0;
  static const double defaultBrightnessMax = 220.0;
  static const int defaultMaxJointsPerScan = 50;
  /// Batas atas titik per foto (papan apa pun, jumlah titik bebas; bisa ditambah/dihapus manual saat review)
  static const int maxJointsPerScan = 200;
  /// Batas atas titik pada pratinjau kamera live (performa)
  static const int maxJointsLivePreview = 60;

  // Board Types
  static const String boardGeneralPcb = 'GENERAL_PCB';
  static const String boardFlipFlopTht = 'FLIP_FLOP_THT';
  static const String boardCustom = 'CUSTOM_BOARD';
  static const String boardHeaderConnector = 'HEADER_CONNECTOR';
  static const String boardIcSocket = 'IC_SOCKET';
  static const String boardSmdMixed = 'SMD_MIXED';

  /// Label tampilan ramah pengguna untuk kode tipe papan
  static String boardLabel(String code) {
    switch (code) {
      case boardGeneralPcb:
        return 'PCB Umum';
      case boardFlipFlopTht:
        return 'Flip-Flop (THT)';
      case boardHeaderConnector:
        return 'Header & Konektor';
      case boardIcSocket:
        return 'Soket IC';
      case boardSmdMixed:
        return 'PCB SMD / Campuran';
      case boardCustom:
        return 'Papan Kustom';
      default:
        return code;
    }
  }
}
