-- ============================================================
-- InvenKai Application Query Inventory (CP3)
-- Source of Truth: Arpitgoyal1306/InvenKai (backend/server.js, backend/src/**)
-- Schema Reference: dbms/03_schema.sql
--
-- Summary:
--   READ  queries: R1 - R26 (26 queries)
--   WRITE queries: W1 - W20 (20 queries)
--   Total queries: 46
--
-- Note: Transaction control statements (BEGIN, COMMIT, ROLLBACK)
-- and non-PostgreSQL operations (Redis, BullMQ) are excluded.
-- ============================================================


-- ============================================================
-- READ QUERIES (R1 - R26)
-- ============================================================

-- [R1] backend/server.js :: startServer()
-- Startup PostgreSQL connectivity check
SELECT NOW();

-- [R2] backend/src/app.js :: GET /health
-- HTTP health-check database probe
SELECT 1;

-- [R3] backend/src/services/auth.service.js :: loginUser()
-- Look up user credentials and role by normalized email
SELECT id, name, email, password_hash, role
FROM users
WHERE email = $1;

-- [R4] backend/src/services/product.service.js :: getProducts()
-- Paginated product listing
SELECT *
FROM products
ORDER BY id
LIMIT $1
OFFSET $2;

-- [R5] backend/src/services/product.service.js :: getProductById()
-- Fetch a single product by primary key
SELECT *
FROM products
WHERE id = $1;

-- [R6] backend/src/services/product.service.js :: updateProduct()
-- Lock product row before merging PATCH updates (runs inside transaction)
SELECT *
FROM products
WHERE id = $1
FOR UPDATE;

-- [R7] backend/src/services/inventory.service.js :: getInventoryByProductId()
-- Fetch current stock level for a product
SELECT product_id, quantity, created_at, updated_at
FROM inventory
WHERE product_id = $1;

-- [R8] backend/src/services/inventory.service.js :: getLowStockProducts()
-- Also reused by backend/src/services/reports.service.js :: getLowStockSummary()
-- List products whose stock is at or below their configured threshold
SELECT
  p.id AS product_id,
  p.name,
  p.sku,
  p.category_id,
  i.quantity,
  p.low_stock_threshold
FROM products p
INNER JOIN inventory i ON i.product_id = p.id
WHERE p.low_stock_threshold IS NOT NULL
  AND i.quantity <= p.low_stock_threshold
ORDER BY i.quantity ASC, p.name ASC;

-- [R9] backend/src/services/inventory.service.js :: changeStock()
-- Lock inventory row before increasing or decreasing stock (runs inside transaction)
SELECT product_id, quantity
FROM inventory
WHERE product_id = $1
FOR UPDATE;

-- [R10] backend/src/services/inventory.service.js :: getInventoryTransactions()
-- Dynamic SQL (2 variants):
--   Variant A (no productId filter): $1 = limit, $2 = offset
--   Variant B (with productId filter): $1 = productId, $2 = limit, $3 = offset
-- Variant A (unfiltered):
SELECT
  id,
  product_id,
  performed_by,
  transaction_type,
  quantity,
  quantity_before,
  quantity_after,
  created_at
FROM inventory_transactions
ORDER BY created_at DESC, id DESC
LIMIT $1
OFFSET $2;

-- Variant B (filtered by product_id):
SELECT
  id,
  product_id,
  performed_by,
  transaction_type,
  quantity,
  quantity_before,
  quantity_after,
  created_at
FROM inventory_transactions
WHERE product_id = $1
ORDER BY created_at DESC, id DESC
LIMIT $2
OFFSET $3;

-- [R11] backend/src/services/supplier.service.js :: getSuppliers()
-- Paginated list of active suppliers
SELECT *
FROM suppliers
WHERE is_active = TRUE
ORDER BY id
LIMIT $1
OFFSET $2;

-- [R12] backend/src/services/supplier.service.js :: getSupplierById()
-- Fetch a single active supplier by ID
SELECT *
FROM suppliers
WHERE id = $1
  AND is_active = TRUE;

-- [R13] backend/src/services/supplier.service.js :: updateSupplier()
-- Lock active supplier row before merging updates (runs inside transaction)
SELECT *
FROM suppliers
WHERE id = $1
  AND is_active = TRUE
FOR UPDATE;

-- [R14] backend/src/services/reports.service.js :: getStockSummary()
-- Aggregate overall product and inventory counts
SELECT
  COUNT(p.id)::INTEGER AS product_count,
  COUNT(i.product_id)::INTEGER AS products_with_inventory,
  (COUNT(p.id) - COUNT(i.product_id))::INTEGER AS products_without_inventory,
  COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
FROM products p
LEFT JOIN inventory i
  ON i.product_id = p.id;

-- [R15] backend/src/services/reports.service.js :: getCategoryStock()
-- Dynamic SQL (2 variants):
--   Variant A (all categories): no parameters
--   Variant B (single category): $1 = categoryId
-- Variant A (all categories):
SELECT
  c.id AS category_id,
  c.name AS category_name,
  COUNT(DISTINCT p.id)::INTEGER AS product_count,
  COUNT(DISTINCT i.product_id)::INTEGER AS products_with_inventory,
  COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
FROM categories c
LEFT JOIN products p
  ON p.category_id = c.id
LEFT JOIN inventory i
  ON i.product_id = p.id
GROUP BY c.id, c.name
ORDER BY c.name ASC;

-- Variant B (filtered by category_id):
SELECT
  c.id AS category_id,
  c.name AS category_name,
  COUNT(DISTINCT p.id)::INTEGER AS product_count,
  COUNT(DISTINCT i.product_id)::INTEGER AS products_with_inventory,
  COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
FROM categories c
LEFT JOIN products p
  ON p.category_id = c.id
LEFT JOIN inventory i
  ON i.product_id = p.id
WHERE c.id = $1
GROUP BY c.id, c.name
ORDER BY c.name ASC;

-- [R16] backend/src/services/reports.service.js :: getStockMovement()
-- Aggregate stock added and removed within an inclusive UTC date range ($1 = startDate, $2 = endDate)
SELECT
  COALESCE(
    SUM(quantity) FILTER (WHERE transaction_type = 'increase'),
    0
  ) AS total_added,
  COALESCE(
    SUM(quantity) FILTER (WHERE transaction_type = 'decrease'),
    0
  ) AS total_removed
FROM inventory_transactions
WHERE created_at >= ($1::date::timestamp AT TIME ZONE 'UTC')
  AND created_at < (($2::date + INTERVAL '1 day')::timestamp AT TIME ZONE 'UTC');

-- [R17] backend/src/services/reports.service.js :: getStockMovement()
-- Daily stock movement breakdown within an inclusive UTC date range ($1 = startDate, $2 = endDate)
SELECT
  TO_CHAR((created_at AT TIME ZONE 'UTC')::date, 'YYYY-MM-DD') AS date,
  COALESCE(
    SUM(quantity) FILTER (WHERE transaction_type = 'increase'),
    0
  ) AS stock_added,
  COALESCE(
    SUM(quantity) FILTER (WHERE transaction_type = 'decrease'),
    0
  ) AS stock_removed
FROM inventory_transactions
WHERE created_at >= ($1::date::timestamp AT TIME ZONE 'UTC')
  AND created_at < (($2::date + INTERVAL '1 day')::timestamp AT TIME ZONE 'UTC')
GROUP BY (created_at AT TIME ZONE 'UTC')::date
ORDER BY date ASC;

-- [R18] backend/src/services/order.service.js :: getUserOrders()
-- Verify user exists before listing their orders
SELECT id
FROM users
WHERE id = $1;

-- [R19] backend/src/services/order.service.js :: getUserOrders()
-- Count total orders for a user
SELECT COUNT(*) AS total
FROM orders
WHERE user_id = $1;

-- [R20] backend/src/services/order.service.js :: getUserOrders()
-- Paginated user orders with item counts ($1 = userId, $2 = limit, $3 = offset)
SELECT
  o.id,
  o.user_id,
  o.status,
  o.total_amount,
  o.created_at,
  o.updated_at,
  COUNT(oi.id)::INTEGER AS item_count
FROM orders o
LEFT JOIN order_items oi
  ON oi.order_id = o.id
WHERE o.user_id = $1
GROUP BY o.id
ORDER BY o.created_at DESC, o.id DESC
LIMIT $2 OFFSET $3;

-- [R21] backend/src/services/order.service.js :: getOrderById()
-- Fetch a single order and its line items for a user ($1 = orderId, $2 = userId)
SELECT
  o.id,
  o.user_id,
  o.status,
  o.total_amount,
  o.created_at,
  o.updated_at,
  oi.id AS item_id,
  oi.product_id,
  oi.product_name,
  oi.sku,
  oi.unit_price,
  oi.quantity,
  oi.line_total
FROM orders o
LEFT JOIN order_items oi
  ON oi.order_id = o.id
WHERE o.id = $1
  AND o.user_id = $2
ORDER BY oi.id;

-- [R22] backend/src/services/order.service.js :: createOrder()
-- Lock ordered products and their inventory rows in deterministic order ($1 = bigint[] productIds)
SELECT
  p.id,
  p.name,
  p.sku,
  p.price,
  i.quantity AS available_quantity
FROM products p
INNER JOIN inventory i ON i.product_id = p.id
WHERE p.id = ANY($1::bigint[])
ORDER BY p.id
FOR UPDATE OF p, i;

-- [R23] backend/src/services/order.service.js :: createOrder()
-- Fetch saved order items with generated line_total before committing ($1 = orderId)
SELECT
  id,
  product_id,
  product_name,
  sku,
  unit_price,
  quantity,
  line_total
FROM order_items
WHERE order_id = $1
ORDER BY id;

-- [R24] backend/src/workers/order-receipt.processor.js :: processOrderReceipt()
-- Load order and line items to build receipt snapshot ($1 = orderId)
SELECT
  o.id AS order_id,
  o.user_id,
  o.total_amount,
  oi.id AS item_id,
  oi.product_id,
  oi.product_name,
  oi.sku,
  oi.unit_price,
  oi.quantity,
  oi.line_total
FROM orders o
LEFT JOIN order_items oi ON oi.order_id = o.id
WHERE o.id = $1
ORDER BY oi.id;

-- [R25] backend/src/workers/order-receipt.processor.js :: processOrderReceipt()
-- Fallback read when receipt already exists on conflict ($1 = orderId)
SELECT id, order_id, receipt_number, issued_at
FROM receipts
WHERE order_id = $1;

-- [R26] backend/src/scripts/retry-failed-order-receipts.js :: retryFailedOrderReceipt()
-- Check whether a receipt was already generated before retrying a failed BullMQ job ($1 = orderId)
SELECT id, receipt_number
FROM receipts
WHERE order_id = $1;


-- ============================================================
-- WRITE QUERIES (W1 - W20)
-- ============================================================

-- [W1] backend/src/services/auth.service.js :: registerUser()
-- Register a new user ($1 = name, $2 = email, $3 = password_hash)
INSERT INTO users (name, email, password_hash)
VALUES ($1, $2, $3)
RETURNING id, name, email, role, created_at;

-- [W2] backend/src/services/product.service.js :: createProduct()
-- Create a new product ($1 = category_id, $2 = name, $3 = description, $4 = sku, $5 = price)
INSERT INTO products (
  category_id,
  name,
  description,
  sku,
  price
)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- [W3] backend/src/services/product.service.js :: updateProduct()
-- Update product fields inside transaction ($1..$5 = fields, $6 = id)
UPDATE products
SET category_id = $1,
    name = $2,
    description = $3,
    sku = $4,
    price = $5,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $6
RETURNING *;

-- [W4] backend/src/services/product.service.js :: deleteProduct()
-- Delete product by ID ($1 = id)
DELETE FROM products
WHERE id = $1
RETURNING *;

-- [W5] backend/src/services/inventory.service.js :: changeStock()
-- Update inventory quantity inside transaction ($1 = productId, $2 = quantityAfter)
UPDATE inventory
SET quantity = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE product_id = $1
RETURNING product_id, quantity, updated_at;

-- [W6] backend/src/services/inventory.service.js :: changeStock()
-- Record stock increase/decrease audit row inside transaction ($1..$6)
INSERT INTO inventory_transactions
  (product_id, performed_by, transaction_type, quantity,
   quantity_before, quantity_after)
VALUES ($1, $2, $3, $4, $5, $6);

-- [W7] backend/src/services/supplier.service.js :: createSupplier()
-- Create a new supplier ($1 = name, $2 = contact_name, $3 = email, $4 = phone)
INSERT INTO suppliers (
  name,
  contact_name,
  email,
  phone
)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- [W8] backend/src/services/supplier.service.js :: updateSupplier()
-- Update active supplier inside transaction ($1..$4 = fields, $5 = id)
UPDATE suppliers
SET name = $1,
    contact_name = $2,
    email = $3,
    phone = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $5
  AND is_active = TRUE
RETURNING *;

-- [W9] backend/src/services/supplier.service.js :: deleteSupplier()
-- Soft-delete (deactivate) an active supplier ($1 = id)
UPDATE suppliers
SET is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND is_active = TRUE
RETURNING *;

-- [W10] backend/src/services/order.service.js :: createOrder()
-- Insert initial order row inside transaction ($1 = userId)
INSERT INTO orders (user_id, status, total_amount)
VALUES ($1, 'placed', 0)
RETURNING id, user_id, status, total_amount,
          created_at, updated_at;

-- [W11] backend/src/services/order.service.js :: createOrder()
-- Insert order item price/product snapshot inside transaction ($1..$6)
INSERT INTO order_items
  (order_id, product_id, product_name, sku, unit_price, quantity)
VALUES ($1, $2, $3, $4, $5, $6);

-- [W12] backend/src/services/order.service.js :: createOrder()
-- Conditionally deduct inventory inside transaction ($1 = productId, $2 = quantity)
UPDATE inventory
SET quantity = quantity - $2,
    updated_at = CURRENT_TIMESTAMP
WHERE product_id = $1
  AND quantity >= $2
RETURNING quantity;

-- [W13] backend/src/services/order.service.js :: createOrder()
-- Record order-linked inventory decrease inside transaction ($1..$6)
INSERT INTO inventory_transactions
  (product_id, performed_by, transaction_type, quantity,
   quantity_before, quantity_after, order_id)
VALUES ($1, $2, 'decrease', $3, $4, $5, $6);

-- [W14] backend/src/services/order.service.js :: createOrder()
-- Compute and store final order total_amount from order_items.line_total ($1 = orderId)
UPDATE orders
SET total_amount = (
  SELECT COALESCE(SUM(line_total), 0)
  FROM order_items
  WHERE order_id = $1
),
updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, user_id, status, total_amount,
          created_at, updated_at;

-- [W15] backend/src/services/order-outbox.service.js :: addOrderReceiptEvent()
-- Enqueue outbox event idempotently inside order transaction ($1 = event_type, $2 = orderId, $3 = payload jsonb)
INSERT INTO order_outbox (event_type, order_id, payload)
VALUES ($1, $2, $3::jsonb)
ON CONFLICT (event_type, order_id) DO NOTHING;

-- [W16] backend/src/services/order-outbox-dispatcher.service.js :: claimPendingEvents()
-- Atomically claim pending or expired-lease outbox events ($1 = batchSize, $2 = leaseSeconds, $3 = claimToken uuid)
WITH candidates AS (
  SELECT id
  FROM order_outbox
  WHERE
    (status = 'pending' AND available_at <= CURRENT_TIMESTAMP)
    OR
    (status = 'processing' AND locked_until < CURRENT_TIMESTAMP)
  ORDER BY id
  LIMIT $1
  FOR UPDATE SKIP LOCKED
)
UPDATE order_outbox AS events
SET status = 'processing',
    attempts = attempts + 1,
    locked_until = CURRENT_TIMESTAMP + ($2 * INTERVAL '1 second'),
    claim_token = $3::uuid,
    updated_at = CURRENT_TIMESTAMP
FROM candidates
WHERE events.id = candidates.id
RETURNING events.id, events.order_id, events.payload,
          events.attempts, events.claim_token;

-- [W17] backend/src/services/order-outbox-dispatcher.service.js :: renewClaimedEvents()
-- Extend lease for in-flight claimed outbox events ($1 = leaseSeconds, $2 = claimToken uuid, $3 = bigint[] ids)
UPDATE order_outbox
SET locked_until = CURRENT_TIMESTAMP + ($1 * INTERVAL '1 second'),
    updated_at = CURRENT_TIMESTAMP
WHERE id = ANY($3::bigint[])
  AND status = 'processing'
  AND claim_token = $2::uuid
RETURNING id;

-- [W18] backend/src/services/order-outbox-dispatcher.service.js :: markDispatched()
-- Mark outbox event dispatched when claim token still matches ($1 = id, $2 = claimToken uuid)
UPDATE order_outbox
SET status = 'dispatched',
    dispatched_at = CURRENT_TIMESTAMP,
    locked_until = NULL,
    claim_token = NULL,
    last_error = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND status = 'processing'
  AND claim_token = $2::uuid;

-- [W19] backend/src/services/order-outbox-dispatcher.service.js :: releaseForRetry()
-- Release failed outbox event back to pending with exponential backoff ($1 = id, $2 = last_error, $3 = claimToken uuid)
UPDATE order_outbox
SET status = 'pending',
    available_at = CURRENT_TIMESTAMP + LEAST(POWER(2, attempts), 60) * INTERVAL '1 second',
    locked_until = NULL,
    claim_token = NULL,
    last_error = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND status = 'processing'
  AND claim_token = $3::uuid;

-- [W20] backend/src/workers/order-receipt.processor.js :: processOrderReceipt()
-- Idempotently insert receipt snapshot ($1 = order_id, $2 = receipt_number, $3 = user_id, $4 = total_amount, $5 = items jsonb)
INSERT INTO receipts (order_id, receipt_number, user_id, total_amount, items)
VALUES ($1, $2, $3, $4, $5::jsonb)
ON CONFLICT (order_id) DO NOTHING
RETURNING id, order_id, receipt_number, issued_at;
