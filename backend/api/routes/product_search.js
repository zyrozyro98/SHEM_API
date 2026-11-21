const express = require('express');
const db = require('../db');
const {
  getFirebaseAuth,
  getFirebaseDatabase,
} = require('../services/firebase_admin');
const {
  buildSearchIndexRecord,
  normalizeSearchText,
} = require('../services/product_search_index');
const {
  deleteProductSearchRecord,
  upsertProductSearchRecord,
} = require('../services/product_search_repository');

const router = express.Router();
const maxPageSize = 40;
const maxSyncBatchSize = 50;
const sortExpressions = {
  relevance: 'relevance desc, product_id asc',
  newest: 'created_at desc nulls last, product_id asc',
  price_asc: 'coalesce(price, 0) asc, product_id asc',
  price_desc: 'coalesce(price, 0) desc, product_id asc',
  category_asc: 'normalized_category asc, product_id asc',
  category_desc: 'normalized_category desc, product_id asc',
  brand_asc: 'normalized_brand asc, product_id asc',
  brand_desc: 'normalized_brand desc, product_id asc',
  available_first: 'available desc, product_id asc',
  unavailable_first: 'available asc, product_id asc',
};

let cachedFacets;
let cachedFacetsAt = 0;

function getBearerToken(req) {
  const authorization = req.headers.authorization || '';
  return authorization.startsWith('Bearer ')
    ? authorization.slice('Bearer '.length).trim()
    : '';
}

async function requireFirebaseUser(req, res, next) {
  const token = getBearerToken(req);
  if (!token) return res.status(401).json({ error: 'Authentication required' });

  try {
    req.firebaseUser = await getFirebaseAuth().verifyIdToken(token);
    if (!req.firebaseUser.uid) {
      return res.status(401).json({ error: 'Invalid authentication token' });
    }
    return next();
  } catch (error) {
    if (error.code === 'FIREBASE_ADMIN_NOT_CONFIGURED') {
      return res.status(503).json({ error: 'Search indexing is unavailable' });
    }
    return res.status(401).json({ error: 'Invalid authentication token' });
  }
}

function decodeCursor(value) {
  if (!value) return null;
  try {
    const cursor = JSON.parse(Buffer.from(value, 'base64url').toString('utf8'));
    if (!cursor || typeof cursor !== 'object') return null;
    return cursor;
  } catch {
    return null;
  }
}

function encodeCursor(row, sort) {
  const cursor = {
    sort,
    productId: row.product_id,
    relevance: Number(row.relevance) || 0,
    price: Number(row.price) || 0,
    category: row.normalized_category || '',
    brand: row.normalized_brand || '',
    available: row.available === true,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
  };
  return Buffer.from(JSON.stringify(cursor)).toString('base64url');
}

function addCursorCondition(cursor, sort, params) {
  if (!cursor) return '';
  if (cursor.sort !== sort || typeof cursor.productId !== 'string') {
    throw new Error('Invalid search cursor');
  }

  const idIndex = params.push(cursor.productId);
  const id = `$${idIndex}`;
  let value;
  let expression;
  let comparison;
  switch (sort) {
    case 'relevance':
      value = Number(cursor.relevance);
      expression = 'relevance';
      comparison = '<';
      break;
    case 'newest':
      value = cursor.createdAt ?? '1970-01-01T00:00:00.000Z';
      expression = "coalesce(created_at, '1970-01-01'::timestamptz)";
      comparison = '<';
      break;
    case 'price_asc':
    case 'price_desc':
      value = Number(cursor.price);
      expression = 'coalesce(price, 0)';
      comparison = sort === 'price_asc' ? '>' : '<';
      break;
    case 'category_asc':
    case 'category_desc':
      value = String(cursor.category ?? '');
      expression = 'normalized_category';
      comparison = sort === 'category_asc' ? '>' : '<';
      break;
    case 'brand_asc':
    case 'brand_desc':
      value = String(cursor.brand ?? '');
      expression = 'normalized_brand';
      comparison = sort === 'brand_asc' ? '>' : '<';
      break;
    case 'available_first':
    case 'unavailable_first':
      value = cursor.available === true;
      expression = 'available';
      comparison = sort === 'available_first' ? '<' : '>';
      break;
    default:
      throw new Error('Unsupported search cursor');
  }

  if (sort === 'newest') {
    value = new Date(value);
    if (Number.isNaN(value.getTime())) {
      throw new Error('Invalid search cursor');
    }
    value = value.toISOString();
  } else if (sort === 'relevance' || sort.startsWith('price_')) {
    if (!Number.isFinite(value)) throw new Error('Invalid search cursor');
  }
  const valueIndex = params.push(value);
  const valuePlaceholder = `$${valueIndex}`;
  return `(${expression} ${comparison} ${valuePlaceholder} or ` +
    `(${expression} = ${valuePlaceholder} and product_id > ${id}))`;
}

