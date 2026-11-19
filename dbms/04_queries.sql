-- ============================================================
-- InvenKai AP Project
-- CP3: Application SQL Query Inventory
-- Source: Arpitgoyal1306/InvenKai backend (main branch)
--
-- READ queries use R1, R2, ...
-- WRITE queries use W1, W2, ...
--
-- Parameters ($1, $2, ...) are supplied by the application.
-- Dynamic query notes identify optional clauses built by the
-- application at runtime.
--
-- Transaction-control statements (BEGIN, COMMIT, ROLLBACK) are
-- intentionally not assigned business-query IDs. They are
-- documented in the transaction notes after the relevant query.
-- Redis and BullMQ operations are not PostgreSQL queries and
-- are excluded.
-- ============================================================


-- ============================================================
-- SECTION 1: AUTHENTICATION
-- Source: backend/src/services/auth.service.js
-- ============================================================

-- WRITE
-- ID: W1
-- Purpose: Register a user and return the created account details.
-- Tables: users
INSERT INTO users (name, email, password_hash)
VALUES ($1, $2, $3)
RETURNING id, name, email, role, created_at;


-- READ
-- ID: R1
-- Purpose: Find a user by normalized email during login.
-- Tables: users
SELECT id, name, email, password_hash, role
FROM users
WHERE email = $1;


-- ============================================================
-- SECTION 2: PRODUCT MANAGEMENT
-- Source: backend/src/services/product.service.js
-- ============================================================

-- WRITE
-- ID: W2
-- Purpose: Create a product.
-- Tables: products
INSERT INTO products (
    category_id,
    name,
    description,
    sku,
    price
)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;


-- READ
-- ID: R2
-- Purpose: Retrieve products in ascending ID order with pagination.
-- Tables: products
SELECT *
FROM products
ORDER BY id
LIMIT $1
OFFSET $2;


-- READ
-- ID: R3
-- Purpose: Retrieve one product by its ID.
-- Tables: products
SELECT *
FROM products
WHERE id = $1;


-- READ
-- ID: R4
-- Purpose: Lock a product row before validating and updating it.
-- Tables: products
-- Note: Executed inside the product update transaction.
SELECT *
FROM products
WHERE id = $1
FOR UPDATE;


-- WRITE
-- ID: W3
-- Purpose: Update the supplied product fields and return the updated row.
-- Tables: products
UPDATE products
SET category_id = $1,
    name = $2,
    description = $3,
    sku = $4,
    price = $5,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $6
RETURNING *;


-- WRITE
-- ID: W4
-- Purpose: Delete a product and return the deleted row.
-- Tables: products
DELETE FROM products
WHERE id = $1
RETURNING *;


-- ============================================================
-- SECTION 3: INVENTORY MANAGEMENT
-- Source: backend/src/services/inventory.service.js
-- ============================================================

-- READ
-- ID: R5
-- Purpose: Retrieve inventory details for one product.
-- Tables: inventory
SELECT product_id, quantity, created_at, updated_at
FROM inventory
WHERE product_id = $1;


-- READ
-- ID: R6
-- Purpose: List products whose configured stock threshold has been reached.
-- Tables: products, inventory
SELECT
    p.id AS product_id,
    p.name,
    p.sku,
    p.category_id,
    i.quantity,
    p.low_stock_threshold
FROM products p
INNER JOIN inventory i
    ON i.product_id = p.id
WHERE p.low_stock_threshold IS NOT NULL
  AND i.quantity <= p.low_stock_threshold
ORDER BY i.quantity ASC, p.name ASC;


-- READ
-- ID: R7
-- Purpose: Lock an inventory row before changing its quantity.
-- Tables: inventory
-- Note: Executed inside the stock adjustment transaction.
SELECT product_id, quantity
FROM inventory
WHERE product_id = $1
FOR UPDATE;


-- WRITE
-- ID: W5
-- Purpose: Set the calculated stock quantity and return the updated inventory.
-- Tables: inventory
-- Note: Used for both stock increases and decreases.
UPDATE inventory
SET quantity = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE product_id = $1
RETURNING product_id, quantity, updated_at;


