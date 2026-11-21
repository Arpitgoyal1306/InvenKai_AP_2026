-- Application SQL from InvenKai 33b5bbe. Locations refer to the pinned source.
-- Bind parameters in the order shown. CP4 samples use plans/fixture.sql.
-- BEGIN, COMMIT and ROLLBACK delimit transactions. LISTEN market_inventory
-- subscribes the API session to refresh notifications. These session commands
-- have no PostgreSQL execution plan. Redis/BullMQ commands run outside PostgreSQL.

-- READ
-- R1 · Startup clock probe
-- Source: server/server.js:193
SELECT NOW();

-- READ
-- R2 · Database readiness
-- Source: server/src/app.js:62, server/src/app.js:79
SELECT 1;

-- READ
-- R3 · Database identity
-- Source: server/src/config/database.js:102
SELECT current_database() AS database_name;

-- READ
-- R4 · Google-only account check
-- Source: server/src/middleware/auth.middleware.js:42
SELECT 1 FROM users WHERE id=$1 AND google_subject IS NOT NULL AND password_hash IS NULL;

-- READ
-- R5 · Buyer catalog
-- Source: server/src/routes/market.routes.js:123
SELECT p.id,p.name,p.description,p.photo,p.price,c.name AS category,i.quantity

      FROM products p JOIN inventory i ON i.product_id=p.id JOIN categories c ON c.id=p.category_id
      WHERE p.store_id=$1 AND p.deleted_at IS NULL AND ($2 OR NOT p.archived)
        AND strpos(lower(p.name), lower($3)) > 0 AND ($4 = '' OR c.name = $4)
        AND (NOT $5 OR (NOT p.archived AND (i.quantity <= COALESCE(p.low_stock_threshold, 3))))
      ORDER BY p.id DESC LIMIT $6 OFFSET $7;

-- READ
-- R6 · Owner low-stock catalog
-- Source: server/src/routes/market.routes.js:123
SELECT p.id,p.name,p.description,p.photo,p.price,c.name AS category,i.quantity
      ,p.archived,p.low_stock_threshold
      FROM products p JOIN inventory i ON i.product_id=p.id JOIN categories c ON c.id=p.category_id
      WHERE p.store_id=$1 AND p.deleted_at IS NULL AND ($2 OR NOT p.archived)
        AND strpos(lower(p.name), lower($3)) > 0 AND ($4 = '' OR c.name = $4)
        AND (NOT $5 OR (NOT p.archived AND (i.quantity <= COALESCE(p.low_stock_threshold, 3))))
      ORDER BY p.id DESC LIMIT $6 OFFSET $7;

-- READ
-- R7 · Store catalog categories
-- Source: server/src/routes/market.routes.js:134
SELECT DISTINCT c.name FROM products p JOIN categories c ON c.id=p.category_id
      WHERE p.store_id=$1 AND p.deleted_at IS NULL AND ($2 OR NOT p.archived) ORDER BY c.name;

-- READ
-- R8 · Published shop directory and previews
-- Source: server/src/routes/market.routes.js:153
SELECT s.name,s.slug,s.description,s.category,s.logo,s.cover,
          COALESCE((
            SELECT json_agg(json_build_object(
              'id', p.id::text, 'name', p.name, 'price', p.price::text, 'quantity', i.quantity
            ) ORDER BY p.id DESC)
            FROM (
              SELECT id,name,price FROM products
              WHERE store_id=s.id AND NOT archived ORDER BY id DESC LIMIT 3
            ) p JOIN inventory i ON i.product_id=p.id
          ), '[]'::json) AS products
       FROM stores s
       WHERE s.published AND strpos(lower(s.name), lower($1)) > 0
         AND ($2 = '' OR lower(s.category) = lower($2))
       ORDER BY s.name,s.id LIMIT $3 OFFSET $4;

-- READ
-- R9 · Public directory categories
-- Source: server/src/routes/market.routes.js:171
SELECT DISTINCT category FROM stores WHERE published ORDER BY category;

-- READ
-- R10 · Published store details
-- Source: server/src/routes/market.routes.js:184
SELECT id,name,slug,description,category,contact,pickup,logo,cover FROM stores WHERE slug=$1 AND published FOR SHARE;

