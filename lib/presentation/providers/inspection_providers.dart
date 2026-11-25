import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/defect_type_model.dart';
import '../../data/models/inspection_model.dart';
import '../../data/repositories/inspection_repository.dart';
import '../../services/ai/ai_inference_service.dart';
import '../../services/ai/solder_model_engine.dart';

/// Provider Repository Tunggal
final repositoryProvider = Provider<InspectionRepository>((ref) {
  return InspectionRepository();
});

/// Provider Daftar Taksonomi Cacat Solder
final defectTypesProvider = FutureProvider<List<DefectTypeModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getAllDefectTypes();
});

/// Provider Engine AI Inference
final aiServiceProvider = FutureProvider<AIInferenceService>((ref) async {
  final defectTypes = await ref.watch(defectTypesProvider.future);
  final metadata = await SolderModelMetadata.load();
  final engine = SolderModelEngine(metadata: metadata);
  return AIInferenceService(defectTypes: defectTypes, modelEngine: engine);
});

/// StateFilter untuk Riwayat (Riverpod 3 Notifier)
class HistoryFilterNotifier extends Notifier<String> {
  @override
  String build() => 'ALL';

  void setFilter(String filter) => state = filter;
}

final historyFilterProvider = NotifierProvider<HistoryFilterNotifier, String>(HistoryFilterNotifier.new);

class HistorySearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setSearch(String search) => state = search;
}

final historySearchProvider = NotifierProvider<HistorySearchNotifier, String>(HistorySearchNotifier.new);

/// Provider Daftar Riwayat Inspeksi (Auto Refreshable)
final inspectionsListProvider = FutureProvider<List<InspectionModel>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  final filter = ref.watch(historyFilterProvider);
  final search = ref.watch(historySearchProvider);

  return await repo.getInspections(
    resultFilter: filter,
    searchQuery: search,
  );
});

/// Tren tingkat lolos harian (sparkline dashboard)
final yieldTrendProvider = FutureProvider<List<double>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.getDailyYieldTrend(days: 7);
});

/// Provider Statistik Riwayat Nyata dari SQLite
final statisticsProvider = FutureProvider<QCStatistics>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return await repo.calculateStatistics();
});