-- WRITE
-- ID: W6
-- Purpose: Record a stock increase or decrease in the inventory history.
-- Tables: inventory_transactions
INSERT INTO inventory_transactions
    (product_id, performed_by, transaction_type, quantity,
     quantity_before, quantity_after)
VALUES ($1, $2, $3, $4, $5, $6);


-- READ
-- ID: R8
-- Purpose: Retrieve inventory transaction history, optionally filtered by product.
-- Tables: inventory_transactions
-- Dynamic query: the backend emits one of these two parameterized forms.
--
-- Variant A: productId is not provided.
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
--
-- Variant B: productId is provided.
-- The actual backend query adds WHERE product_id = $1 and shifts
-- the pagination placeholders to $2 and $3.
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


-- ============================================================
-- SECTION 4: SUPPLIER MANAGEMENT
-- Source: backend/src/services/supplier.service.js
-- ============================================================

-- WRITE
-- ID: W7
-- Purpose: Create a supplier.
-- Tables: suppliers
INSERT INTO suppliers (
    name,
    contact_name,
    email,
    phone
)
VALUES ($1, $2, $3, $4)
RETURNING *;


-- READ
-- ID: R9
-- Purpose: Retrieve active suppliers with pagination.
-- Tables: suppliers
SELECT *
FROM suppliers
WHERE is_active = TRUE
ORDER BY id
LIMIT $1
OFFSET $2;


-- READ
-- ID: R10
-- Purpose: Retrieve one active supplier by ID.
-- Tables: suppliers
SELECT *
FROM suppliers
WHERE id = $1
  AND is_active = TRUE;


-- READ
-- ID: R11
-- Purpose: Lock an active supplier row before updating it.
-- Tables: suppliers
-- Note: Executed inside the supplier update transaction.
SELECT *
FROM suppliers
WHERE id = $1
  AND is_active = TRUE
FOR UPDATE;


-- WRITE
-- ID: W8
-- Purpose: Update supplier contact and identity fields.
-- Tables: suppliers
UPDATE suppliers
SET name = $1,
    contact_name = $2,
    email = $3,
    phone = $4,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $5
  AND is_active = TRUE
RETURNING *;


-- WRITE
-- ID: W9
-- Purpose: Soft-delete a supplier by marking it inactive.
-- Tables: suppliers
UPDATE suppliers
SET is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND is_active = TRUE
RETURNING *;


-- ============================================================
-- SECTION 5: ORDER RETRIEVAL
-- Source: backend/src/services/order.service.js
-- ============================================================

-- READ
-- ID: R12
-- Purpose: Verify that the user exists before retrieving their orders.
-- Tables: users
SELECT id
FROM users
WHERE id = $1;


-- READ
-- ID: R13
-- Purpose: Count the user's orders for pagination metadata.
-- Tables: orders
SELECT COUNT(*) AS total
FROM orders
WHERE user_id = $1;


-- READ
-- ID: R14
-- Purpose: Retrieve paginated orders for a user with the number of items in each order.
-- Tables: orders, order_items
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
LIMIT $2
OFFSET $3;


-- READ
-- ID: R15
-- Purpose: Retrieve one order and its item details for the owning user.
-- Tables: orders, order_items
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


-- ============================================================
-- SECTION 6: ORDER CREATION AND INVENTORY DEDUCTION
-- Source: backend/src/services/order.service.js
-- ============================================================

-- READ
-- ID: R16
-- Purpose: Retrieve and lock requested products and their inventory rows
--          in deterministic product ID order before checkout.
-- Tables: products, inventory
SELECT
    p.id,
    p.name,
    p.sku,
    p.price,
    i.quantity AS available_quantity
FROM products p
INNER JOIN inventory i
    ON i.product_id = p.id
WHERE p.id = ANY($1::bigint[])
ORDER BY p.id
FOR UPDATE OF p, i;


-- WRITE
-- ID: W10
-- Purpose: Create an order with its initial placed status.
-- Tables: orders
INSERT INTO orders (user_id, status, total_amount)
VALUES ($1, 'placed', 0)
RETURNING id, user_id, status, total_amount,
          created_at, updated_at;


