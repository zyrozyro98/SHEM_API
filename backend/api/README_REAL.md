Production-ready backend (instructions)

This folder contains an Express-based backend that connects to a PostgreSQL database (Supabase/Postgres) and uses Supabase Storage for payment proofs.

Required environment variables (create a `.env` from `.env.example`):
- `DATABASE_URL` - Postgres connection string (e.g., Supabase DB)
- `SUPABASE_URL` - Supabase project URL
- `SUPABASE_ANON_KEY` - Supabase anon/public key (used only to verify tokens)
- `SUPABASE_SERVICE_ROLE_KEY` - Supabase service role key (used for Storage uploads)
- `SUPABASE_PROOFS_BUCKET` - Storage bucket name for payment proofs (default `payment-proofs`)

Setup:

```bash
cd backend/api
npm install
# run DB migrations (local psql or supabase CLI)
npm run migrate

# create a .env file using .env.example then:
npm run dev
```

Endpoints (authenticated endpoints require `Authorization: Bearer <access_token>`):
- `GET /config/google-sign-in` - public Google Web OAuth client ID for Flutter Web
- `GET /products` - public list of available products
- `GET /products/:id` - product detail
- `POST /products` - create product (merchant/admin)
- `PATCH /products/:id` - update product (owner/admin)
- `GET /product-search` - paginated Arabic/English product search and filters
- `POST /product-search/sync` - sync Firebase product IDs into the search index
- `POST /orders` - create order (authenticated user)
- `GET /orders` - list orders for authenticated user
- `POST /payments/proofs` - upload payment proof (multipart form `file`)

### Product search index

The Flutter catalog remains authoritative in Firebase Realtime Database. Search
uses the indexed PostgreSQL `product_search_documents` table so a query returns
only a small, ranked page instead of downloading the whole catalog. The index
includes product names, brands, descriptions, categories, and each product's
`alternative_names` search keywords. Rating-based search is intentionally not
included.

Before deploying the updated API:

```bash
cd backend/api
npm run migrate:product-search
npm run sync:product-search
```

The backfill reads Firebase products in bounded key-ordered pages and is safe to
rerun. Configure `FIREBASE_DATABASE_URL`, `FIREBASE_SERVICE_ACCOUNT_JSON`, and
`DATABASE_URL` on the API host first. Once the API is deployed, the Flutter
Firebase database service asks it to refresh the affected product's index after
product writes, updates, and deletes. Search remains usable from locally cached
products if the API is unreachable.

Security notes:
- Ensure `SUPABASE_SERVICE_ROLE_KEY` is kept secret and not exposed to clients.
- Set `GOOGLE_WEB_CLIENT_ID` in Render to the Google OAuth 2.0 **Web client ID**.
  The public config endpoint returns only this client ID; never put a Google
  client secret in this variable or expose one to Flutter Web.
- Run `schema.sql` to create tables before starting the server.
- Configure Supabase Storage bucket policies to restrict public access; signed URLs are used here for convenience but adjust per policy.

Docker (local dev)
-------------------
You can run the full local stack (Postgres + API) using Docker Compose.

1. Create `backend/api/.env` from `.env.example` and fill values.
2. From the repository root run:

```bash
cd backend
docker compose up --build
```

This will start Postgres (initializing `schema.sql`) and the API server on `http://localhost:8080`.

To tear down and remove volumes:

```bash
docker compose down -v
```

Note: The compose file runs the API in dev mode (`npm run dev`) so code changes are picked up. For production, build a production image and run with `npm start`.
