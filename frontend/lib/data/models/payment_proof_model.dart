class PaymentProofModel {
  final String id;
  final String orderId;
  final String uploadedBy;
  final String imageUrl;
  final String? note;
  final String? reviewNote;
  final String status;
  final DateTime createdAt;

  const PaymentProofModel({
    required this.id,
    required this.orderId,
    required this.uploadedBy,
    required this.imageUrl,
    this.note,
    this.reviewNote,
    required this.status,
    required this.createdAt,
  });

  factory PaymentProofModel.fromJson(Map<String, dynamic> json) {
    return PaymentProofModel(
      id: json['id']?.toString() ?? '',
      orderId:
          json['order_id']?.toString() ?? json['orderId']?.toString() ?? '',
      uploadedBy: json['uploaded_by']?.toString() ??
          json['uploadedBy']?.toString() ??
          '',
      imageUrl:
          json['image_url']?.toString() ?? json['imageUrl']?.toString() ?? '',
      note: json['note']?.toString(),
      reviewNote:
          json['review_note']?.toString() ?? json['reviewNote']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'uploaded_by': uploadedBy,
      'image_url': imageUrl,
      'note': note,
      'review_note': reviewNote,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