-- WRITE
-- ID: W11
-- Purpose: Save a product snapshot as an order item.
-- Tables: order_items
-- Note: Executed once for each requested item.
INSERT INTO order_items
    (order_id, product_id, product_name, sku, unit_price, quantity)
VALUES ($1, $2, $3, $4, $5, $6);


-- WRITE
-- ID: W12
-- Purpose: Deduct ordered quantity from inventory when sufficient stock exists.
-- Tables: inventory
UPDATE inventory
SET quantity = quantity - $2,
    updated_at = CURRENT_TIMESTAMP
WHERE product_id = $1
  AND quantity >= $2
RETURNING quantity;


-- WRITE
-- ID: W13
-- Purpose: Record the order-related stock deduction.
-- Tables: inventory_transactions
INSERT INTO inventory_transactions
    (product_id, performed_by, transaction_type, quantity,
     quantity_before, quantity_after, order_id)
VALUES ($1, $2, 'decrease', $3, $4, $5, $6);


-- WRITE
-- ID: W14
-- Purpose: Calculate and save the order total from its generated item line totals.
-- Tables: orders, order_items
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


-- READ
-- ID: R17
-- Purpose: Retrieve saved order items after order creation.
-- Tables: order_items
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


-- ============================================================
-- SECTION 7: ORDER OUTBOX
-- Sources:
--   backend/src/services/order-outbox.service.js
--   backend/src/services/order-outbox-dispatcher.service.js
-- ============================================================

-- WRITE
-- ID: W15
-- Purpose: Add an idempotent receipt-request event to the outbox.
-- Tables: order_outbox
-- Note: Executed in the same transaction as order creation.
INSERT INTO order_outbox (event_type, order_id, payload)
VALUES ($1, $2, $3::jsonb)
ON CONFLICT (event_type, order_id) DO NOTHING;


-- WRITE
-- ID: W16
-- Purpose: Claim available or expired outbox events for processing.
-- Tables: order_outbox
-- Note: Uses SKIP LOCKED so concurrent dispatchers do not claim
--       the same candidate rows at the same time.
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


-- WRITE
-- ID: W17
-- Purpose: Renew the processing lease for events owned by the claim token.
-- Tables: order_outbox
UPDATE order_outbox
SET locked_until = CURRENT_TIMESTAMP + ($1 * INTERVAL '1 second'),
    updated_at = CURRENT_TIMESTAMP
WHERE id = ANY($3::bigint[])
  AND status = 'processing'
  AND claim_token = $2::uuid
RETURNING id;


-- WRITE
-- ID: W18
-- Purpose: Mark a successfully enqueued receipt event as dispatched.
-- Tables: order_outbox
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


-- WRITE
-- ID: W19
-- Purpose: Return a failed event to pending status with exponential backoff.
-- Tables: order_outbox
UPDATE order_outbox
SET status = 'pending',
    available_at = CURRENT_TIMESTAMP
        + LEAST(POWER(2, attempts), 60) * INTERVAL '1 second',
    locked_until = NULL,
    claim_token = NULL,
    last_error = $2,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND status = 'processing'
  AND claim_token = $3::uuid;


-- ============================================================
-- SECTION 8: REPORTS AND ANALYTICS
-- Source: backend/src/services/reports.service.js
-- ============================================================

-- READ
-- ID: R18
-- Purpose: Summarize total products, inventory coverage, and stock quantity.
-- Tables: products, inventory
SELECT
    COUNT(p.id)::INTEGER AS product_count,
    COUNT(i.product_id)::INTEGER AS products_with_inventory,
    (
        COUNT(p.id) - COUNT(i.product_id)
    )::INTEGER AS products_without_inventory,
    COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
FROM products p
LEFT JOIN inventory i
    ON i.product_id = p.id;


-- READ
-- ID: R19
-- Purpose: Retrieve category-wise product and stock totals.
-- Tables: categories, products, inventory
-- Dynamic query: when categoryId is supplied, the application adds
-- WHERE c.id = $1 before GROUP BY. Otherwise, no WHERE clause is added.
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
-- Optional WHERE c.id = $1
GROUP BY c.id, c.name
ORDER BY c.name ASC;


