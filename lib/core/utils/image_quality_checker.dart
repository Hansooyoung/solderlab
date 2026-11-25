import 'dart:math';
import 'package:image/image.dart' as img;

/// Hasil Evaluasi Kualitas Citra (Image Quality Assessment)
class ImageQualityResult {
  final bool isAcceptable;
  final double blurScore; // Varians Laplacian / Gradient
  final double brightnessScore; // Rata-rata luminansi [0.0 - 255.0]
  final String status; // 'OPTIMAL', 'BLUR', 'TOO_DARK', 'TOO_BRIGHT'
  final String message;

  const ImageQualityResult({
    required this.isAcceptable,
    required this.blurScore,
    required this.brightnessScore,
    required this.status,
    required this.message,
  });
}

/// Utilitas Penilaian Kualitas Citra Solder
class ImageQualityChecker {
  /// Evaluasi citra dari buffer memori byte gambar
  static ImageQualityResult evaluateImage(
    img.Image image, {
    double blurThreshold = 20.0,
    double minBrightness = 40.0,
    double maxBrightness = 225.0,
  }) {
    // 1. Hitung Luminansi Rata-rata (Kecerahan)
    double totalLuminance = 0;
    final int sampleStep = max(1, (image.width * image.height) ~/ 10000); // sampling untuk kecepatan
    int samplesCount = 0;

    for (int y = 0; y < image.height; y += sampleStep) {
      for (int x = 0; x < image.width; x += sampleStep) {
        final pixel = image.getPixel(x, y);
        // Standard Rec. 709 luma: Y = 0.2126 R + 0.7152 G + 0.0722 B
        final luma = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
        totalLuminance += luma;
        samplesCount++;
      }
    }

    final double meanBrightness = samplesCount > 0 ? (totalLuminance / samplesCount) : 128.0;

    // 2. Cek Kecerahan Ekstrem
    if (meanBrightness < minBrightness) {
      return ImageQualityResult(
        isAcceptable: false,
        blurScore: 0,
        brightnessScore: meanBrightness,
        status: 'TOO_DARK',
        message: 'Pencahayaan terlalu gelap (${meanBrightness.toStringAsFixed(1)} < $minBrightness). Aktifkan lampu/flash.',
      );
    }

    if (meanBrightness > maxBrightness) {
      return ImageQualityResult(
        isAcceptable: false,
        blurScore: 0,
        brightnessScore: meanBrightness,
        status: 'TOO_BRIGHT',
        message: 'Silau berlebih pada timah (${meanBrightness.toStringAsFixed(1)} > $maxBrightness). Kurangi pantulan lampu langsung.',
      );
    }

    // 3. Hitung Varians Ketajaman (Aproksimasi Laplacian Variance pada sampel tengah)
    final double sharpnessScore = _estimateSharpness(image);

    if (sharpnessScore < blurThreshold) {
      return ImageQualityResult(
        isAcceptable: false,
        blurScore: sharpnessScore,
        brightnessScore: meanBrightness,
        status: 'BLUR',
        message: 'Foto buram / tidak fokus (${sharpnessScore.toStringAsFixed(1)} < $blurThreshold). Tahan posisi kamera dengan stabil.',
      );
    }

    return ImageQualityResult(
      isAcceptable: true,
      blurScore: sharpnessScore,
      brightnessScore: meanBrightness,
      status: 'OPTIMAL',
      message: 'Kualitas citra optimal untuk analisis solder.',
    );
  }

  /// Estimasi ketajaman menggunakan selisih gradien lokal (fast mobile approximation)
  static double _estimateSharpness(img.Image image) {
    double sumGrad = 0;
    double sumSqGrad = 0;
    int count = 0;

    // Ambil area tengah (center 60% ROI) untuk evaluasi fokus
    final startX = (image.width * 0.2).toInt();
    final endX = (image.width * 0.8).toInt();
    final startY = (image.height * 0.2).toInt();
    final endY = (image.height * 0.8).toInt();
    final step = max(2, (endX - startX) ~/ 120);

    for (int y = startY; y < endY - 1; y += step) {
      for (int x = startX; x < endX - 1; x += step) {
        final p0 = image.getPixel(x, y).luminanceNormalized;
        final pRight = image.getPixel(x + 1, y).luminanceNormalized;
        final pBottom = image.getPixel(x, y + 1).luminanceNormalized;

        final double dx = (pRight - p0) * 255.0;
        final double dy = (pBottom - p0) * 255.0;
        final double grad = sqrt(dx * dx + dy * dy);

        sumGrad += grad;
        sumSqGrad += grad * grad;
        count++;
      }
    }

    if (count <= 1) return 100.0;
    final double mean = sumGrad / count;
    final double variance = (sumSqGrad / count) - (mean * mean);
    return max(0.0, variance);
  }
}