function fieldScore(field, weight) {
  return `greatest(
    case when ${field} = query_word then 1000
         when ${field} like query_word || '%' then 850
         when ${field} like '%' || query_word || '%' then 700
         when char_length(query_word) >= 3 and query_word <% ${field}
           then word_similarity(query_word, ${field}) * 600
         else 0 end
  ) * ${weight}`;
}

const relevanceExpression = `
  case when $1 = '' then 0::double precision else
    (case when normalized_name = $1 then 1000
          when normalized_name like $1 || '%' then 850
          when normalized_name like '%' || $1 || '%' then 700
          when $1 <% normalized_name then word_similarity($1, normalized_name) * 600
          else 0 end) * 5
    + (case when normalized_brand = $1 then 1000
            when normalized_brand like $1 || '%' then 850
            when normalized_brand like '%' || $1 || '%' then 700
            when $1 <% normalized_brand then word_similarity($1, normalized_brand) * 600
            else 0 end) * 4
    + (case when normalized_keywords = $1 then 1000
            when normalized_keywords like $1 || '%' then 850
            when normalized_keywords like '%' || $1 || '%' then 700
            when $1 <% normalized_keywords then word_similarity($1, normalized_keywords) * 600
            else 0 end) * 4
    + (case when normalized_description = $1 then 1000
            when normalized_description like $1 || '%' then 850
            when normalized_description like '%' || $1 || '%' then 700
            when $1 <% normalized_description then word_similarity($1, normalized_description) * 600
            else 0 end)
    + (case when normalized_document like '%' || $1 || '%' then 300 else 0 end)
    + coalesce((
      select sum(greatest(
        ${fieldScore('normalized_name', 5)},
        ${fieldScore('normalized_brand', 4)},
        ${fieldScore('normalized_keywords', 4)},
        ${fieldScore('normalized_category', 2)},
        ${fieldScore('normalized_main_category', 2)},
        ${fieldScore('normalized_subcategory', 2)},
        ${fieldScore('normalized_description', 1)}
      ))
      from unnest($2::text[]) as query_words(query_word)
    ), 0)
  end as relevance`;

async function getFacets() {
  const now = Date.now();
  if (cachedFacets && now - cachedFacetsAt < 60_000) return cachedFacets;

  const { rows } = await db.query(`
    select
      coalesce((
        select json_agg(value order by value)
        from (
          select distinct value
          from (
            select category as value from product_search_documents
            union all
            select main_category as value from product_search_documents
            union all
            select subcategory as value from product_search_documents
          ) categories
          where value <> ''
          limit 500
        ) distinct_categories
      ), '[]'::json) as categories,
      coalesce((
        select json_agg(value order by value)
        from (
          select distinct brand as value
          from product_search_documents
          where brand <> ''
          limit 500
        ) distinct_brands
      ), '[]'::json) as brands
  `);
  cachedFacets = rows[0] ?? { categories: [], brands: [] };
  cachedFacetsAt = now;
  return cachedFacets;
}