-- READ
-- ID: R20
-- Purpose: Calculate total stock added and removed in an inclusive date range.
-- Tables: inventory_transactions
SELECT
    COALESCE(
        SUM(quantity) FILTER (
            WHERE transaction_type = 'increase'
        ),
        0
    ) AS total_added,
    COALESCE(
        SUM(quantity) FILTER (
            WHERE transaction_type = 'decrease'
        ),
        0
    ) AS total_removed
FROM inventory_transactions
WHERE created_at >= (
    $1::date::timestamp AT TIME ZONE 'UTC'
)
AND created_at < (
    ($2::date + INTERVAL '1 day')::timestamp
    AT TIME ZONE 'UTC'
);


-- READ
-- ID: R21
-- Purpose: Retrieve daily stock added and removed in an inclusive date range.
-- Tables: inventory_transactions
SELECT
    TO_CHAR(
        (created_at AT TIME ZONE 'UTC')::date,
        'YYYY-MM-DD'
    ) AS date,
    COALESCE(
        SUM(quantity) FILTER (
            WHERE transaction_type = 'increase'
        ),
        0
    ) AS stock_added,
    COALESCE(
        SUM(quantity) FILTER (
            WHERE transaction_type = 'decrease'
        ),
        0
    ) AS stock_removed
FROM inventory_transactions
WHERE created_at >= (
    $1::date::timestamp AT TIME ZONE 'UTC'
)
AND created_at < (
    ($2::date + INTERVAL '1 day')::timestamp
    AT TIME ZONE 'UTC'
)
GROUP BY (created_at AT TIME ZONE 'UTC')::date
ORDER BY date ASC;


-- ============================================================
-- SECTION 9: RECEIPT PROCESSING AND RECOVERY
-- Sources:
--   backend/src/workers/order-receipt.processor.js
--   backend/src/scripts/retry-failed-order-receipts.js
-- ============================================================

-- READ
-- ID: R22
-- Purpose: Retrieve an order and its item snapshots to construct a receipt.
-- Tables: orders, order_items
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
LEFT JOIN order_items oi
    ON oi.order_id = o.id
WHERE o.id = $1
ORDER BY oi.id;


-- WRITE
-- ID: W20
-- Purpose: Create a receipt once per order and return its identifying details.
-- Tables: receipts
-- Note: ON CONFLICT prevents duplicate receipts for the same order.
INSERT INTO receipts (
    order_id,
    receipt_number,
    user_id,
    total_amount,
    items
)
VALUES ($1, $2, $3, $4, $5::jsonb)
ON CONFLICT (order_id) DO NOTHING
RETURNING id, order_id, receipt_number, issued_at;


-- READ
-- ID: R23
-- Purpose: Retrieve an existing receipt when receipt creation already occurred.
-- Tables: receipts
SELECT id, order_id, receipt_number, issued_at
FROM receipts
WHERE order_id = $1;


-- READ
-- ID: R24
-- Purpose: Check whether a receipt already exists before retrying a failed receipt job.
-- Tables: receipts
-- Source: backend/src/scripts/retry-failed-order-receipts.js
SELECT id, receipt_number
FROM receipts
WHERE order_id = $1;


-- ============================================================
-- SECTION 10: DATABASE HEALTH AND STARTUP
-- Sources:
--   backend/src/app.js
--   backend/server.js
-- ============================================================

-- READ
-- ID: R25
-- Purpose: Check PostgreSQL availability for the API health endpoint.
SELECT 1;


-- READ
-- ID: R26
-- Purpose: Verify PostgreSQL connectivity before starting the HTTP server.
SELECT NOW();


