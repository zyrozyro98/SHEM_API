# REST API route plan

## Auth
- POST /auth/request-otp
  - body: { phone }
  - response: { success: true, message: 'OTP sent' }

- POST /auth/verify-otp
  - body: { phone, otp }
  - response: { success: true, token, user }

- POST /auth/register
  - body: { full_name, phone, role, city, address }
  - response: { user }

## Products
- GET /products
- GET /products/:id
- POST /products
- PATCH /products/:id

## Orders
- POST /orders
  - body: { customer_id, items, payment_method, subtotal, shipping_fee, total }

- GET /orders?customer_id=:id
- PATCH /orders/:id/status
  - body: { status }

## Payment proofs
- POST /payments/proofs
  - body: { order_id, uploaded_by, image_url, note }

- GET /payments/proofs?order_id=:id
- PATCH /payments/proofs/:id
  - body: { status }

## Delivery
- GET /delivery/:order_id
- POST /delivery/update
  - body: { order_id, courier_name, current_location, eta, status }

## Admin
- GET /admin/orders/pending
- PATCH /admin/orders/:id/approve
- PATCH /admin/orders/:id/reject
