const test = require('node:test');
const assert = require('node:assert/strict');
const { getVisiblePromotions } = require('../routes/promotions');

test('public promotions include only active, approved, in-date banners', () => {
  const now = Date.parse('2026-11-21T02:00:00.000Z');
  const promotions = getVisiblePromotions(
    {
      visible: {
        title: 'منشور',
        image_url: 'https://example.test/visible.png',
        is_active: true,
        approval_status: 'approved',
        sort_order: 2,
        review_reason: 'private admin note',
      },
      legacy: {
        title: 'قديم',
        imageUrl: 'https://example.test/legacy.png',
        isActive: 'true',
        sortOrder: 1,
      },
      pending: {
        image_url: 'https://example.test/pending.png',
        is_active: true,
        approval_status: 'pending',
      },
      inactive: {
        image_url: 'https://example.test/inactive.png',
        is_active: false,
        approval_status: 'approved',
      },
      future: {
        image_url: 'https://example.test/future.png',
        is_active: true,
        approval_status: 'approved',
        starts_at: '2026-11-22T00:00:00.000Z',
      },
      expired: {
        image_url: 'https://example.test/expired.png',
        is_active: true,
        approval_status: 'approved',
        ends_at: '2026-11-20T00:00:00.000Z',
      },
      noImage: {
        is_active: true,
        approval_status: 'approved',
      },
    },
    now,
  );

  assert.deepEqual(
    promotions.map(promotion => promotion.id),
    ['legacy', 'visible'],
  );
  assert.equal(promotions[1].review_reason, undefined);
  assert.equal(promotions[1].approval_status, 'approved');
});
