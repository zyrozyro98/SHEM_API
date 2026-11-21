require('dotenv').config();
const db = require('../db');
const { getFirebaseDatabase } = require('../services/firebase_admin');
const {
  buildSearchIndexRecord,
} = require('../services/product_search_index');
const {
  deleteProductSearchRecord,
  upsertProductSearchRecord,
} = require('../services/product_search_repository');

const pageSize = 250;
const writeConcurrency = 10;

async function syncProduct(productId, product) {
  if (!product || product.is_archived === true) {
    await deleteProductSearchRecord(productId);
    return;
  }
  const record = buildSearchIndexRecord(productId, product);
  if (!record.name) {
    await deleteProductSearchRecord(productId);
    return;
  }
  await upsertProductSearchRecord(record);
}

async function syncAllProducts() {
  const firebaseDatabase = getFirebaseDatabase();
  const productsRef = firebaseDatabase.ref('products');
  const startedAt = new Date().toISOString();
  let cursor = null;
  let synced = 0;

  while (true) {
    let query = productsRef.orderByKey();
    if (cursor) query = query.startAt(cursor);
    const snapshot = await query.limitToFirst(pageSize + (cursor ? 1 : 0))
      .once('value');
    const entries = Object.entries(snapshot.val() || {})
      .filter(([productId]) => !cursor || productId > cursor);
    if (entries.length === 0) break;

    for (let offset = 0; offset < entries.length; offset += writeConcurrency) {
      const batch = entries.slice(offset, offset + writeConcurrency);
      await Promise.all(
        batch.map(([productId, product]) => syncProduct(productId, product)),
      );
      synced += batch.length;
    }

    cursor = entries[entries.length - 1][0];
    if (entries.length < pageSize) break;
  }

  await db.query(
    'delete from product_search_documents where updated_at < $1',
    [startedAt],
  );
  console.log(`Indexed ${synced} Firebase products`);
}

syncAllProducts()
  .catch(error => {
    console.error('Product search index backfill failed:', error);
    process.exitCode = 1;
  })
  .finally(() => db.pool.end());
