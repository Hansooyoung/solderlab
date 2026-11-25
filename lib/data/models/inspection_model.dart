import '../../core/constants/app_constants.dart';
import 'inspection_joint_model.dart';

/// Model Sesi Inspeksi PCB (Parent Record)
/// Menampung metadata foto, ringkasan kalkulasi hasil, dan rincian titik solder (joints).
class InspectionModel {
  final int? id;
  final String inspectionCode;
  final String inspectedAt;
  final String boardType;
  final int totalJoints;
  final int passCount;
  final int failCount;
  final int uncertainCount;
  final String overallResult; // 'PASS', 'FAIL', 'UNCERTAIN'
  final String imagePath;
  final String modelVersion;
  final int totalInferenceTimeMs;
  final String imageQualityStatus;
  final String? notes;
  final bool manualReviewStatus;
  final bool isRework;
  final int? parentInspectionId;
  final List<InspectionJointModel> joints;

  const InspectionModel({
    this.id,
    required this.inspectionCode,
    required this.inspectedAt,
    required this.boardType,
    required this.totalJoints,
    required this.passCount,
    required this.failCount,
    required this.uncertainCount,
    required this.overallResult,
    required this.imagePath,
    required this.modelVersion,
    required this.totalInferenceTimeMs,
    required this.imageQualityStatus,
    this.notes,
    required this.manualReviewStatus,
    this.isRework = false,
    this.parentInspectionId,
    this.joints = const [],
  });

  bool get isPass => overallResult == 'PASS' || overallResult == 'LULUS';
  bool get isFail => overallResult == 'FAIL' || overallResult == 'REWORK';
  bool get isUncertain => overallResult == 'UNCERTAIN';

  String get overallStatus => isPass ? 'LULUS' : (isFail ? 'REWORK' : 'UNCERTAIN');
  String get boardName => AppConstants.boardLabel(boardType);
  double get yieldRate => passRate;
  DateTime get createdAt => DateTime.tryParse(inspectedAt) ?? DateTime.now();

  double get passRate => totalJoints > 0 ? (passCount / totalJoints) * 100.0 : 0.0;
  double get failRate => totalJoints > 0 ? (failCount / totalJoints) * 100.0 : 0.0;

  factory InspectionModel.fromMap(
    Map<String, dynamic> map, {
    List<InspectionJointModel> joints = const [],
  }) {
    return InspectionModel(
      id: map['id'] as int?,
      inspectionCode: map['inspection_code'] as String,
      inspectedAt: map['inspected_at'] as String,
      boardType: (map['board_type'] as String?) ?? 'GENERAL_PCB',
      totalJoints: map['total_joints'] as int,
      passCount: map['pass_count'] as int,
      failCount: map['fail_count'] as int,
      uncertainCount: map['uncertain_count'] as int,
      overallResult: map['overall_result'] as String,
      imagePath: map['image_path'] as String,
      modelVersion: map['model_version'] as String,
      totalInferenceTimeMs: map['total_inference_time_ms'] as int,
      imageQualityStatus: (map['image_quality_status'] as String?) ?? 'OPTIMAL',
      notes: map['notes'] as String?,
      manualReviewStatus: (map['manual_review_status'] as int) == 1,
      isRework: (map['is_rework'] as int?) == 1,
      parentInspectionId: map['parent_inspection_id'] as int?,
      joints: joints,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'inspection_code': inspectionCode,
      'inspected_at': inspectedAt,
      'board_type': boardType,
      'total_joints': totalJoints,
      'pass_count': passCount,
      'fail_count': failCount,
      'uncertain_count': uncertainCount,
      'overall_result': overallResult,
      'image_path': imagePath,
      'model_version': modelVersion,
      'total_inference_time_ms': totalInferenceTimeMs,
      'image_quality_status': imageQualityStatus,
      'notes': notes,
      'manual_review_status': manualReviewStatus ? 1 : 0,
      'is_rework': isRework ? 1 : 0,
      'parent_inspection_id': parentInspectionId,
    };
    if (id != null) map['id'] = id;
    return map;
  }

  InspectionModel copyWith({
    int? id,
    String? inspectionCode,
    String? inspectedAt,
    String? boardType,
    int? totalJoints,
    int? passCount,
    int? failCount,
    int? uncertainCount,
    String? overallResult,
    String? imagePath,
    String? modelVersion,
    int? totalInferenceTimeMs,
    String? imageQualityStatus,
    String? notes,
    bool? manualReviewStatus,
    bool? isRework,
    int? parentInspectionId,
    List<InspectionJointModel>? joints,
  }) {
    return InspectionModel(
      id: id ?? this.id,
      inspectionCode: inspectionCode ?? this.inspectionCode,
      inspectedAt: inspectedAt ?? this.inspectedAt,
      boardType: boardType ?? this.boardType,
      totalJoints: totalJoints ?? this.totalJoints,
      passCount: passCount ?? this.passCount,
      failCount: failCount ?? this.failCount,
      uncertainCount: uncertainCount ?? this.uncertainCount,
      overallResult: overallResult ?? this.overallResult,
      imagePath: imagePath ?? this.imagePath,
      modelVersion: modelVersion ?? this.modelVersion,
      totalInferenceTimeMs: totalInferenceTimeMs ?? this.totalInferenceTimeMs,
      imageQualityStatus: imageQualityStatus ?? this.imageQualityStatus,
      notes: notes ?? this.notes,
      manualReviewStatus: manualReviewStatus ?? this.manualReviewStatus,
      isRework: isRework ?? this.isRework,
      parentInspectionId: parentInspectionId ?? this.parentInspectionId,
      joints: joints ?? this.joints,
    );
  }
}
