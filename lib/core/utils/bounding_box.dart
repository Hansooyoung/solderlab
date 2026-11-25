import 'dart:ui';

/// Model Bounding Box normalisasi (0.0 s.d. 1.0) untuk titik sambungan solder
class NormalizedBoundingBox {
  final double x; // x min [0.0 - 1.0]
  final double y; // y min [0.0 - 1.0]
  final double width; // lebar normalisasi
  final double height; // tinggi normalisasi

  const NormalizedBoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// Konversi ke koordinat piksel aktual berdasarkan ukuran canvas/gambar
  Rect toPixelRect(Size imageSize) {
    return Rect.fromLTWH(
      x * imageSize.width,
      y * imageSize.height,
      width * imageSize.width,
      height * imageSize.height,
    );
  }

  /// Buat Bounding Box dari Rect piksel dan ukuran gambar
  factory NormalizedBoundingBox.fromPixelRect(Rect rect, Size imageSize) {
    return NormalizedBoundingBox(
      x: (rect.left / imageSize.width).clamp(0.0, 1.0),
      y: (rect.top / imageSize.height).clamp(0.0, 1.0),
      width: (rect.width / imageSize.width).clamp(0.0, 1.0),
      height: (rect.height / imageSize.height).clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bbox_x': x,
      'bbox_y': y,
      'bbox_w': width,
      'bbox_h': height,
    };
  }

  factory NormalizedBoundingBox.fromMap(Map<String, dynamic> map) {
    return NormalizedBoundingBox(
      x: (map['bbox_x'] as num).toDouble(),
      y: (map['bbox_y'] as num).toDouble(),
      width: (map['bbox_w'] as num).toDouble(),
      height: (map['bbox_h'] as num).toDouble(),
    );
  }

  /// Menghitung Intersection over Union (IoU) untuk eliminasi duplikasi / NMS
  double calculateIoU(NormalizedBoundingBox other) {
    final double left = x > other.x ? x : other.x;
    final double top = y > other.y ? y : other.y;
    final double right = (x + width) < (other.x + other.width) ? (x + width) : (other.x + other.width);
    final double bottom = (y + height) < (other.y + other.height) ? (y + height) : (other.y + other.height);

    if (right < left || bottom < top) return 0.0;

    final double intersection = (right - left) * (bottom - top);
    final double unionArea = (width * height) + (other.width * other.height) - intersection;

    if (unionArea <= 0.0) return 0.0;
    return intersection / unionArea;
  }
}
