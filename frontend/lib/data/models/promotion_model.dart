class PromotionModel {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String actionText;
  final String actionUrl;
  final String productId;
  final String merchantId;
  final bool isActive;
  final int sortOrder;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String approvalStatus;
  final String reviewReason;
  final DateTime? reviewedAt;

  const PromotionModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.actionText = 'تسوق الآن',
    this.actionUrl = '',
    required this.productId,
    required this.merchantId,
    required this.isActive,
    this.sortOrder = 0,
    this.startsAt,
    this.endsAt,
    this.approvalStatus = 'pending',
    this.reviewReason = '',
    this.reviewedAt,
  });

  factory PromotionModel.fromJson(Map<String, dynamic> json, {String? id}) {
    DateTime? parseDate(dynamic value) =>
        value == null ? null : DateTime.tryParse(value.toString());

    final rawImageUrl =
        (json['image_url'] ?? json['imageUrl'] ?? '').toString();

    return PromotionModel(
      id: (json['id'] ?? id ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      imageUrl: normalizePublicImageUrl(rawImageUrl),
      actionText:
          (json['action_text'] ?? json['actionText'] ?? 'تسوق الآن').toString(),
      actionUrl: (json['action_url'] ?? json['actionUrl'] ?? '').toString(),
      productId: (json['product_id'] ?? json['productId'] ?? '').toString(),
      merchantId: (json['merchant_id'] ?? json['merchantId'] ?? '').toString(),
      isActive: json['is_active'] == true ||
          json['isActive'] == true ||
          json['is_active']?.toString().toLowerCase() == 'true' ||
          json['isActive']?.toString().toLowerCase() == 'true',
      sortOrder: int.tryParse(
            (json['sort_order'] ?? json['sortOrder'] ?? 0).toString(),
          ) ??
          0,
      startsAt: parseDate(json['starts_at'] ?? json['startsAt']),
      endsAt: parseDate(json['ends_at'] ?? json['endsAt']),
      approvalStatus: _normalizeApprovalStatus(
        json['approval_status'] ?? json['approvalStatus'],
        isActive: json['is_active'] == true || json['isActive'] == true,
      ),
      reviewReason:
          (json['review_reason'] ?? json['reviewReason'] ?? '').toString(),
      reviewedAt: parseDate(json['reviewed_at'] ?? json['reviewedAt']),
    );
  }

  static String normalizePublicImageUrl(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return normalized;

    final match = RegExp(
      r'^https?://github\.com/([^/]+/[^/]+)/blob/([^/]+)/(.*)$',
    ).firstMatch(normalized);
    if (match == null) return normalized;

    final repository = match.group(1)!;
    final branch = Uri.encodeComponent(match.group(2)!);
    final path = match.group(3)!.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/$repository/$branch/$path';
  }

  static String _normalizeApprovalStatus(
    dynamic value, {
    required bool isActive,
  }) {
    final status = value?.toString().trim().toLowerCase() ?? '';
    if (status == 'pending' ||
        status == 'approved' ||
        status == 'rejected' ||
        status == 'ignored') {
      return status;
    }
    return isActive ? 'approved' : 'pending';
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'image_url': imageUrl,
        'product_id': productId,
        'merchant_id': merchantId,
        'is_active': isActive,
        'sort_order': sortOrder,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
        'approval_status': approvalStatus,
        'review_reason': reviewReason,
        'reviewed_at': reviewedAt?.toIso8601String(),
      };

  bool get isVisible {
    final now = DateTime.now();
    return approvalStatus == 'approved' &&
        isActive &&
        (startsAt == null || !now.isBefore(startsAt!)) &&
        (endsAt == null || !now.isAfter(endsAt!));
  }
}
