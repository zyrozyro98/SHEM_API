She M backend API

Node + Express API used by the She M Flutter application.

Quick start:

```bash
cd backend/api
npm install
npm run dev
```

Available endpoints:
- `GET /` - health
- `GET /health/ready` - production readiness check for Firebase, GitHub media storage, and WhatsApp OTP configuration
- `GET|PUT|PATCH|DELETE /database?path=...` - authenticated Firebase Realtime Database gateway; only explicitly permitted paths and role operations are accepted
- `POST /database/orders` - create a checkout order from current product, currency, pricing, and saved-address data
- `POST /database/orders/:orderId/payment-proof` - submit a stored receipt for the authenticated customer's pending wallet order
- `POST /database/payment-proofs/:proofId/review` - approve or reject a pending payment proof as an administrator and atomically sync the order, customer mirror, and notification
- `POST /database/orders/:orderId/payment-method` - change the payment method on an owned, unpaid order using current wallet settings
- `POST /database/refund-requests` - create a refund request from the authenticated customer's order item and current database snapshots
- `POST /database/refund-requests/:requestId/review` - review a refund request as an administrator and sync the customer mirror
- `POST /database/merchant-withdrawals` - create a merchant withdrawal after the API recalculates released sales and active withdrawal reservations from Firebase
- `POST /database/merchant-withdrawals/:requestId/review` - approve, reject, or mark an approved withdrawal as paid; writes are administrator-only
- `GET /app-update/notice` - public app-update notice fields
- `GET /products` - list mock products
- `GET /products/:id` - get product
- `POST /orders` - create order (mock in-memory)
- `GET /orders?customer_id=` - list orders for a customer
- `POST /media/session` - exchange a valid phone/password login for a Firebase custom token
- `POST /media/switch-sessions` - create a saved account session for an authenticated Firebase user
- `POST /media/switch-sessions/restore` - restore an account session and refresh its idle expiry
- `POST /media/switch-sessions/revoke` - revoke a saved account session
- `POST /media/upload` - upload an authenticated product, receipt, promotion, profile, or wallet image to GitHub (product MP4 videos are also supported)
- `DELETE /accounts/:profileId` - delete a customer, merchant, or non-admin account after password reauthentication and order checks

Account-switch session secrets are stored on the device using secure storage; the
backend stores only their SHA-256 hashes in Firebase Realtime Database. Restoring
a session renews its idle expiry without changing its secret, so a dropped
response can be retried safely. Sessions expire after 30 days of inactivity and
have a 180-day maximum lifetime.

Media uploads require a GitHub fine-grained token with Contents: Read and write
permission for `GITHUB_REPOSITORY`. The API authenticates uploads with Firebase
ID tokens. Receipt uploads are stored under the configured receipts directory;
only URLs from that repository are accepted by the payment-proof endpoint.
Phone/password logins exchange credentials for a Firebase custom
token through `POST /media/session`; Firebase ID tokens are verified by Firebase
Admin before any file is accepted. Keep the Firebase service-account JSON and
GitHub token on the backend only.

```bash
flutter run --dart-define=SHEM_MEDIA_API_BASE_URL=http://10.0.2.2:8080
```

The client uploads resized JPEG images or compressed MP4 product videos with
`multipart/form-data` and stores only the returned `raw.githubusercontent.com`
URL. Images are limited to 2 MiB and product videos to 12 MiB. Existing data
URIs remain readable as a migration fallback.

For local development only, `MEDIA_ALLOW_LOCAL_UPLOADS=true` lets the API accept
uploads without Firebase authentication. Keep it `false` in production.

## Public deployment

`localhost`, `10.0.2.2`, and `adb reverse` are local-only addresses. Deploy this
API using the repository root `render.yaml`, then set these secret environment
variables in the hosting service:

- `GITHUB_TOKEN`: fine-grained token with `Contents: Read and write` for `zyrozyro98/SHEM_API`.
- `WAWP_INSTANCE_ID` and `WAWP_ACCESS_TOKEN`: the instance credentials from Wawp.
- `WAWP_API_URL`: `https://api.wawp.net` (optional; this is the default).
- `FIREBASE_SERVICE_ACCOUNT_JSON`: the Firebase Admin service-account JSON, stored as a secret environment variable.
- `FIREBASE_DATABASE_URL`: the Firebase Realtime Database URL.

