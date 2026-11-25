import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/bounding_box.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../../services/ai/ai_inference_service.dart';
import '../../services/ai/solder_localizer_service.dart';
import '../providers/inspection_providers.dart';
import '../widgets/bounding_box_overlay.dart';
import 'joint_review_screen.dart';
import '../../core/animations/anim_kit.dart';

/// Halaman Pemindaian Kamera Cerdas dengan Pre-Capture Environmental Diagnostics
class CameraScanScreen extends ConsumerStatefulWidget {
  final bool isRework;
  final int? parentInspectionId;
  final String boardType;

  const CameraScanScreen({
    super.key,
    this.isRework = false,
    this.parentInspectionId,
    this.boardType = AppConstants.boardGeneralPcb,
  });

  @override
  ConsumerState<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends ConsumerState<CameraScanScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isFlashOn = false;
  double _currentZoomLevel = 1.0;
  double _maxZoomLevel = 5.0;

  // Mode Pemindaian: Multi-Joint (default) atau Single-Joint Macro
  bool _isMultiJointMode = true;

  // Status Diagnostik Pre-Capture (Lighting, Focus, Solder Detection)
  String _lightStatus = 'OPTIMAL'; // 'OPTIMAL', 'DARK', 'GLARE'
  String _focusStatus = 'SHARP'; // 'SHARP', 'BLUR'
  int _detectedJointsCount = 0;

