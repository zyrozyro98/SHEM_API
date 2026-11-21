const express = require('express');
const { getFirebaseDatabase } = require('../services/firebase_admin');

const router = express.Router();

function isActive(value) {
  return value === true || value === 1 || ['true', '1'].includes(
    String(value ?? '').trim().toLowerCase(),
  );
}

function parseDate(value) {
  if (value == null || value === '') return null;
  const timestamp = typeof value === 'number' ? value : Date.parse(String(value));
  return Number.isFinite(timestamp) ? timestamp : null;
}

function getVisiblePromotions(data, now = Date.now()) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return [];

  return Object.entries(data)
    .filter(([, promotion]) =>
      promotion && typeof promotion === 'object' && !Array.isArray(promotion),
    )
    .map(([id, promotion]) => {
      const active = isActive(promotion.is_active ?? promotion.isActive);
      const rawStatus = String(
        promotion.approval_status ?? promotion.approvalStatus ?? '',
      ).trim().toLowerCase();
      const approvalStatus = rawStatus || (active ? 'approved' : 'pending');
      const startsAt = parseDate(promotion.starts_at ?? promotion.startsAt);
      const endsAt = parseDate(promotion.ends_at ?? promotion.endsAt);
      const imageUrl = String(
        promotion.image_url ?? promotion.imageUrl ?? '',
      ).trim();
      const sortOrder = Number.parseInt(
        String(promotion.sort_order ?? promotion.sortOrder ?? 0),
        10,
      );

      return {
        id,
        title: String(promotion.title ?? ''),
        subtitle: String(promotion.subtitle ?? ''),
        image_url: imageUrl,
        action_text: String(
          promotion.action_text ?? promotion.actionText ?? 'تسوق الآن',
        ),
        action_url: String(promotion.action_url ?? promotion.actionUrl ?? ''),
        product_id: String(promotion.product_id ?? promotion.productId ?? ''),
        merchant_id: String(promotion.merchant_id ?? promotion.merchantId ?? ''),
        is_active: active,
        sort_order: Number.isFinite(sortOrder) ? sortOrder : 0,
        starts_at: startsAt == null ? null : new Date(startsAt).toISOString(),
        ends_at: endsAt == null ? null : new Date(endsAt).toISOString(),
        approval_status: approvalStatus,
        visible: active &&
          approvalStatus === 'approved' &&
          imageUrl.length > 0 &&
          (startsAt == null || now >= startsAt) &&
          (endsAt == null || now <= endsAt),
      };
    })
    .filter(promotion => promotion.visible)
    .map(({ visible, ...promotion }) => promotion)
    .sort((first, second) =>
      first.sort_order - second.sort_order || first.id.localeCompare(second.id),
    );
}

router.get('/', async (req, res) => {
  try {
    const snapshot = await getFirebaseDatabase()
      .ref('promotions')
      .once('value');
    res.set('Cache-Control', 'public, max-age=30');
    return res.json({
      promotions: getVisiblePromotions(snapshot.val()),
    });
  } catch (error) {
    console.error('Public promotions request failed:', error);
    const status = error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED' ? 503 : 500;
    return res.status(status).json({
      error: 'Promotions are temporarily unavailable',
    });
  }
});

module.exports = { getVisiblePromotions, router };
