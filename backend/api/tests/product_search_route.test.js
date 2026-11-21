const assert = require('node:assert/strict');
const express = require('express');
const { once } = require('node:events');
const test = require('node:test');
const db = require('../db');
const productSearchRouter = require('../routes/product_search');

test('category search prioritizes a section without filtering other sections', async () => {
  const originalQuery = db.query;
  const queries = [];
  db.query = async (text, params) => {
    queries.push({ text, params });
    if (text.includes('select distinct brand as value')) {
      return { rows: [{ categories: ['shoes'], brands: [] }] };
    }
    if (queries.length === 1) {
      return {
        rows: [
          {
            product_id: 'selected-product',
            payload: { name: 'Selected product' },
            category_priority: 0,
            relevance: 20,
            price: 12,
            normalized_brand: '',
            created_at: null,
          },
          {
            product_id: 'other-product',
            payload: { name: 'Other product' },
            category_priority: 1,
            relevance: 10,
            price: 14,
            normalized_brand: '',
            created_at: null,
          },
        ],
      };
    }
    return { rows: [] };
  };

  const app = express();
  app.use('/product-search', productSearchRouter);
  const server = app.listen(0, '127.0.0.1');

  try {
    await once(server, 'listening');
    const address = server.address();
    const baseUrl = `http://127.0.0.1:${address.port}/product-search`;
    const firstUrl = new URL(baseUrl);
    firstUrl.searchParams.set('q', 'bag');
    firstUrl.searchParams.set('category', 'shoes');
    firstUrl.searchParams.set('limit', '1');

    const firstResponse = await fetch(firstUrl);
    assert.equal(firstResponse.status, 200);
    const firstPage = await firstResponse.json();
    assert.deepEqual(
      firstPage.products.map((product) => product.id),
      ['selected-product'],
    );
    assert.ok(firstPage.nextCursor);
    assert.equal(queries[0].params[2], 'shoes');
    assert.equal(queries[0].params[4], null);
    assert.match(
      queries[0].text,
      /order by category_priority asc, relevance desc, product_id asc/i,
    );
    assert.doesNotMatch(
      queries[0].text,
      /and\s*\(\$3\s*=\s*''\s+or normalized_category/i,
    );

    const nextUrl = new URL(firstUrl);
    nextUrl.searchParams.set('cursor', firstPage.nextCursor);
    const nextResponse = await fetch(nextUrl);
    assert.equal(nextResponse.status, 200);
    assert.match(
      queries[2].text,
      /category_priority > \$\d+ or \(category_priority = \$\d+ and \(relevance < \$\d+/i,
    );
    assert.equal(queries[2].params[2], 'shoes');
  } finally {
    await new Promise((resolve) => server.close(resolve));
    db.query = originalQuery;
  }
});

test('queries without direct matches return the nearest indexed products', async () => {
  const originalQuery = db.query;
  const queries = [];
  db.query = async (text, params) => {
    queries.push({ text, params });
    if (text.includes('fallback_score')) {
      return {
        rows: [
          {
            product_id: 'closest-product',
            payload: { name: 'Closest product' },
            category_priority: 1,
            fallback_score: 0.42,
          },
        ],
      };
    }
    return { rows: [] };
  };

  const app = express();
  app.use('/product-search', productSearchRouter);
  const server = app.listen(0, '127.0.0.1');

  try {
    await once(server, 'listening');
    const address = server.address();
    const url = new URL(
      `http://127.0.0.1:${address.port}/product-search?q=unmatched-query`,
    );
    const response = await fetch(url);
    assert.equal(response.status, 200);
    const page = await response.json();
    assert.equal(page.fallback, true);
    assert.deepEqual(
      page.products.map((product) => product.id),
      ['closest-product'],
    );
    assert.ok(queries.some(({ text }) => text.includes('fallback_score')));
    assert.equal(queries[0].params[4], null);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    db.query = originalQuery;
  }
});
