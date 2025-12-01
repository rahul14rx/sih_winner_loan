// lib/models/process_step.dart

class ProcessStep {
  final String id;
  final int processId;

  final String? whatToDo;
  final String? dataType;
  final String? fileId;
  final String? mediaUrl;
  final String? status;

  double? utilizationAmount;
  String? officerComment;

  final String? docsAsset;
  final String? docsImage;

  ProcessStep({
    required this.id,
    required this.processId,
    this.whatToDo,
    this.dataType,
    this.fileId,
    this.mediaUrl,
    this.status,
    this.utilizationAmount,
    this.officerComment,
    this.docsAsset,
    this.docsImage,
  });

  factory ProcessStep.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic x) {
      if (x == null) return null;
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x);
      return null;
    }

    return ProcessStep(
      id: json['id']?.toString() ?? '',
      processId: int.tryParse(json['process_id']?.toString() ?? '0') ?? 0,

      whatToDo: json['what_to_do'] ?? json['whatToDo'] ?? json['what_to_do'],

      dataType: json['data_type'] ?? json['dataType'],

      fileId: json['file_id']?.toString(),
      mediaUrl: json['media_url']?.toString(),

      status: json['status']?.toString(),

      utilizationAmount: parseDouble(
          json['utilization_amount'] ??
              json['utilizationAmount']
      ),

      officerComment: json['officer_comment'] ?? json['officerComment'],

      docsAsset: json['docs_asset'] ?? json['docsAsset'],
      docsImage: json['docs_image'] ?? json['docsImage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'process_id': processId,
      'what_to_do': whatToDo,
      'data_type': dataType,
      'file_id': fileId,
      'media_url': mediaUrl,
      'status': status,
      'utilization_amount': utilizationAmount,
      'officer_comment': officerComment,
      'docs_asset': docsAsset,
      'docs_image': docsImage,
    };
  }
}
