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
- `GET /app-update/notice` - public app-update notice fields
- `GET /products` - list mock products
- `GET /products/:id` - get product
- `POST /orders` - create order (mock in-memory)
- `GET /orders?customer_id=` - list orders for a customer
- `POST /media/session` - exchange a valid phone/password login for a Firebase custom token
- `POST /media/switch-sessions` - create a saved account session for an authenticated Firebase user
- `POST /media/switch-sessions/restore` - restore an account session and refresh its idle expiry
- `POST /media/switch-sessions/revoke` - revoke a saved account session
- `POST /media/upload` - upload a compressed product image or product MP4 video to GitHub
- `DELETE /accounts/:profileId` - delete a customer, merchant, or non-admin account after password reauthentication and order checks

Account-switch session secrets are stored on the device using secure storage; the
backend stores only their SHA-256 hashes in Firebase Realtime Database. Restoring
a session renews its idle expiry without changing its secret, so a dropped
response can be retried safely. Sessions expire after 30 days of inactivity and
have a 180-day maximum lifetime.

Media uploads require a GitHub fine-grained token with Contents: Read and write
permission for `GITHUB_REPOSITORY`. The API authenticates uploads with Firebase
ID tokens. Phone/password logins exchange credentials for a Firebase custom
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

For a production Android build:

```powershell
.\scripts\build_release.ps1
```

Notes:
- This is a lightweight mock for development. For production use, implement these
  routes with proper database access, validation, authentication, and file storage.