-- READ
-- R11 · Refresh cart products
-- Source: server/src/routes/market.routes.js:205
SELECT p.id,p.name,p.photo,p.price,i.quantity
      FROM stores s JOIN products p ON p.store_id=s.id JOIN inventory i ON i.product_id=p.id
      WHERE s.slug=$1 AND s.published AND NOT p.archived AND p.id=ANY($2::bigint[]);

-- READ
-- R12 · Buyer purchase history
-- Source: server/src/routes/market.routes.js:254
SELECT o.id,o.status,o.total_amount,o.created_at,o.pickup_snapshot,
      COALESCE(s.name,'InvenKai') store_name, s.slug FROM orders o LEFT JOIN stores s ON s.id=o.store_id
      WHERE o.user_id=$1 ORDER BY o.created_at DESC,o.id DESC LIMIT $2 OFFSET $3;

-- READ
-- R13 · Current owner's store
-- Source: server/src/routes/market.routes.js:265
SELECT * FROM stores WHERE owner_id=$1;

-- READ
-- R14 · Owner category suggestions
-- Source: server/src/routes/market.routes.js:283
SELECT category FROM stores WHERE owner_id=$1
     UNION
     SELECT c.name FROM stores s JOIN products p ON p.store_id=s.id
       JOIN categories c ON c.id=p.category_id WHERE s.owner_id=$1 AND p.deleted_at IS NULL
     ORDER BY 1;

-- READ
-- R15 · Slug claimed by another owner
-- Source: server/src/routes/market.routes.js:300
SELECT 1 FROM stores WHERE slug=$1 AND owner_id<>$2;

-- WRITE
-- W1 · Save store profile
-- Source: server/src/routes/market.routes.js:321
INSERT INTO stores(owner_id,name,slug,description,category,contact,pickup,logo,cover)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(owner_id) DO UPDATE SET
    name=excluded.name,slug=excluded.slug,description=excluded.description,category=excluded.category,
    contact=excluded.contact,pickup=excluded.pickup,logo=excluded.logo,cover=excluded.cover
    WHERE NOT stores.slug_locked OR stores.slug=excluded.slug RETURNING *;

-- WRITE
-- W2 · Publish store
-- Source: server/src/routes/market.routes.js:340
UPDATE stores SET published=$2,slug_locked=slug_locked OR $2 WHERE id=$1
    AND (NOT $2 OR EXISTS(SELECT FROM products WHERE store_id=$1 AND NOT archived)) RETURNING *;

-- READ
-- R16 · Category lookup
-- Source: server/src/routes/market.routes.js:368, server/src/routes/market.routes.js:379
SELECT id FROM categories WHERE name=$1;

-- WRITE
-- W3 · Create seller category
-- Source: server/src/routes/market.routes.js:373
INSERT INTO categories(name) VALUES($1) ON CONFLICT(name) DO NOTHING RETURNING id;

-- WRITE
-- W4 · Edit seller product
-- Source: server/src/routes/market.routes.js:392
UPDATE products SET name=$1,description=$2,price=$3,photo=COALESCE($4,photo),category_id=$5,low_stock_threshold=$6,updated_at=NOW()
        WHERE store_id=$7 AND id=$8 AND deleted_at IS NULL RETURNING id;

-- WRITE
-- W5 · Create seller product
-- Source: server/src/routes/market.routes.js:400
INSERT INTO products(name,description,price,photo,category_id,low_stock_threshold,store_id,sku)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id;

-- WRITE
-- W6 · Initialize seller stock
-- Source: server/src/routes/market.routes.js:406, server/src/scripts/seed-sample-shops.js:154
INSERT INTO inventory(product_id,quantity) VALUES($1,$2);

-- WRITE
-- W7 · Record starting seller stock
-- Source: server/src/routes/market.routes.js:412, server/src/scripts/seed-sample-shops.js:158
INSERT INTO inventory_transactions(product_id,performed_by,transaction_type,quantity,quantity_before,quantity_after) VALUES($1,$2,'increase',$3,0,$3);

-- WRITE
-- W8 · Hide seller product
-- Source: server/src/routes/market.routes.js:425
UPDATE products SET archived=$3 WHERE id=$1 AND store_id=$2 AND deleted_at IS NULL;

-- WRITE
-- W9 · Soft-delete seller product
-- Source: server/src/routes/market.routes.js:433
UPDATE products SET archived=true,deleted_at=NOW(),updated_at=NOW()
     WHERE id=$1 AND store_id=$2 AND deleted_at IS NULL;

