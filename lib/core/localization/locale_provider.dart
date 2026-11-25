import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/inspection_providers.dart';
import 'app_strings.dart';

/// Provider Kode Bahasa Aktif ('id' = Bahasa Indonesia default, 'en' = English), dipersist di SQLite.
class LocaleNotifier extends Notifier<String> {
  static const String _settingKey = 'app_locale';
  bool _loaded = false;

  @override
  String build() {
    if (!_loaded) {
      _loaded = true;
      Future.microtask(_loadPersistedLocale);
    }
    return 'id';
  }

  Future<void> _loadPersistedLocale() async {
    try {
      final saved = await ref.read(repositoryProvider).getStringSetting(_settingKey, 'id');
      if (saved == 'en' || saved == 'id') {
        state = saved;
      }
    } catch (_) {
      // Abaikan jika dipanggil sebelum DB inisialisasi pada pengujian unit terisolasi
    }
  }

  void setLocale(String code) {
    if (code == 'en' || code == 'id') {
      state = code;
      ref.read(repositoryProvider).setSetting(_settingKey, code).catchError((_) {});
    }
  }

  void toggleLocale() {
    final next = (state == 'en') ? 'id' : 'en';
    setLocale(next);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);

/// Extension helper pada WidgetRef untuk terjemahan singkat.
extension LocalizationHelper on WidgetRef {
  String tr(String key) {
    final locale = watch(localeProvider);
    return AppStrings.tr(key, locale);
  }
}