  // Daftar Bounding Box panduan/deteksi pada preview
  List<NormalizedBoundingBox> _activeBoxes = [];
  bool _isProcessingLiveFrame = false;
  DateTime _lastFrameTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_cameraController?.value.isStreamingImages ?? false) {
      try {
        _cameraController?.stopImageStream();
      } catch (_) {}
    }
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Jaminan Tidak Berjalan di Latar Belakang & Safe Disposal Guard:
    // Saat aplikasi diminimalkan atau berpindah layar, hentikan stream dan nullify controller
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_cameraController != null) {
        if (_cameraController!.value.isStreamingImages) {
          try {
            _cameraController!.stopImageStream();
          } catch (_) {}
        }
        _cameraController!.dispose();
        _cameraController = null;
        if (mounted) {
          setState(() {
            _isCameraInitialized = false;
          });
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null || !_isCameraInitialized) {
        _initCamera();
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _showErrorDialog('Kamera Tidak Ditemukan', 'Tidak ada perangkat kamera yang terdeteksi.');
        return;
      }

      final backCamera = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
        _maxZoomLevel = await _cameraController!.getMaxZoomLevel();
        await _cameraController!.setFlashMode(FlashMode.off);
        _isFlashOn = false;
      } catch (_) {}

      _setupDefaultBoxes();
      _startLiveStreamDetection();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      _showErrorDialog('Inisialisasi Kamera Gagal', '$e');
    }
  }

  void _startLiveStreamDetection() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isStreamingImages) return;
      controller.startImageStream((CameraImage image) {
        if (!mounted || !_isMultiJointMode || _isProcessing) return;
        final now = DateTime.now();
        if (_isProcessingLiveFrame || now.difference(_lastFrameTime).inMilliseconds < 250) {
          return;
        }
        _isProcessingLiveFrame = true;
        _lastFrameTime = now;

        try {
          if (image.planes.isNotEmpty) {
            final plane = image.planes.first;
            final liveResult = SolderLocalizerService.analyzeLiveLuminanceFrame(
              yPlaneBytes: plane.bytes,
              width: image.width,
              height: image.height,
              bytesPerRow: plane.bytesPerRow,
              maxJoints: AppConstants.maxJointsLivePreview,
            );

            if (mounted && !_isProcessing) {
              setState(() {
                _activeBoxes = liveResult.boxes;
                _detectedJointsCount = liveResult.boxes.length;
                _lightStatus = liveResult.lightStatus;
                _focusStatus = liveResult.focusStatus;
              });
            }
          }
        } catch (_) {
        } finally {
          _isProcessingLiveFrame = false;
        }
      });
    } catch (_) {}
  }

  Future<void> _stopLiveStreamDetection() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }

  void _setupDefaultBoxes() {
    if (_isMultiJointMode) {
      _activeBoxes = [];
      _detectedJointsCount = 0;
    } else {
      _activeBoxes = const [
        NormalizedBoundingBox(x: 0.30, y: 0.35, width: 0.40, height: 0.30),
      ];
      _detectedJointsCount = 1;
    }
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      _isFlashOn = !_isFlashOn;
      await _cameraController!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _setZoom(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final target = zoom.clamp(1.0, _maxZoomLevel);
      await _cameraController!.setZoomLevel(target);
      setState(() {
        _currentZoomLevel = target;
      });
    } catch (_) {}
  }

  Future<void> _captureAndAnalyze() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    HapticFeedback.mediumImpact();

    try {
      // 0. Hentikan image stream agar perangkat kamera siap memotret resolusi tinggi tanpa tabrakan buffer
      await _stopLiveStreamDetection();

      // 1. Ambil Foto Resolusi Tinggi
      final XFile photoFile = await _cameraController!.takePicture();
      final bytes = await File(photoFile.path).readAsBytes();

      final blurThreshold = await ref.read(repositoryProvider).getDoubleSetting(
            'blur_threshold',
            AppConstants.defaultBlurThreshold,
          );
      final appDir = await getApplicationDocumentsDirectory();
      final stagingDirPath = '${appDir.path}/qc_staging';
      final aiMeta = ref.read(aiServiceProvider).value?.modelEngine.metadata;

      // 2. Decode, Cek Kualitas & Deteksi Titik Solder di Background Isolate (Nol UI Freeze)
      final precheck = await AIInferenceService.precheckAndDetectCapture(
        rawBytes: bytes,
        stagingDirPath: stagingDirPath,
        blurThreshold: blurThreshold,
        metadata: aiMeta,
      );

      if (!precheck.isQualityPass) {
        final msgLower = precheck.qualityMessage.toLowerCase();
        final bool isTooDark = msgLower.contains('gelap') || msgLower.contains('dark');
        final bool isBlurry = msgLower.contains('buram') || msgLower.contains('blur');
        final bool isGlare = msgLower.contains('silau') || msgLower.contains('bright');

        if (mounted) {
          setState(() {
            _lightStatus = isTooDark ? 'DARK' : (isGlare ? 'GLARE' : 'OPTIMAL');
            _focusStatus = isBlurry ? 'BLUR' : 'SHARP';
          });
        }

        if (mounted) {
          _showQualityWarningDialog(
            precheck.qualityMessage,
            isDark: isTooDark,
            isBlur: isBlurry,
            isNoSolder: false,
          );
        }
        _startLiveStreamDetection();
        return;
      }

      // 3. Multi-Joint Targets (atau single ROI)
      List<NormalizedBoundingBox> targetBoxes = _isMultiJointMode
          ? precheck.detectedBoxes
          : const [NormalizedBoundingBox(x: 0.30, y: 0.35, width: 0.40, height: 0.30)];

      if (targetBoxes.isEmpty) {
        if (mounted) {
          final filteredMsg = precheck.filteredNonSolderCount > 0
              ? 'Soldy AI menyaring ${precheck.filteredNonSolderCount} kaki komponen / objek non-solder dan tidak menemukan titik timah yang siap periksa. Arahkan kamera lebih dekat ke sambungan timah pada PCB.'
              : ref.tr('statusNoSolder');
          _showQualityWarningDialog(
            filteredMsg,
            isDark: false,
            isBlur: false,
            isNoSolder: true,
          );
        }
        _startLiveStreamDetection();
        return;
      }

      setState(() {
        _detectedJointsCount = targetBoxes.length;
        _lightStatus = 'OPTIMAL';
        _focusStatus = 'SHARP';
      });

      // 4. Navigasi ke Layar Konfirmasi menggunakan gambar 1600px teroptimasi
      if (!mounted) return;
      await Navigator.push(
        context,
        SolderPageRoute(
          builder: (_) => JointReviewScreen(
            imagePath: precheck.optimizedImagePath ?? photoFile.path,
            initialBoxes: targetBoxes,
            isRework: widget.isRework,
            parentInspectionId: widget.parentInspectionId,
            boardType: widget.boardType,
          ),
        ),
      );

      // Mulai ulang live stream deteksi saat kembali ke layar viewfinder kamera
      if (mounted) {
        _startLiveStreamDetection();
      }
    } catch (e) {
      _showErrorDialog('Analisis Gagal', '$e');
      if (mounted) {
        _startLiveStreamDetection();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showQualityWarningDialog(String message, {required bool isDark, required bool isBlur, required bool isNoSolder}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: Row(
          children: [
            Icon(
              isDark ? Icons.brightness_low : (isBlur ? Icons.blur_on : Icons.warning_amber_rounded),
              color: AppTheme.uncertainYellow,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(ref.tr('retakeNeeded'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.4),
            ),
            if (isDark) ...[
              const SizedBox(height: 12),
              const Text(
                'Saran: Tekan tombol petir di pojok kanan atas untuk mengaktifkan lampu flash.',
                style: TextStyle(color: AppTheme.accentBlue, fontSize: 11),
              ),
            ],
            if (isBlur) ...[
              const SizedBox(height: 12),
              const Text(
                'Saran: Tahan smartphone dengan kedua tangan dan jaga jarak lensa sekitar 7-10 cm.',
                style: TextStyle(color: AppTheme.accentBlue, fontSize: 11),
              ),
            ],
            if (isNoSolder) ...[
              const SizedBox(height: 12),
              const Text(
                'Saran: Arahkan lensa kamera tegak lurus pada sisi bawah PCB tempat kaki komponen disolder.',
                style: TextStyle(color: AppTheme.accentBlue, fontSize: 11),
              ),
            ],
          ],
        ),
        actions: [
          if (isDark && !_isFlashOn)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _toggleFlash();
              },
              child: const Text('NYALAKAN FLASH'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ref.tr('retakeButton')),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: Text(title, style: const TextStyle(color: AppTheme.failRed)),
        content: Text(message, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isMultiJointMode ? ref.tr('multiJointMode') : ref.tr('singleMacroMode'),
              style: const TextStyle(fontSize: 16),
            ),
            if (widget.isRework)
              Text(
                'FOTO ULANG REWORK • INDUK #${widget.parentInspectionId ?? "-"}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            color: _isFlashOn ? Colors.yellow : Colors.white,
            tooltip: 'Flash',
            onPressed: _toggleFlash,
          ),
          IconButton(
            icon: Icon(_isMultiJointMode ? Icons.grid_view : Icons.crop_free),
            tooltip: _isMultiJointMode ? 'Multi-Solder' : 'Macro Mode',
            onPressed: () {
              setState(() {
                _isMultiJointMode = !_isMultiJointMode;
                _setupDefaultBoxes();
              });
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Live Camera Preview
          if (_isCameraInitialized && _cameraController != null)
            CameraPreview(_cameraController!)
          else
            const Center(child: CircularProgressIndicator(color: AppTheme.accentBlue)),

          // 2. Overlay Bounding Box Panduan
          if (_isCameraInitialized)
            BoundingBoxOverlay(
              boxes: _activeBoxes,
            ),

          // 3. Status Bar Diagnostik Pre-Capture (Lighting, Focus, Target)
          Positioned(
            top: 12,
            left: 14,
            right: 14,
            child: Column(
              children: [
                // Sensor Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(200),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatusIndicator(
                        icon: Icons.light_mode,
                        label: _lightStatus == 'OPTIMAL' ? 'Cahaya: OK' : (_lightStatus == 'DARK' ? 'Gelap' : 'Silau'),
                        color: _lightStatus == 'OPTIMAL' ? AppTheme.passGreen : AppTheme.failRed,
                      ),
                      Container(width: 1, height: 16, color: AppTheme.darkBorder),
                      _buildStatusIndicator(
                        icon: Icons.center_focus_strong,
                        label: _focusStatus == 'SHARP' ? 'Fokus: Tajam' : 'Buram',
                        color: _focusStatus == 'SHARP' ? AppTheme.passGreen : AppTheme.uncertainYellow,
                      ),
                      Container(width: 1, height: 16, color: AppTheme.darkBorder),
                      _buildStatusIndicator(
                        icon: Icons.grain,
                        label: '$_detectedJointsCount Solder Pad',
                        color: AppTheme.accentBlue,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Panduan Instruksi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isMultiJointMode ? ref.tr('multiInstruction') : ref.tr('macroInstruction'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          // 4. Zoom Controls di Samping Kanan
          Positioned(
            right: 14,
            bottom: 120,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, size: 18, color: Colors.white),
                    onPressed: () => _setZoom(_currentZoomLevel + 0.5),
                  ),
                  Text(
                    '${_currentZoomLevel.toStringAsFixed(1)}x',
                    style: const TextStyle(fontSize: 10, color: AppTheme.accentBlue, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18, color: Colors.white),
                    onPressed: () => _setZoom(_currentZoomLevel - 0.5),
                  ),
                ],
              ),
            ),
          ),

          // 5. Loading Overlay saat Inferensi
          if (_isProcessing)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ScanSweep(color: AppTheme.accentBlue),
                  Container(
                    color: Colors.black.withAlpha(185),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SoldyAvatarAnimated(size: 72, mood: SoldyMood.inspecting),
                          const SizedBox(height: 12),
                          Text(
                            ref.tr('analyzingJoints'),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 6. Tombol Shutter di Bagian Bawah
          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PressableScale(
                  onTap: _isProcessing ? null : _captureAndAnalyze,
                  pressedScale: 0.90,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isProcessing ? Colors.grey : AppTheme.accentBlue,
                      boxShadow: _isProcessing
                          ? const []
                          : [
                              BoxShadow(
                                color: AppTheme.accentBlue.withValues(alpha: 0.4),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Color(0xFF001E36),
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator({required IconData icon, required String label, required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}
