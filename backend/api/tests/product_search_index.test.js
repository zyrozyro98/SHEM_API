const test = require('node:test');
const assert = require('node:assert/strict');
const {
  buildSearchIndexRecord,
  normalizeSearchText,
} = require('../services/product_search_index');

test('search normalization handles Arabic variants, marks, digits, and English', () => {
  assert.equal(
    normalizeSearchText('إِكْسِسْوار ۱۲٣'),
    normalizeSearchText('اكسسوار 123'),
  );
  assert.equal(normalizeSearchText('یك'), normalizeSearchText('يك'));
  assert.equal(normalizeSearchText('جمييييل'), normalizeSearchText('جميل'));
  assert.equal(
    normalizeSearchText('Hoodie—قميص'),
    normalizeSearchText('hoodie قميص'),
  );
});

test('search document includes product keywords, brand, categories, and description', () => {
  const record = buildSearchIndexRecord('bag-1', {
    name: 'حقيبة ظهر',
    brand: 'Example',
    alternative_names: ['شنطة', 'backpack'],
    category: 'حقائب',
    main_category: 'أزياء',
    subcategory: 'حقائب سفر',
    description: 'مناسبة للجامعة والعمل',
    price: '24.5',
    available: true,
  });

  assert.match(record.normalizedDocument, /شنطه/);
  assert.match(record.normalizedDocument, /backpack/);
  assert.match(record.normalizedDocument, /example/);
  assert.match(record.normalizedDocument, /للجامعه/);
  assert.equal(record.payload.id, 'bag-1');
  assert.equal(record.price, 24.5);
  assert.equal(record.available, true);
});

test('search document preserves unavailable products for explicit availability filters', () => {
  const record = buildSearchIndexRecord('out-of-stock', {
    name: 'منتج غير متوفر',
    available: false,
  });

  assert.equal(record.available, false);
  assert.equal(record.payload.available, false);
});
