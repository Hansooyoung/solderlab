import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'dashboard_screen.dart';
import 'ipc_standard_screen.dart';
import 'statistics_screen.dart';
import 'history_screen.dart';
import 'workstation_setup_screen.dart';
import 'settings_screen.dart';
import '../../core/animations/anim_kit.dart';

/// MainNavigationScaffold: Kerangka Navigasi Utama SolderLab
/// Menampilkan Floating Capsule Dock (#52738D) dengan 5 Navigasi Intuitif
class MainNavigationScaffold extends StatefulWidget {
  final int initialIndex;
  const MainNavigationScaffold({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScaffold> createState() => _MainNavigationScaffoldState();
}

class _MainNavigationScaffoldState extends State<MainNavigationScaffold> {
  late int _currentIndex;

  final List<Widget> _tabs = const [
    DashboardScreen(),
    IpcStandardScreen(),
    StatisticsScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openCameraFlow() {
    Navigator.push(
      context,
      SolderPageRoute(builder: (_) => const WorkstationSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.warmEggshell,
      appBar: AppBar(
        backgroundColor: AppTheme.warmEggshell,
        elevation: 0,
        titleSpacing: 20,
        title: const AppLogo(size: 32, showText: true, fontSize: 17),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.softSkyBorder),
              ),
              child: const Icon(Icons.settings_outlined, color: AppTheme.slateBlue, size: 18),
            ),
            onPressed: () {
              Navigator.push(
                context,
                SolderPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: Stack(
        children: [
          // Konten Layar Aktif
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<int>(_currentIndex),
              child: _tabs[_currentIndex],
            ),
          ),

          // Floating Capsule Dock Pinned di Bagian Bawah
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: _buildFloatingCapsuleDock(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingCapsuleDock() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.slateBlue,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3D283F52),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Beranda
          _buildDockItem(
            icon: Icons.home_rounded,
            label: 'Beranda',
            isSelected: _currentIndex == 0,
            onTap: () => _onTabSelected(0),
          ),

          // 2. Kamus Standar Solder
          _buildDockItem(
            icon: Icons.menu_book_rounded,
            label: 'Kamus',
            isSelected: _currentIndex == 1,
            onTap: () => _onTabSelected(1),
          ),

          // 3. Tombol Kamera Tengah (denyut lembut + umpan balik sentuh)
          PressableScale(
            onTap: _openCameraFlow,
            pressedScale: 0.9,
            child: PulseGlow(
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.softSky, width: 2.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.slateBlue,
                  size: 26,
                ),
              ),
            ),
          ),

          // 4. Statistik Mutu
          _buildDockItem(
            icon: Icons.bar_chart_rounded,
            label: 'Statistik',
            isSelected: _currentIndex == 2,
            onTap: () => _onTabSelected(2),
          ),

          // 5. Riwayat Inspeksi
          _buildDockItem(
            icon: Icons.history_rounded,
            label: 'Riwayat',
            isSelected: _currentIndex == 3,
            onTap: () => _onTabSelected(3),
          ),
        ],
      ),
    );
  }

  Widget _buildDockItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: PressableScale(
        onTap: onTap,
        pressedScale: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.white.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isSelected ? 1.18 : 1.0,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    icon,
                    size: 22,
                    color: isSelected ? Colors.white : const Color(0xFFA8CCE8),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFFA8CCE8),
                  ),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