router.get('/', async (req, res) => {
  const rawQuery = String(req.query.q ?? '');
  if (rawQuery.length > 120) {
    return res.status(400).json({ error: 'Search query is too long' });
  }
  const normalizedQuery = normalizeSearchText(rawQuery);
  const queryWords = [...new Set(normalizedQuery.split(' ').filter(Boolean))];
  const category = normalizeSearchText(req.query.category ?? '');
  const brand = normalizeSearchText(req.query.brand ?? '');
  const availability = String(req.query.availability ?? 'available');
  const availableFilter =
    availability === 'available'
      ? true
      : availability === 'unavailable'
        ? false
        : null;
  if (!['all', 'available', 'unavailable'].includes(availability)) {
    return res.status(400).json({ error: 'Invalid availability filter' });
  }
  const sort = String(req.query.sort ?? 'relevance');
  const orderBy = sortExpressions[sort];
  if (!orderBy) return res.status(400).json({ error: 'Invalid sort option' });

  const limitValue = Number.parseInt(String(req.query.limit ?? '20'), 10);
  const limit = Number.isFinite(limitValue)
    ? Math.max(1, Math.min(maxPageSize, limitValue))
    : 20;
  const params = [
    normalizedQuery,
    queryWords,
    category,
    brand,
    availableFilter,
    limit + 1,
  ];
  const cursor = decodeCursor(req.query.cursor);
  let cursorCondition = '';
  if (req.query.cursor && !cursor) {
    return res.status(400).json({ error: 'Invalid search cursor' });
  }
  try {
    cursorCondition = addCursorCondition(cursor, sort, params);
  } catch {
    return res.status(400).json({ error: 'Invalid search cursor' });
  }

  const whereCursor = cursorCondition ? `and ${cursorCondition}` : '';
  try {
    const { rows } = await db.query(
      `
        with scored as (
          select documents.*,
                 ${relevanceExpression}
          from product_search_documents documents
          where ($1 = '' or
            normalized_document like '%' || $1 || '%' or exists (
              select 1
              from unnest($2::text[]) as query_words(query_word)
              where normalized_document like '%' || query_word || '%'
                 or (char_length(query_word) >= 3 and (
                   query_word <% normalized_name
                   or query_word <% normalized_brand
                   or query_word <% normalized_keywords
                   or query_word <% normalized_description
                 ))
            ))
            and ($3 = '' or normalized_category = $3
              or normalized_main_category = $3
              or normalized_subcategory = $3)
            and ($4 = '' or normalized_brand = $4)
            and ($5::boolean is null or available = $5::boolean)
        )
        select *
        from scored
        where true ${whereCursor}
        order by ${orderBy}
        limit $6
      `,
      params,
    );
    const hasMore = rows.length > limit;
    const pageRows = hasMore ? rows.slice(0, limit) : rows;
    const facets = await getFacets();
    return res.json({
      products: pageRows.map(row => {
        const payload =
          typeof row.payload === 'string' ? JSON.parse(row.payload) : row.payload;
        return { ...payload, id: row.product_id };
      }),
      nextCursor: hasMore
        ? encodeCursor(pageRows[pageRows.length - 1], sort)
        : null,
      facets,
    });
  } catch (error) {
    console.error('Product search failed:', error);
    return res.status(500).json({ error: 'Product search is temporarily unavailable' });
  }
});

router.post('/sync', requireFirebaseUser, async (req, res) => {
  const productIds = Array.isArray(req.body?.productIds)
    ? [...new Set(req.body.productIds.map(id => String(id).trim()))]
    : [];
  if (
    productIds.length === 0 ||
    productIds.length > maxSyncBatchSize ||
    productIds.some(id => !/^[A-Za-z0-9_-]{1,128}$/.test(id))
  ) {
    return res.status(400).json({ error: 'Invalid product IDs' });
  }

  try {
    const firebaseDatabase = getFirebaseDatabase();
    for (const productId of productIds) {
      const snapshot = await firebaseDatabase
        .ref(`products/${productId}`)
        .once('value');
      const product = snapshot.val();
      if (!product || product.is_archived === true) {
        await deleteProductSearchRecord(productId);
        continue;
      }

      const record = buildSearchIndexRecord(productId, product);
      if (!record.name) {
        await deleteProductSearchRecord(productId);
        continue;
      }

      await upsertProductSearchRecord(record);
    }

    cachedFacets = null;
    return res.json({ synced: productIds.length });
  } catch (error) {
    console.error('Product search index sync failed:', error);
    return res.status(500).json({ error: 'Product search index sync failed' });
  }
});

module.exports = router;
