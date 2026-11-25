import '../../core/utils/bounding_box.dart';
import 'defect_type_model.dart';

/// Model Rincian Titik Sambungan Solder (Multi-Solder Joint Item)
class InspectionJointModel {
  final int? id;
  final int? inspectionId;
  final int jointIndex;
  final NormalizedBoundingBox bbox;
  final String result; // 'PASS', 'FAIL', 'UNCERTAIN'
  final int? defectTypeId;
  final double confidence;
  final String? cropImagePath;
  final DefectTypeModel? defectType; // Objek relasi opsional

  const InspectionJointModel({
    this.id,
    this.inspectionId,
    required this.jointIndex,
    required this.bbox,
    required this.result,
    this.defectTypeId,
    required this.confidence,
    this.cropImagePath,
    this.defectType,
  });

  bool get isPass => result == 'PASS';
  bool get isFail => result == 'FAIL';
  bool get isUncertain => result == 'UNCERTAIN';
  String? get defectCode => defectType?.defectCode;

  factory InspectionJointModel.fromMap(Map<String, dynamic> map, {DefectTypeModel? defectType}) {
    return InspectionJointModel(
      id: map['id'] as int?,
      inspectionId: map['inspection_id'] as int?,
      jointIndex: map['joint_index'] as int,
      bbox: NormalizedBoundingBox.fromMap(map),
      result: map['result'] as String,
      defectTypeId: map['defect_type_id'] as int?,
      confidence: (map['confidence'] as num).toDouble(),
      cropImagePath: map['crop_image_path'] as String?,
      defectType: defectType,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'joint_index': jointIndex,
      'result': result,
      'confidence': confidence,
      'crop_image_path': cropImagePath,
      ...bbox.toMap(),
    };
    if (id != null) map['id'] = id;
    if (inspectionId != null) map['inspection_id'] = inspectionId;
    if (defectTypeId != null) map['defect_type_id'] = defectTypeId;
    return map;
  }

  InspectionJointModel copyWith({
    int? id,
    int? inspectionId,
    int? jointIndex,
    NormalizedBoundingBox? bbox,
    String? result,
    int? defectTypeId,
    double? confidence,
    String? cropImagePath,
    DefectTypeModel? defectType,
  }) {
    return InspectionJointModel(
      id: id ?? this.id,
      inspectionId: inspectionId ?? this.inspectionId,
      jointIndex: jointIndex ?? this.jointIndex,
      bbox: bbox ?? this.bbox,
      result: result ?? this.result,
      defectTypeId: defectTypeId ?? this.defectTypeId,
      confidence: confidence ?? this.confidence,
      cropImagePath: cropImagePath ?? this.cropImagePath,
      defectType: defectType ?? this.defectType,
    );
  }
}
