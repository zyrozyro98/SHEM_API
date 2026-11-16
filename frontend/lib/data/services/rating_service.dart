import 'package:she_m_app/data/services/firebase_database_service.dart';

class ProductRatingSummary {
  const ProductRatingSummary({required this.average, required this.count});

  final double average;
  final int count;

  bool get hasRatings => count > 0;
}

class RatingService {
  RatingService({DatabaseService? databaseService})
      : _databaseService = databaseService ?? FirebaseDatabaseService.instance;

  final DatabaseService _databaseService;

  Future<ProductRatingSummary> getSummary(String productId) async {
    if (productId.trim().isEmpty) {
      return const ProductRatingSummary(average: 0, count: 0);
    }
    try {
      final snapshot =
          await _databaseService.read('product_ratings/$productId');
      final ratings = snapshot.values
          .whereType<Map>()
          .map((value) {
            final map = Map<String, dynamic>.from(value);
            final rating = map['rating'];
            return rating is num
                ? rating.toDouble()
                : double.tryParse('$rating') ?? 0;
          })
          .where((rating) => rating > 0 && rating <= 5)
          .toList();
      if (ratings.isEmpty) {
        return const ProductRatingSummary(average: 0, count: 0);
      }
      final average = ratings.reduce((a, b) => a + b) / ratings.length;
      return ProductRatingSummary(average: average, count: ratings.length);
    } catch (_) {
      return const ProductRatingSummary(average: 0, count: 0);
    }
  }

  Future<bool> submitRating({
    required String productId,
    required String customerId,
    required double rating,
    String comment = '',
  }) async {
    if (productId.trim().isEmpty ||
        customerId.trim().isEmpty ||
        rating < 1 ||
        rating > 5) {
      return false;
    }
    try {
      await _databaseService.write(
        'product_ratings/$productId/$customerId',
        {
          'product_id': productId,
          'customer_id': customerId,
          'rating': rating,
          'comment': comment.trim(),
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