-- READ
-- R17 · Lock seller stock
-- Source: server/src/routes/market.routes.js:446
SELECT i.quantity FROM inventory i JOIN products p ON p.id=i.product_id WHERE p.id=$1 AND p.store_id=$2 AND p.deleted_at IS NULL FOR UPDATE OF p,i;

-- WRITE
-- W10 · Adjust seller stock and write audit row
-- Source: server/src/routes/market.routes.js:455
WITH updated AS (
        UPDATE inventory SET quantity=$6,updated_at=NOW() WHERE product_id=$1
        RETURNING product_id,quantity
      )
      INSERT INTO inventory_transactions(product_id,performed_by,transaction_type,quantity,quantity_before,quantity_after)
      SELECT product_id,$2,$3,$4,$5,quantity FROM updated;

-- READ
-- R18 · Owner stock history
-- Source: server/src/routes/market.routes.js:477
SELECT t.id,t.created_at,p.name,t.transaction_type,t.quantity,t.quantity_after
      FROM inventory_transactions t JOIN products p ON p.id=t.product_id
      WHERE p.store_id=$1 ORDER BY t.id DESC LIMIT $2 OFFSET $3;

-- READ
-- R19 · Owner inventory totals
-- Source: server/src/routes/market.routes.js:488
SELECT count(*)::int AS "activeProducts",
        count(*) FILTER (WHERE NOT p.archived AND (i.quantity <= COALESCE(p.low_stock_threshold, 3)))::int AS "lowProducts"
        FROM products p JOIN inventory i ON i.product_id=p.id
        WHERE p.store_id=$1 AND NOT p.archived;