Account deletion requires the Firebase Admin settings above. The endpoint checks
the requester's password against the current profile, blocks deletion while the
role-specific orders are active, removes the Firebase Auth user when one is
linked, deletes profile/session indexes, and archives a merchant's listings
while retaining order history. Never commit the service-account JSON.

The public app-update endpoint reads through Firebase Admin and returns only the
fields needed by clients to display the configured notice. It does not expose
internal metadata or allow writes.

Phone verification codes for signup, phone-number changes, and password resets
are sent through Wawp. Keep its credentials only in the backend environment;
never put them in Flutter build arguments or app code.
The backend requests OTPs with `POST /v2/auth/otp/send` and validates submitted
codes with `POST /v2/auth/otp/verify`. Both calls pass the credentials and
international phone number in the JSON body; Wawp generates and verifies the
OTP. The send request uses Arabic (`lang: ar`) and a custom message containing
Wawp's `{{otp}}` placeholder. Make sure `WAWP_INSTANCE_ID` and
`WAWP_ACCESS_TOKEN` are valid credentials from the same Wawp account.

After deployment, use the HTTPS service URL on every device:

```bash
flutter run --dart-define=SHEM_MEDIA_API_BASE_URL=https://shem-api.onrender.com
```

On Windows PowerShell, use the repository helper:

```powershell
.\scripts\run_flutter.ps1
```

Replace the example hostname with the URL assigned by the hosting provider.
Do not set `MEDIA_ALLOW_LOCAL_UPLOADS=true` on a public deployment.

To build and deploy Firebase Hosting:

```powershell
.\scripts\deploy_web.ps1
```

Phone/password users who were already signed in may need to sign in once after
the API update so the app can establish a Firebase-authenticated session.

Render uses `/health/ready` to avoid treating an API with missing production
credentials as ready. Configure the `FIREBASE_SERVICE_ACCOUNT_JSON`,
`FIREBASE_DATABASE_URL`, `GITHUB_TOKEN`, `GITHUB_REPOSITORY`,
`WAWP_INSTANCE_ID`, and `WAWP_ACCESS_TOKEN` variables in Render before release.
The local upload bypass is disabled when `NODE_ENV=production`.

The Flutter Firebase database client now sends Realtime Database operations
through `/database`; Firebase Admin performs the actual database access. Direct
client access is intended to be denied by `database.rules.json`. The gateway
uses a deny-by-default role policy, so a `403` indicates an operation that still
needs a dedicated server-side authorization rule or endpoint. Do not deploy the
deny-all Firebase rules until the release-critical app flows have been migrated
and tested against the gateway.

Merchant product creation is restricted to the authenticated merchant's own
product path. The gateway validates required product fields and forces new
products to remain pending and unavailable until admin review; merchants cannot
set approval or commission overrides during creation. Negative stock updates
are rejected.

Checkout order creation recalculates item amounts, commission, currency
conversion, and delivery fees from Firebase data. It requires coordinates on
the customer's selected saved address, rejects a stale client quote, and writes
the order, customer index, and order notifications in one database update.
Payment-proof submission verifies order ownership and pending wallet-payment
status, accepts only a receipt image URL from the configured GitHub repository,
and writes the proof, updated order, customer mirror, and notification in one
database update. Refund-request creation validates order ownership and item
selection, rejects duplicate active requests, derives the customer and merchant
claims from stored order data, and writes the admin record and customer index
in one update. Refund review requires an administrator, bounds approved
amounts by the customer's claim, records the reviewing profile from the
verified token, and syncs both indexes atomically. Generic writes to refund
requests are denied. Payment-proof and merchant-withdrawal records can only be
reviewed through their dedicated administrator endpoints. Merchant withdrawal
creation recalculates the three-day release period and reserved withdrawals
from current orders, products, currencies, and withdrawal records; a Firebase
transaction prevents simultaneous requests from reserving the same balance.

For a production Android build:

```powershell
.\scripts\build_release.ps1
```

Notes:
- This is a lightweight mock for development. For production use, implement these
  routes with proper database access, validation, authentication, and file storage.
