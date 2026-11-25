import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../features/shared/widgets/soldy_avatar_animated.dart';
import '../providers/inspection_providers.dart';

/// SettingsScreen: Layar Pengaturan & Profil SolderLab
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _confidenceThreshold = AppConstants.defaultConfidenceThreshold;
  double _blurThreshold = AppConstants.defaultBlurThreshold;
  String _operatorName = 'Teknisi QC';
  int _stagingFileCount = 0;
  double _stagingSizeMb = 0.0;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _measureStagingCache();
  }

  Future<void> _measureStagingCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stagingDir = Directory('${dir.path}/qc_staging');
      if (!await stagingDir.exists()) {
        if (mounted) {
          setState(() {
            _stagingFileCount = 0;
            _stagingSizeMb = 0.0;
          });
        }
        return;
      }
      int count = 0;
      int totalBytes = 0;
      await for (final entity in stagingDir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          count++;
          totalBytes += await entity.length();
        }
      }
      if (mounted) {
        setState(() {
          _stagingFileCount = count;
          _stagingSizeMb = totalBytes / (1024.0 * 1024.0);
        });
      }
    } catch (_) {}
  }

  Future<void> _clearStagingCache() async {
    if (_isClearingCache) return;
    setState(() => _isClearingCache = true);
    int clearedCount = 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stagingDir = Directory('${dir.path}/qc_staging');
      if (await stagingDir.exists()) {
        await for (final entity in stagingDir.list(followLinks: false)) {
          if (entity is File) {
            await entity.delete();
            clearedCount++;
          }
        }
      }
    } catch (_) {}
    await _measureStagingCache();
    if (mounted) {
      setState(() => _isClearingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            clearedCount > 0
                ? 'Membersihkan $clearedCount berkas sementara dari penyimpanan lokal.'
                : 'Penyimpanan staging sudah bersih.',
          ),
          backgroundColor: AppTheme.slateBlue,
        ),
      );
    }
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(repositoryProvider);
    final conf = await repo.getDoubleSetting('confidence_threshold', AppConstants.defaultConfidenceThreshold);
    final blur = await repo.getDoubleSetting('blur_threshold', AppConstants.defaultBlurThreshold);
    final opName = await repo.getStringSetting('operator_name', 'Teknisi QC');
    if (!mounted) return;
    setState(() {
      _confidenceThreshold = conf.clamp(0.20, 0.95);
      _blurThreshold = blur.clamp(10.0, 50.0);
      _operatorName = opName;
    });
  }

  Future<void> _editOperatorName() async {
    final controller = TextEditingController(text: _operatorName);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Nama Operator / Workstation',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.slateBlueDark),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Mis. Meja Perakitan 01',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.slateBlue, foregroundColor: Colors.white),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved != null && saved.isNotEmpty) {
      await ref.read(repositoryProvider).setSetting('operator_name', saved);
      if (mounted) setState(() => _operatorName = saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLocale = ref.watch(localeProvider);
    final aiAsync = ref.watch(aiServiceProvider);
    final modelName = aiAsync.value?.modelEngine.metadata.modelName ?? AppConstants.defaultModelVersion;
    final initials = _operatorName
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      appBar: AppBar(
        backgroundColor: AppTheme.warmEggshell,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.slateBlue),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Pengaturan & Profil',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.slateBlueDark,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: [
                  // 1. Profil Workstation & Model AI Aktif
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.softSky,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.softSkyBorder, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            initials.isEmpty ? 'QC' : initials,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.slateBlueDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _operatorName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slateBlueDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Workstation QC Solder PCB (Offline)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Engine: $modelName',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.slateBlue),
                          tooltip: 'Ubah Nama Workstation',
                          onPressed: _editOperatorName,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Pengaturan Bahasa
                  const Text(
                    'PENGATURAN BAHASA',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlue,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      children: [
                        _buildRadioTile(
                          title: 'Bahasa Indonesia (Aktif)',
                          subtitle: 'Format resmi istilah teknis dan panduan IPC',
                          isSelected: currentLocale == 'id',
                          onTap: () => ref.read(localeProvider.notifier).setLocale('id'),
                        ),
                        const Divider(height: 1),
                        _buildRadioTile(
                          title: 'English',
                          subtitle: 'International Technical Standard format',
                          isSelected: currentLocale == 'en',
                          onTap: () => ref.read(localeProvider.notifier).setLocale('en'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Parameter Mesin AI
                  const Text(
                    'PARAMETER DETEKSI AI ON-DEVICE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlue,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Ambang Keyakinan (Confidence)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                            ),
                            Text(
                              '${(_confidenceThreshold * 100).toInt()}%',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slateBlue),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.slateBlue,
                            thumbColor: AppTheme.slateBlue,
                            inactiveTrackColor: AppTheme.softSky,
                          ),
                          child: Slider(
                            value: _confidenceThreshold,
                            min: 0.20,
                            max: 0.95,
                            divisions: 15,
                            onChanged: (val) => setState(() => _confidenceThreshold = val),
                            onChangeEnd: (val) => ref.read(repositoryProvider).setSetting('confidence_threshold', val.toStringAsFixed(2)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Ambang Ketajaman (Laplacian Blur)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                            ),
                            Text(
                              _blurThreshold.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.slateBlue),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.slateBlue,
                            thumbColor: AppTheme.slateBlue,
                            inactiveTrackColor: AppTheme.softSky,
                          ),
                          child: Slider(
                            value: _blurThreshold,
                            min: 10.0,
                            max: 50.0,
                            divisions: 8,
                            onChanged: (val) => setState(() => _blurThreshold = val),
                            onChangeEnd: (val) => ref.read(repositoryProvider).setSetting('blur_threshold', val.toStringAsFixed(1)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Penyimpanan Staging & Diagnostik
                  const Text(
                    'PENYIMPANAN & CACHE LOKAL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlue,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppTheme.cardDecoration(),
                    child: Row(
                      children: [
                        SoldyAvatarAnimated(
                          size: 44,
                          mood: _stagingFileCount > 40 ? SoldyMood.warning : SoldyMood.happy,
                          onTap: _measureStagingCache,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cache Berkas Staging ($_stagingFileCount item)',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.slateBlueDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Terpakai ${_stagingSizeMb.toStringAsFixed(2)} MB di perangkat lokal',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _isClearingCache ? null : _clearStagingCache,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.slateBlue,
                            side: const BorderSide(color: AppTheme.softSkyBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            _isClearingCache ? 'Proses...' : 'Bersihkan',
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Izin Akses Perangkat
                  const Text(
                    'IZIN AKSES PERANGKAT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlue,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      children: [
                        _buildPermissionItem(
                          icon: Icons.camera_alt_outlined,
                          title: 'Kamera Optik Makro',
                          status: 'Diizinkan',
                        ),
                        const Divider(height: 1),
                        _buildPermissionItem(
                          icon: Icons.folder_outlined,
                          title: 'Penyimpanan & SQLite',
                          status: 'Diizinkan',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Footer Pinned di Bawah Sesuai Permintaan User
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTheme.softSkyBorder, width: 1)),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SolderLab v1.0 • Build 2026.11',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.slateBlueDark,
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sistem Kendali Mutu Solder Elektronika On-Device',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: isSelected ? AppTheme.slateBlue : AppTheme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required String title,
    required String status,
  }) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.slateBlue, size: 20),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.softSky,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.softSkyBorder),
            ),
            child: Text(
              status,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.slateBlueDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
