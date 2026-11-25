/// Model Taksonomi Cacat Sambungan Solder
class DefectTypeModel {
  final int id;
  final String defectCode;
  final String defectName;
  final String description;
  final String category;
  final String qualityStatus; // 'PASS' atau 'FAIL'

  const DefectTypeModel({
    required this.id,
    required this.defectCode,
    required this.defectName,
    required this.description,
    required this.category,
    required this.qualityStatus,
  });

  bool get isPass => qualityStatus == 'PASS';

  factory DefectTypeModel.fromMap(Map<String, dynamic> map) {
    return DefectTypeModel(
      id: map['id'] as int,
      defectCode: map['defect_code'] as String,
      defectName: map['defect_name'] as String,
      description: map['description'] as String,
      category: map['category'] as String,
      qualityStatus: map['quality_status'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'defect_code': defectCode,
      'defect_name': defectName,
      'description': description,
      'category': category,
      'quality_status': qualityStatus,
    };
  }
}