-- READ
-- R20 · Owner order and sales totals
-- Source: server/src/routes/market.routes.js:495
SELECT count(*) FILTER (WHERE status='placed')::int AS "newOrders",
        COALESCE(sum(total_amount) FILTER (WHERE status<>'cancelled'
          AND created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'), 0) AS "sales"
        FROM orders WHERE store_id=$1;

-- READ
-- R21 · Owner low-stock alerts
-- Source: server/src/routes/market.routes.js:502
SELECT p.id,p.name,i.quantity FROM products p JOIN inventory i ON i.product_id=p.id
        WHERE p.store_id=$1 AND (NOT p.archived AND (i.quantity <= COALESCE(p.low_stock_threshold, 3))) ORDER BY i.updated_at DESC,p.id DESC LIMIT 20;

-- READ
-- R22 · Seller order list
-- Source: server/src/routes/market.routes.js:537
SELECT o.id,o.status,o.created_at,o.total_amount,u.name AS buyer
      FROM orders o JOIN users u ON u.id=o.user_id
      WHERE o.store_id=$1 AND strpos(o.id::text, $2) > 0 AND ($3 = '' OR o.status=$3)
        AND ($4::date IS NULL OR (
          o.created_at >= ($4::timestamp AT TIME ZONE 'UTC') + make_interval(mins => $5)
          AND o.created_at < (($4::date + 1)::timestamp AT TIME ZONE 'UTC') + make_interval(mins => $6)
        ))
      ORDER BY o.created_at DESC,o.id DESC LIMIT $7 OFFSET $8;

-- READ
-- R23 · Seller order details
-- Source: server/src/routes/market.routes.js:553
SELECT o.id,o.created_at,o.status,o.total_amount,o.pickup_snapshot,o.buyer_details,u.name AS buyer,u.email FROM orders o JOIN users u ON u.id=o.user_id WHERE o.id=$1 AND o.store_id=$2;

-- READ
-- R24 · Seller order lines
-- Source: server/src/routes/market.routes.js:560
SELECT product_name,quantity,unit_price,line_total FROM order_items WHERE order_id=$1 ORDER BY id;

-- WRITE
-- W11 · Advance fulfillment
-- Source: server/src/routes/market.routes.js:572
UPDATE orders SET status=$1,updated_at=NOW() WHERE id=$2 AND store_id=$3 AND status=$4 RETURNING id, pg_notify('market_inventory', json_build_object('owner',$5::text,'public',false)::text);

-- READ
-- R25 · Staff category list
-- Source: server/src/routes/workspace.routes.js:29
SELECT id,name FROM categories ORDER BY name,id;

-- WRITE
-- W12 · Create warehouse category
-- Source: server/src/routes/workspace.routes.js:42
INSERT INTO categories(name) VALUES ($1) ON CONFLICT (name) DO NOTHING RETURNING id, name;

-- READ
-- R26 · Check active supplier
-- Source: server/src/routes/workspace.routes.js:80
SELECT id FROM suppliers WHERE id=$1 AND is_active;

-- READ
-- R27 · List products for supplier linking
-- Source: server/src/routes/workspace.routes.js:86
SELECT p.id,p.name,p.sku,sp.supplier_id IS NOT NULL AS linked
     FROM products p LEFT JOIN supplier_products sp ON sp.product_id=p.id AND sp.supplier_id=$1
     WHERE p.store_id IS NULL
       AND (NOT p.archived OR sp.supplier_id IS NOT NULL)
       AND ($2::boolean = false OR sp.supplier_id IS NOT NULL)
     ORDER BY p.name,p.id LIMIT $3 OFFSET $4;

-- WRITE
-- W13 · Link warehouse product to supplier
-- Source: server/src/routes/workspace.routes.js:102
WITH target AS (
         SELECT id FROM products WHERE id=$2 AND store_id IS NULL AND NOT archived FOR UPDATE
       ), linked AS (
         INSERT INTO supplier_products(supplier_id, product_id)
         SELECT $1, id FROM target ON CONFLICT DO NOTHING
       )
       SELECT id FROM target;

-- WRITE
-- W14 · Unlink warehouse product
-- Source: server/src/routes/workspace.routes.js:132
DELETE FROM supplier_products sp USING products p
       WHERE sp.supplier_id=$1 AND sp.product_id=$2 AND p.id=sp.product_id AND p.store_id IS NULL;

-- READ
-- R28 · Buyer receipt lookup
-- Source: server/src/routes/workspace.routes.js:143
SELECT r.receipt_number, r.issued_at, r.total_amount, r.items
     FROM orders o LEFT JOIN receipts r ON r.order_id=o.id
     WHERE o.id=$1 AND o.user_id=$2;

-- READ
-- R29 · Operations queue totals
-- Source: server/src/routes/workspace.routes.js:179
SELECT COUNT(*) FILTER (WHERE status='pending') AS pending,
           COUNT(*) FILTER (WHERE status='processing') AS processing,
           COUNT(*) FILTER (WHERE status='dispatched') AS dispatched,
           (SELECT COUNT(*) FROM receipts) AS issued
    FROM order_outbox;

-- READ
-- R30 · Check receipt before retry
-- Source: server/src/scripts/retry-failed-order-receipts.js:41
SELECT id, receipt_number FROM receipts WHERE order_id = $1;

-- READ
-- R31 · Identify seeded shop owner
-- Source: server/src/scripts/seed-sample-shops.js:100
SELECT u.email FROM stores s JOIN users u ON u.id=s.owner_id WHERE s.slug=$1;

-- WRITE
-- W15 · Create sample shop owner
-- Source: server/src/scripts/seed-sample-shops.js:113
INSERT INTO users(name,email,password_hash,role) VALUES($1,$2,$3,'customer') RETURNING id;

-- WRITE
-- W16 · Create sample shop
-- Source: server/src/scripts/seed-sample-shops.js:119
INSERT INTO stores(owner_id,name,slug,description,category,contact,pickup,cover,published,slug_locked)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,true,true) RETURNING id;

-- WRITE
-- W17 · Ensure sample category exists
-- Source: server/src/scripts/seed-sample-shops.js:134
INSERT INTO categories(name) VALUES($1) ON CONFLICT DO NOTHING;

-- WRITE
-- W18 · Create sample product
-- Source: server/src/scripts/seed-sample-shops.js:141
INSERT INTO products(store_id,category_id,name,description,photo,price,sku,low_stock_threshold)
          SELECT $1,id,$3,$4,$5,$6,$7,4 FROM categories WHERE name=$2 RETURNING id;

-- WRITE
-- W19 · Register password account
-- Source: server/src/services/auth.service.js:79
INSERT INTO users (name, email, password_hash)
       VALUES ($1, $2, $3)
       RETURNING id, name, email, role, created_at;

-- READ
-- R32 · Password login lookup
-- Source: server/src/services/auth.service.js:107
SELECT id, name, email, password_hash, role
     FROM users
     WHERE email = $1;

-- WRITE
-- W20 · Refresh Google avatar
-- Source: server/src/services/auth.service.js:200
UPDATE users SET avatar_url=COALESCE($2,avatar_url) WHERE google_subject=$1 RETURNING id,name,email,role,avatar_url;

-- WRITE
-- W21 · Create Google account
-- Source: server/src/services/auth.service.js:208
INSERT INTO users(name,email,google_subject,avatar_url) VALUES($1,$2,$3,$4)
       ON CONFLICT(google_subject) DO UPDATE SET avatar_url=COALESCE(excluded.avatar_url,users.avatar_url)
       RETURNING id,name,email,role,avatar_url;

-- WRITE
-- W22 · Link verified Google account
-- Source: server/src/services/auth.service.js:240
UPDATE users SET google_subject=$2, avatar_url=COALESCE($3,avatar_url),
          password_hash=NULL, updated_at=NOW()
       WHERE email=$1 AND role='customer' AND google_subject IS NULL
       RETURNING id,name,email,role,avatar_url;

-- READ
-- R33 · Find linked Google account
-- Source: server/src/services/auth.service.js:251
SELECT id,name,email,role,avatar_url FROM users WHERE google_subject=$1;

-- READ
-- R34 · Account profile
-- Source: server/src/services/auth.service.js:276
SELECT id, name, email, role, phone, pickup_address, avatar_url, password_hash IS NULL AS google_only FROM users WHERE id=$1;

-- READ
-- R35 · Check profile-edit credential
-- Source: server/src/services/auth.service.js:316
SELECT email, password_hash FROM users WHERE id=$1;

-- WRITE
-- W23 · Save buyer profile
-- Source: server/src/services/auth.service.js:337
UPDATE users SET name=$2,email=$3,phone=$4,pickup_address=$5,updated_at=NOW()
       WHERE id=$1 AND email=$6 AND password_hash IS NOT DISTINCT FROM $7 RETURNING id, name, email, role, phone, pickup_address, avatar_url, password_hash IS NULL AS google_only;

-- READ
-- R36 · Look up warehouse stock
-- Source: server/src/services/inventory.service.js:18
SELECT product_id, quantity, created_at, updated_at
       FROM inventory
       WHERE product_id = $1 AND EXISTS (SELECT 1 FROM products WHERE id=$1 AND store_id IS NULL AND NOT archived);

-- READ
-- R37 · Warehouse low-stock list
-- Source: server/src/services/inventory.service.js:29
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
         AND p.store_id IS NULL AND NOT p.archived
       ORDER BY i.quantity ASC, p.name ASC;

-- READ
-- R38 · Lock warehouse inventory
-- Source: server/src/services/inventory.service.js:70
SELECT i.product_id, i.quantity
         FROM inventory i JOIN products p ON p.id = i.product_id
         WHERE i.product_id = $1 AND p.store_id IS NULL AND NOT p.archived
         FOR UPDATE OF p, i;

-- WRITE
-- W24 · Set warehouse quantity
-- Source: server/src/services/inventory.service.js:110
UPDATE inventory
         SET quantity = $2,
             updated_at = CURRENT_TIMESTAMP
         WHERE product_id = $1
         RETURNING product_id, quantity, updated_at;

-- WRITE
-- W25 · Record warehouse movement
-- Source: server/src/services/inventory.service.js:119
INSERT INTO inventory_transactions
          (product_id, performed_by, transaction_type, quantity,
           quantity_before, quantity_after)
         VALUES ($1, $2, $3, $4, $5, $6);

-- READ
-- R39 · All warehouse movements
-- Source: server/src/services/inventory.service.js:190
SELECT
         t.id, t.product_id, t.performed_by, t.transaction_type, t.quantity,
         t.quantity_before, t.quantity_after, t.created_at
       FROM inventory_transactions t JOIN products p ON p.id = t.product_id
       WHERE p.store_id IS NULL
       ORDER BY t.created_at DESC, t.id DESC
       LIMIT $1
       OFFSET $2;

-- READ
-- R40 · Movements for one warehouse product
-- Source: server/src/services/inventory.service.js:190
SELECT
         t.id, t.product_id, t.performed_by, t.transaction_type, t.quantity,
         t.quantity_before, t.quantity_after, t.created_at
       FROM inventory_transactions t JOIN products p ON p.id = t.product_id
       WHERE p.store_id IS NULL AND t.product_id = $1
       ORDER BY t.created_at DESC, t.id DESC
       LIMIT $2
       OFFSET $3;

-- READ
-- R41 · Warehouse inventory page
-- Source: server/src/services/inventory.service.js:219
SELECT p.id,p.name,p.sku,p.category_id,c.name AS category,p.price,
      i.quantity,p.low_stock_threshold
      FROM products p JOIN inventory i ON i.product_id=p.id
      JOIN categories c ON c.id=p.category_id
      WHERE p.store_id IS NULL AND NOT p.archived ORDER BY p.id LIMIT $1 OFFSET $2;

-- READ
-- R42 · Warehouse inventory count
-- Source: server/src/services/inventory.service.js:226
SELECT count(*)::int AS total FROM products p
      JOIN inventory i ON i.product_id=p.id WHERE p.store_id IS NULL AND NOT p.archived;

-- WRITE
-- W26 · Claim pending receipt jobs
-- Source: server/src/services/order-outbox-dispatcher.service.js:93
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
-- W27 · Renew dispatch lease
-- Source: server/src/services/order-outbox-dispatcher.service.js:128
UPDATE order_outbox
           SET locked_until = CURRENT_TIMESTAMP + ($1 * INTERVAL '1 second'),
               updated_at = CURRENT_TIMESTAMP
           WHERE id = ANY($3::bigint[])
             AND status = 'processing'
             AND claim_token = $2::uuid
           RETURNING id;

-- WRITE
-- W28 · Mark event dispatched
-- Source: server/src/services/order-outbox-dispatcher.service.js:147
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
-- W29 · Release failed dispatch
-- Source: server/src/services/order-outbox-dispatcher.service.js:171
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

-- WRITE
-- W30 · Enqueue receipt event
-- Source: server/src/services/order-outbox.service.js:6
INSERT INTO order_outbox (event_type, order_id, payload)
       VALUES ($1, $2, $3::jsonb)
       ON CONFLICT (event_type, order_id) DO NOTHING;

-- READ
-- R43 · Verify buyer exists
-- Source: server/src/services/order.service.js:112
SELECT id
     FROM users
     WHERE id = $1;

-- READ
-- R44 · Buyer order count
-- Source: server/src/services/order.service.js:124
SELECT COUNT(*) AS total
     FROM orders
     WHERE user_id = $1;

-- READ
-- R45 · Buyer order page and item counts
-- Source: server/src/services/order.service.js:134
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

-- READ
-- R46 · Buyer order with items
-- Source: server/src/services/order.service.js:168
SELECT
       o.id,
       o.user_id,
       o.status,
       o.total_amount,
       o.created_at,
       o.updated_at,
       o.buyer_details,
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

-- READ
-- R47 · Serialize same-key checkout
-- Source: server/src/services/order.service.js:280
SELECT pg_advisory_xact_lock(hashtextextended($1, 0));

-- READ
-- R48 · Look up prior checkout
-- Source: server/src/services/order.service.js:286
SELECT id,checkout_fingerprint FROM orders WHERE user_id=$1 AND checkout_key=$2;

-- READ
-- R49 · Lock store for checkout
-- Source: server/src/services/order.service.js:304
SELECT id, pickup FROM stores WHERE slug=$1 AND published FOR SHARE;

-- READ
-- R50 · Lock checkout products and inventory
-- Source: server/src/services/order.service.js:314
SELECT
         p.id,
         p.name,
         p.sku,
         p.price,
         i.quantity AS available_quantity
       FROM products p
       INNER JOIN inventory i ON i.product_id = p.id
       WHERE p.id = ANY($1::bigint[]) AND p.store_id IS NOT DISTINCT FROM $2::bigint AND NOT p.archived
       ORDER BY p.id
       FOR UPDATE OF p, i;

-- WRITE
-- W31 · Open order
-- Source: server/src/services/order.service.js:366
INSERT INTO orders (user_id, status, total_amount)
         VALUES ($1, 'placed', 0)
         RETURNING id, user_id, status, total_amount,
                   created_at, updated_at;

-- WRITE
-- W32 · Save checkout snapshots
-- Source: server/src/services/order.service.js:383
UPDATE orders SET store_id=$2,pickup_snapshot=$3,buyer_details=$4 WHERE id=$1;

-- WRITE
-- W33 · Record retry identity
-- Source: server/src/services/order.service.js:389
UPDATE orders SET checkout_key=$2,checkout_fingerprint=$3 WHERE id=$1;

-- WRITE
-- W34 · Insert order line
-- Source: server/src/services/order.service.js:399
INSERT INTO order_items
          (order_id, product_id, product_name, sku, unit_price, quantity)
         VALUES ($1, $2, $3, $4, $5, $6);

-- WRITE
-- W35 · Deduct available stock
-- Source: server/src/services/order.service.js:419
UPDATE inventory
         SET quantity = quantity - $2,
             updated_at = CURRENT_TIMESTAMP
         WHERE product_id = $1
           AND quantity >= $2
         RETURNING quantity;

-- WRITE
-- W36 · Record order stock movement
-- Source: server/src/services/order.service.js:438
INSERT INTO inventory_transactions
          (product_id, performed_by, transaction_type, quantity,
           quantity_before, quantity_after, order_id)
         VALUES ($1, $2, 'decrease', $3, $4, $5, $6);

-- WRITE
-- W37 · Calculate order total
-- Source: server/src/services/order.service.js:461
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
-- R51 · Read saved order lines
-- Source: server/src/services/order.service.js:476
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

-- WRITE
-- W38 · Create warehouse product
-- Source: server/src/services/product.service.js:157
INSERT INTO products (
        category_id,
        name,
        description,
        sku,
        price, low_stock_threshold
      )
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *;

-- WRITE
-- W39 · Initialize warehouse stock
-- Source: server/src/services/product.service.js:185
INSERT INTO inventory (product_id, quantity)
       VALUES ($1, 0);

-- READ
-- R52 · Warehouse product page
-- Source: server/src/services/product.service.js:221
SELECT *
     FROM products
     WHERE store_id IS NULL AND NOT archived
     ORDER BY id
     LIMIT $1
     OFFSET $2;

-- READ
-- R53 · Warehouse product details
-- Source: server/src/services/product.service.js:238
SELECT *
     FROM products
     WHERE id = $1 AND store_id IS NULL AND NOT archived;

-- READ
-- R54 · Lock warehouse product
-- Source: server/src/services/product.service.js:258
SELECT *
       FROM products
       WHERE id = $1 AND store_id IS NULL AND NOT archived
       FOR UPDATE;

-- WRITE
-- W40 · Edit warehouse product
-- Source: server/src/services/product.service.js:284
UPDATE products
       SET category_id = $1,
           name = $2,
           description = $3,
           sku = $4,
           price = $5,
           low_stock_threshold = $7,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $6
       RETURNING *;

-- WRITE
-- W41 · Archive warehouse product
-- Source: server/src/services/product.service.js:338
UPDATE products SET archived=true,updated_at=NOW()
     WHERE id=$1 AND store_id IS NULL AND NOT archived
     RETURNING *;

-- READ
-- R55 · Warehouse product count
-- Source: server/src/services/product.service.js:349
SELECT count(*)::int AS total FROM products WHERE store_id IS NULL AND NOT archived;

-- READ
-- R56 · Warehouse stock summary
-- Source: server/src/services/reports.service.js:42
SELECT
      COUNT(p.id)::INTEGER AS product_count,
      COUNT(i.product_id)::INTEGER AS products_with_inventory,
      (
        COUNT(p.id) - COUNT(i.product_id)
      )::INTEGER AS products_without_inventory,
      COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
    FROM products p
    LEFT JOIN inventory i
      ON i.product_id = p.id
    WHERE p.store_id IS NULL AND NOT p.archived;

-- READ
-- R57 · Stock by category
-- Source: server/src/services/reports.service.js:79
SELECT
      c.id AS category_id,
      c.name AS category_name,
      COUNT(DISTINCT p.id)::INTEGER AS product_count,
      COUNT(DISTINCT i.product_id)::INTEGER AS products_with_inventory,
      COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
    FROM categories c
    LEFT JOIN products p
      ON p.category_id = c.id AND p.store_id IS NULL AND NOT p.archived
    LEFT JOIN inventory i
      ON i.product_id = p.id GROUP BY c.id, c.name ORDER BY c.name ASC;

-- READ
-- R58 · Stock for one category
-- Source: server/src/services/reports.service.js:79
SELECT
      c.id AS category_id,
      c.name AS category_name,
      COUNT(DISTINCT p.id)::INTEGER AS product_count,
      COUNT(DISTINCT i.product_id)::INTEGER AS products_with_inventory,
      COALESCE(SUM(i.quantity), 0)::BIGINT AS total_stock_quantity
    FROM categories c
    LEFT JOIN products p
      ON p.category_id = c.id AND p.store_id IS NULL AND NOT p.archived
    LEFT JOIN inventory i
      ON i.product_id = p.id WHERE c.id = $1 GROUP BY c.id, c.name ORDER BY c.name ASC;

-- READ
-- R59 · Total warehouse movements
-- Source: server/src/services/reports.service.js:134
SELECT
        COALESCE(
          SUM(t.quantity) FILTER (
            WHERE t.transaction_type = 'increase'
          ),
          0
        ) AS total_added,
        COALESCE(
          SUM(t.quantity) FILTER (
            WHERE t.transaction_type = 'decrease'
          ),
          0
        ) AS total_removed
      FROM inventory_transactions t JOIN products p ON p.id = t.product_id
      WHERE p.store_id IS NULL AND t.created_at >= (
        $1::date::timestamp AT TIME ZONE 'UTC'
      )
      AND t.created_at < (
        ($2::date + INTERVAL '1 day')::timestamp
        AT TIME ZONE 'UTC'
      );

-- READ
-- R60 · Daily warehouse movements
-- Source: server/src/services/reports.service.js:162
SELECT
        TO_CHAR(
            (t.created_at AT TIME ZONE 'UTC')::date,
            'YYYY-MM-DD'
        ) AS date,
        COALESCE(
          SUM(t.quantity) FILTER (
            WHERE t.transaction_type = 'increase'
          ),
          0
        ) AS stock_added,
        COALESCE(
          SUM(t.quantity) FILTER (
            WHERE t.transaction_type = 'decrease'
          ),
          0
        ) AS stock_removed
      FROM inventory_transactions t JOIN products p ON p.id = t.product_id
      WHERE p.store_id IS NULL AND t.created_at >= (
        $1::date::timestamp AT TIME ZONE 'UTC'
      )
      AND t.created_at < (
        ($2::date + INTERVAL '1 day')::timestamp
        AT TIME ZONE 'UTC'
      )
      GROUP BY (t.created_at AT TIME ZONE 'UTC')::date
      ORDER BY date ASC;

-- WRITE
-- W42 · Create supplier
-- Source: server/src/services/supplier.service.js:179
INSERT INTO suppliers (
      name,
      contact_name,
      email,
      phone
    )
    VALUES ($1, $2, $3, $4)
    RETURNING *;

-- READ
-- R61 · Active supplier page
-- Source: server/src/services/supplier.service.js:213
SELECT *
     FROM suppliers
     WHERE is_active = TRUE
     ORDER BY id
     LIMIT $1
     OFFSET $2;

-- READ
-- R62 · Supplier details
-- Source: server/src/services/supplier.service.js:234
SELECT *
     FROM suppliers
     WHERE id = $1
       AND is_active = TRUE;

-- READ
-- R63 · Lock supplier for editing
-- Source: server/src/services/supplier.service.js:290
SELECT *
       FROM suppliers
       WHERE id = $1
         AND is_active = TRUE
       FOR UPDATE;

-- WRITE
-- W43 · Edit supplier
-- Source: server/src/services/supplier.service.js:358
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
-- W44 · Deactivate supplier
-- Source: server/src/services/supplier.service.js:407
UPDATE suppliers
     SET is_active = FALSE,
         updated_at = CURRENT_TIMESTAMP
     WHERE id = $1
       AND is_active = TRUE
     RETURNING *;

-- READ
-- R64 · Active supplier count
-- Source: server/src/services/supplier.service.js:421
SELECT count(*)::int AS total FROM suppliers WHERE is_active;

-- READ
-- R65 · Receipt generation inputs
-- Source: server/src/workers/order-receipt.processor.js:11
SELECT o.id AS order_id, o.user_id, o.total_amount,
              oi.id AS item_id, oi.product_id, oi.product_name, oi.sku,
              oi.unit_price, oi.quantity, oi.line_total
       FROM orders o
       LEFT JOIN order_items oi ON oi.order_id = o.id
       WHERE o.id = $1
       ORDER BY oi.id;

-- WRITE
-- W45 · Issue immutable receipt
-- Source: server/src/workers/order-receipt.processor.js:34
INSERT INTO receipts (order_id, receipt_number, user_id, total_amount, items)
       VALUES ($1, $2, $3, $4, $5::jsonb)
       ON CONFLICT (order_id) DO NOTHING
       RETURNING id, order_id, receipt_number, issued_at;

-- READ
-- R66 · Read existing receipt
-- Source: server/src/workers/order-receipt.processor.js:53
SELECT id, order_id, receipt_number, issued_at
       FROM receipts WHERE order_id = $1;
