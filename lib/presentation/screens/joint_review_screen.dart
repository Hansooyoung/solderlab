import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bounding_box.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../providers/inspection_providers.dart';
import 'inspection_result_screen.dart';
import '../../core/animations/anim_kit.dart';

/// Layar Konfirmasi & Kalibrasi Titik Sambungan Solder (Interactive Joint Calibration)
class JointReviewScreen extends ConsumerStatefulWidget {
  final String imagePath;
  final List<NormalizedBoundingBox> initialBoxes;
  final bool isRework;
  final int? parentInspectionId;
  final String boardType;

  const JointReviewScreen({
    super.key,
    required this.imagePath,
    required this.initialBoxes,
    this.isRework = false,
    this.parentInspectionId,
    this.boardType = AppConstants.boardGeneralPcb,
  });

  @override
  ConsumerState<JointReviewScreen> createState() => _JointReviewScreenState();
}

class _JointReviewScreenState extends ConsumerState<JointReviewScreen> {
  late List<NormalizedBoundingBox> _boxes;
  late List<bool> _manualFlags;
  bool _isProcessingAI = false;
  int _analyzedCount = 0;
  int _totalAnalyzeCount = 0;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _boxes = List.from(widget.initialBoxes);
    _manualFlags = List<bool>.filled(widget.initialBoxes.length, false, growable: true);
    _resolveImageDimensions();
  }

  void _resolveImageDimensions() {
    try {
      final file = File(widget.imagePath);
      if (!file.existsSync()) return;
      final Image image = Image.file(file);
      image.image.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool _) {
          if (mounted) {
            setState(() {
              _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
            });
          }
        }),
      );
    } catch (_) {}
  }

  Rect _calculateFittedRect(BoxConstraints constraints) {
    if (_imageSize == null || _imageSize!.width <= 0 || _imageSize!.height <= 0) {
      return Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight);
    }
    final double imgAspect = _imageSize!.width / _imageSize!.height;
    final double containerAspect = constraints.maxWidth / constraints.maxHeight;

    double fittedWidth;
    double fittedHeight;
    double offsetX;
    double offsetY;

    if (containerAspect > imgAspect) {
      // Container lebih lebar: penuhi tinggi, letakkan di tengah horizontal
      fittedHeight = constraints.maxHeight;
      fittedWidth = constraints.maxHeight * imgAspect;
      offsetX = (constraints.maxWidth - fittedWidth) / 2.0;
      offsetY = 0.0;
    } else {
      // Container lebih tinggi: penuhi lebar, letakkan di tengah vertikal
      fittedWidth = constraints.maxWidth;
      fittedHeight = constraints.maxWidth / imgAspect;
      offsetX = 0.0;
      offsetY = (constraints.maxHeight - fittedHeight) / 2.0;
    }

    return Rect.fromLTWH(offsetX, offsetY, fittedWidth, fittedHeight);
  }

  void _handleImageTap(TapUpDetails details, BoxConstraints constraints) {
    if (_isProcessingAI) return;

    final fittedRect = _calculateFittedRect(constraints);
    final localPos = details.localPosition;

    // Abaikan klik jika di luar area citra aktual (BoxFit.contain letterbox area)
    if (!fittedRect.contains(localPos)) return;

    final double clickXNorm = ((localPos.dx - fittedRect.left) / fittedRect.width).clamp(0.0, 1.0);
    final double clickYNorm = ((localPos.dy - fittedRect.top) / fittedRect.height).clamp(0.0, 1.0);

    // Cek apakah klik berada di dalam salah satu box yang sudah ada (untuk hapus titik)
    int clickedIndex = -1;
    for (int i = 0; i < _boxes.length; i++) {
      final b = _boxes[i];
      if (clickXNorm >= b.x &&
          clickXNorm <= b.x + b.width &&
          clickYNorm >= b.y &&
          clickYNorm <= b.y + b.height) {
        clickedIndex = i;
        break;
      }
    }

    setState(() {
      if (clickedIndex != -1) {
        // Hapus box jika diketuk kembali
        _boxes.removeAt(clickedIndex);
        if (clickedIndex < _manualFlags.length) {
          _manualFlags.removeAt(clickedIndex);
        }
      } else {
        // Tambahkan box baru berukuran 7.5% x 7.5% centered pada titik sentuh
        const double boxSize = 0.075;
        final double bx = (clickXNorm - boxSize / 2).clamp(0.0, 1.0 - boxSize);
        final double by = (clickYNorm - boxSize / 2).clamp(0.0, 1.0 - boxSize);

        _boxes.add(NormalizedBoundingBox(
          x: bx,
          y: by,
          width: boxSize,
          height: boxSize,
        ));
        _manualFlags.add(true);
      }
    });
  }

  Future<void> _runAIEvaluation() async {
    if (_boxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan minimal 1 titik solder sebelum analisis.'),
          backgroundColor: AppTheme.failRed,
        ),
      );
      return;
    }

    setState(() {
      _analyzedCount = 0;
      _totalAnalyzeCount = _boxes.length;
      _isProcessingAI = true;
    });

    try {
      final aiService = await ref.read(aiServiceProvider.future);
      final repo = ref.read(repositoryProvider);
      final confidence = await repo.getDoubleSetting('confidence_threshold', AppConstants.defaultConfidenceThreshold);
      final blur = await repo.getDoubleSetting('blur_threshold', AppConstants.defaultBlurThreshold);
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();

      final result = await aiService.analyzeMultiJoints(
        imageBytes: bytes,
        originalImagePath: widget.imagePath,
        boardType: widget.boardType,
        boxes: _boxes,
        isRework: widget.isRework,
        parentInspectionId: widget.parentInspectionId,
        confidenceThreshold: confidence,
        blurThreshold: blur,
        manualBoxFlags: _manualFlags,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _analyzedCount = done;
            _totalAnalyzeCount = total;
          });
        },
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        SolderPageRoute(
          builder: (_) => InspectionResultScreen(
            result: result,
            rawImageBytes: bytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingAI = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kesalahan inferensi AI: $e'),
          backgroundColor: AppTheme.failRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Konfirmasi Titik Solder (${_boxes.length} Pad)',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Reset Titik',
            onPressed: _isProcessingAI
                ? null
                : () {
                    setState(() {
                      _boxes = List.from(widget.initialBoxes);
                      _manualFlags = List<bool>.filled(widget.initialBoxes.length, false, growable: true);
                    });
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Status Kalibrasi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                  child: Container(
                    key: ValueKey(_boxes.length),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.softSky,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_boxes.length} PAD',
                      style: const TextStyle(
                        color: AppTheme.slateBlueDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Ketuk titik untuk menghapus, ketuk area solder kosong untuk menambah target.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Area Gambar Interaktif (BoxFit.contain Bebas Distorsi)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fittedRect = _calculateFittedRect(constraints);
                return GestureDetector(
                  onTapUp: (details) => _handleImageTap(details, constraints),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: Colors.black),
                      Center(
                        child: Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                      // Overlay Target Titik Solder (Tepet & Presisi pada Citra Nyata)
                      CustomPaint(
                        painter: _ReviewJointPainter(boxes: _boxes, fittedRect: fittedRect),
                      ),
                      if (_isProcessingAI)
                        Positioned.fill(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const ScanSweep(color: AppTheme.softSky),
                              Container(
                                color: Colors.black.withAlpha(185),
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SoldyAvatarAnimated(
                                        size: 68,
                                        mood: SoldyMood.inspecting,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'SOLDY AI MENGANALISIS SOLDER...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: LinearProgressIndicator(
                                          value: _totalAnalyzeCount > 0 ? _analyzedCount / _totalAnalyzeCount : null,
                                          minHeight: 6,
                                          backgroundColor: Colors.white24,
                                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.softSky),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '$_analyzedCount / $_totalAnalyzeCount Titik Selesai',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Tombol Tindakan Eksekusi
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppTheme.softSkyBorder, width: 1)),
            ),
            child: SafeArea(
              top: false,
              child: PressableScale(
                onTap: _isProcessingAI ? null : _runAIEvaluation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _isProcessingAI ? AppTheme.slateBlue.withValues(alpha: 0.5) : AppTheme.slateBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Mulai Evaluasi Mutu (${_boxes.length} Titik) →',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewJointPainter extends CustomPainter {
  final List<NormalizedBoundingBox> boxes;
  final Rect fittedRect;

  _ReviewJointPainter({required this.boxes, required this.fittedRect});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      final rect = Rect.fromLTWH(
        fittedRect.left + b.x * fittedRect.width,
        fittedRect.top + b.y * fittedRect.height,
        b.width * fittedRect.width,
        b.height * fittedRect.height,
      );

      final center = Offset(rect.center.dx, rect.center.dy);
      final radius = rect.width / 2;

      // Lingkaran target reticle
      final ringPaint = Paint()
        ..color = const Color(0xFF38BDF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, ringPaint);

      // Label nomor titik
      final textSpan = TextSpan(
        text: '#${i + 1}',
        style: const TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRect = Rect.fromLTWH(
        rect.left,
        rect.top - 14,
        textPainter.width + 6,
        13,
      );

      final bgPaint = Paint()..color = const Color(0xFF38BDF8);
      canvas.drawRect(badgeRect, bgPaint);
      textPainter.paint(canvas, Offset(rect.left + 3, rect.top - 13));
    }
  }

  @override
  bool shouldRepaint(covariant _ReviewJointPainter oldDelegate) {
    return oldDelegate.boxes != boxes || oldDelegate.fittedRect != fittedRect;
  }
}