-- ============================================================
-- TRANSACTION NOTES
-- ============================================================
-- The application uses explicit transaction control around:
--
-- 1. Product update:
--    BEGIN -> R4 -> W3 -> COMMIT
--    On error: ROLLBACK
--
-- 2. Supplier update:
--    BEGIN -> R11 -> W8 -> COMMIT
--    On error: ROLLBACK
--
-- 3. Stock adjustment:
--    BEGIN -> R7 -> W5 -> W6 -> COMMIT
--    On error: ROLLBACK
--
-- 4. Order creation:
--    BEGIN -> R16 -> W10 -> W11 (once per item)
--    -> W12 and W13 (once per item) -> W14 -> R17 -> W15
--    -> COMMIT
--    On error: ROLLBACK
--
-- These transaction-control commands are not separate business
-- queries and therefore do not receive R/W IDs.
--
-- ============================================================
-- DYNAMIC QUERY NOTES
-- ============================================================
-- R8: The application conditionally adds a product_id filter.
--     Placeholder positions for LIMIT and OFFSET depend on whether
--     the optional product filter is present.
--
-- R19: The application conditionally adds a category ID filter.
--      The rest of the aggregation query remains unchanged.
--
-- ============================================================


-- ============================================================
-- CP3 AUDIT PATCH 1: R8 APPLICATION TRACE
-- ============================================================
-- R8 is implemented by getInventoryTransactions in
-- InvenKai/backend/src/services/inventory.service.js.
-- The GET /history route in
-- InvenKai/backend/src/routes/inventory.routes.js validates the
-- optional productId and pagination inputs before invoking it.
-- The focused test is
-- InvenKai/backend/test/inventory.service.test.js.
--
-- This establishes the application path for the R8 query inventory:
-- route validation -> inventory service -> parameterized SQL.

-- ============================================================
-- CP3 AUDIT PATCH 2: R8 PARAMETER AND SCHEMA CHECK
-- ============================================================
-- Without productId, the service binds [limit, offset], matching
-- LIMIT $1 and OFFSET $2 in R8 Variant A.
-- With productId, it binds [productId, limit, offset], matching
-- WHERE product_id = $1, LIMIT $2, and OFFSET $3 in Variant B.
--
-- R8 selects id, product_id, performed_by, transaction_type,
-- quantity, quantity_before, quantity_after, and created_at.
-- Each selected column is defined by inventory_transactions in
-- dbms/03_schema.sql. The focused service test checks the filtered
-- query's generated SQL and ordered values.

-- ============================================================
-- CP3 AUDIT PATCH 3: R19 APPLICATION TRACE
-- ============================================================
-- R19 is implemented by getCategoryStock in
-- InvenKai/backend/src/services/reports.service.js.
-- The GET /category-stock route in
-- InvenKai/backend/src/routes/reports.routes.js passes the optional
-- categoryId to the service. The focused tests are in
-- InvenKai/backend/test/reports.service.test.js.
--
-- The application path is route -> report service -> parameterized
-- category-stock aggregation query.

-- ============================================================
-- CP3 AUDIT PATCH 4: R19 SCHEMA AND PARAMETER CHECK
-- ============================================================
-- Without categoryId, the service emits no WHERE clause and binds [].
-- With categoryId, it validates/parses the value, adds
-- WHERE c.id = $1, and binds [parsedCategoryId].
--
-- The schema defines categories(id, name), products.category_id
-- referencing categories, and inventory.product_id referencing
-- products. The R19 joins therefore use defined relationship columns.
-- GROUP BY c.id, c.name matches the selected category attributes.
-- COUNT(DISTINCT p.id) and COUNT(DISTINCT i.product_id) count
-- products rather than rows multiplied by the joins.
-- The focused tests cover filtered, unfiltered, and invalid IDs.

-- ============================================================
-- CP3 AUDIT PATCH 5: FINDINGS AND AUDIT LIMITS
-- ============================================================
-- Conclusion: no table, column, join-key, or parameter-placeholder
-- mismatch was found for R8 or R19. No SQL correction was justified.
--
-- Evidence reviewed: the AP query inventory and schema, plus the
-- InvenKai service implementations, routes, and focused service tests
-- named in the preceding audit notes.
--
-- Scope limitation: this was a static source/schema/test audit.
-- No live database execution, data loading, benchmark suite, EXPLAIN
-- plan capture, or CP4 timing/plan file change was performed.
