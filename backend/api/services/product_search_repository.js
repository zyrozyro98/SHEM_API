const db = require('../db');

async function upsertProductSearchRecord(record) {
  const createdAt = record.createdAt ? new Date(record.createdAt) : null;
  const normalizedCreatedAt =
    createdAt && !Number.isNaN(createdAt.getTime())
      ? createdAt.toISOString()
      : null;

  await db.query(
    `
      insert into product_search_documents (
        product_id, merchant_id, name, brand, category, main_category,
        subcategory, description, keywords, normalized_name,
        normalized_brand, normalized_category, normalized_main_category,
        normalized_subcategory, normalized_description,
        normalized_keywords, normalized_document, price, available,
        created_at, payload, updated_at
      ) values (
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,
        $18,$19,$20,$21::jsonb,now()
      )
      on conflict (product_id) do update set
        merchant_id = excluded.merchant_id,
        name = excluded.name,
        brand = excluded.brand,
        category = excluded.category,
        main_category = excluded.main_category,
        subcategory = excluded.subcategory,
        description = excluded.description,
        keywords = excluded.keywords,
        normalized_name = excluded.normalized_name,
        normalized_brand = excluded.normalized_brand,
        normalized_category = excluded.normalized_category,
        normalized_main_category = excluded.normalized_main_category,
        normalized_subcategory = excluded.normalized_subcategory,
        normalized_description = excluded.normalized_description,
        normalized_keywords = excluded.normalized_keywords,
        normalized_document = excluded.normalized_document,
        price = excluded.price,
        available = excluded.available,
        created_at = excluded.created_at,
        payload = excluded.payload,
        updated_at = now()
    `,
    [
      record.productId,
      record.merchantId,
      record.name,
      record.brand,
      record.category,
      record.mainCategory,
      record.subcategory,
      record.description,
      record.keywords,
      record.normalizedName,
      record.normalizedBrand,
      record.normalizedCategory,
      record.normalizedMainCategory,
      record.normalizedSubcategory,
      record.normalizedDescription,
      record.normalizedKeywords,
      record.normalizedDocument,
      record.price,
      record.available,
      normalizedCreatedAt,
      JSON.stringify(record.payload),
    ],
  );
}

async function deleteProductSearchRecord(productId) {
  await db.query(
    'delete from product_search_documents where product_id = $1',
    [productId],
  );
}

module.exports = {
  deleteProductSearchRecord,
  upsertProductSearchRecord,
};
