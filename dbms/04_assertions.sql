-- ============================================================
-- InvenKai Database Schema Assertions
-- Fail-fast verification for dbms/03_schema.sql
-- ============================================================

DO $$
DECLARE
    r RECORD;
    actual_count INTEGER;
    actual_type TEXT;
    actual_nullable TEXT;
    actual_cols TEXT[];
    actual_del CHAR(1);
    actual_target TEXT;
    gen_mode CHAR(1);
    pred TEXT;
BEGIN
    -- 1. All 11 expected tables exist (and no unexpected tables)
    FOR r IN
        SELECT unnest(ARRAY[
            'categories', 'users', 'suppliers', 'products', 'inventory',
            'orders', 'inventory_transactions', 'supplier_products',
            'order_items', 'order_outbox', 'receipts'
        ]) AS tbl
    LOOP
        IF to_regclass(format('public.%I', r.tbl)) IS NULL THEN
            RAISE EXCEPTION 'Missing expected table: public.%', r.tbl;
        END IF;
    END LOOP;

    SELECT COUNT(*) INTO actual_count
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    IF actual_count <> 11 THEN
        RAISE EXCEPTION 'Expected 11 tables in public schema, found %', actual_count;
    END IF;

    -- 2. Critical column types and nullability
    FOR r IN
        SELECT * FROM (VALUES
            ('products', 'description', 'text', 'YES'),
            ('products', 'low_stock_threshold', 'integer', 'YES'),
            ('orders', 'created_at', 'timestamp without time zone', 'NO'),
            ('orders', 'updated_at', 'timestamp without time zone', 'NO'),
            ('inventory_transactions', 'performed_by', 'bigint', 'YES'),
            ('inventory_transactions', 'order_id', 'bigint', 'YES'),
            ('order_items', 'sku', 'character varying', 'YES'),
            ('order_items', 'line_total', 'numeric', 'YES'),
            ('order_outbox', 'payload', 'jsonb', 'NO'),
            ('order_outbox', 'locked_until', 'timestamp with time zone', 'YES'),
            ('order_outbox', 'claim_token', 'uuid', 'YES'),
            ('order_outbox', 'last_error', 'text', 'YES'),
            ('order_outbox', 'dispatched_at', 'timestamp with time zone', 'YES'),
            ('receipts', 'items', 'jsonb', 'NO')
        ) AS t(tbl, col, expected_type, expected_nullable)
    LOOP
        SELECT data_type, is_nullable INTO actual_type, actual_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = r.tbl AND column_name = r.col;
        IF NOT FOUND OR actual_type <> r.expected_type OR actual_nullable <> r.expected_nullable THEN
            RAISE EXCEPTION 'Column %.% mismatch: got (%, %), expected (%, %)',
                r.tbl, r.col, actual_type, actual_nullable, r.expected_type, r.expected_nullable;
        END IF;
    END LOOP;

    -- 3. Generated column order_items.line_total is STORED
    SELECT a.attgenerated INTO gen_mode
    FROM pg_attribute a
    WHERE a.attrelid = 'public.order_items'::regclass
      AND a.attname = 'line_total' AND NOT a.attisdropped;
    IF gen_mode IS DISTINCT FROM 's' THEN
        RAISE EXCEPTION 'order_items.line_total attgenerated=%, expected ''s'' (STORED)', gen_mode;
    END IF;

    -- 4. Primary keys on all 11 tables
    FOR r IN
        SELECT * FROM (VALUES
            ('categories', ARRAY['id']), ('users', ARRAY['id']),
            ('suppliers', ARRAY['id']), ('products', ARRAY['id']),
            ('inventory', ARRAY['id']), ('orders', ARRAY['id']),
            ('inventory_transactions', ARRAY['id']),
            ('supplier_products', ARRAY['supplier_id', 'product_id']),
            ('order_items', ARRAY['id']), ('order_outbox', ARRAY['id']),
            ('receipts', ARRAY['id'])
        ) AS t(tbl, expected_cols)
    LOOP
        SELECT array_agg(a.attname::TEXT ORDER BY k.ord) INTO actual_cols
        FROM pg_constraint con
        CROSS JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord)
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
        WHERE con.conrelid = format('public.%I', r.tbl)::regclass AND con.contype = 'p';
        IF actual_cols IS DISTINCT FROM r.expected_cols THEN
            RAISE EXCEPTION 'PK on % is %, expected %', r.tbl, actual_cols, r.expected_cols;
        END IF;
    END LOOP;

    -- 5. All 13 foreign keys and ON DELETE rules
    FOR r IN
        SELECT * FROM (VALUES
            ('products', 'category_id', 'categories', 'r'),
            ('inventory', 'product_id', 'products', 'r'),
            ('orders', 'user_id', 'users', 'r'),
            ('inventory_transactions', 'product_id', 'products', 'r'),
            ('inventory_transactions', 'performed_by', 'users', 'n'),
            ('inventory_transactions', 'order_id', 'orders', 'r'),
            ('supplier_products', 'supplier_id', 'suppliers', 'r'),
            ('supplier_products', 'product_id', 'products', 'r'),
            ('order_items', 'order_id', 'orders', 'c'),
            ('order_items', 'product_id', 'products', 'r'),
            ('order_outbox', 'order_id', 'orders', 'c'),
            ('receipts', 'order_id', 'orders', 'r'),
            ('receipts', 'user_id', 'users', 'r')
        ) AS t(src_tbl, src_col, ref_tbl, expected_del)
    LOOP
        SELECT con.confdeltype, con.confrelid::regclass::TEXT INTO actual_del, actual_target
        FROM pg_constraint con
        JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
        WHERE con.conrelid = format('public.%I', r.src_tbl)::regclass
          AND con.contype = 'f' AND a.attname = r.src_col;
        IF NOT FOUND OR actual_target <> r.ref_tbl OR actual_del <> r.expected_del THEN
            RAISE EXCEPTION 'FK %.% mismatch: got (target=%, del=%), expected (%, %)',
                r.src_tbl, r.src_col, actual_target, actual_del, r.ref_tbl, r.expected_del;
        END IF;
    END LOOP;

    -- 6. Unique and CHECK constraints (migration-aligned names)
    FOR r IN
        SELECT * FROM (VALUES
            ('categories', 'categories_name_key', 'u'),
            ('users', 'users_email_key', 'u'),
            ('products', 'products_sku_key', 'u'),
            ('inventory', 'inventory_product_id_key', 'u'),
            ('order_items', 'order_items_unique_product', 'u'),
            ('order_outbox', 'order_outbox_unique_event_per_order', 'u'),
            ('receipts', 'receipts_order_id_key', 'u'),
            ('receipts', 'receipts_receipt_number_key', 'u'),
            ('suppliers', 'suppliers_name_not_empty', 'c'),
            ('suppliers', 'suppliers_contact_required', 'c'),
            ('products', 'products_low_stock_threshold_non_negative', 'c'),
            ('inventory', 'inventory_quantity_check', 'c'),
            ('orders', 'orders_status_check', 'c'),
            ('orders', 'orders_total_amount_nonnegative', 'c'),
            ('inventory_transactions', 'inventory_transactions_transaction_type_check', 'c'),
            ('inventory_transactions', 'inventory_transactions_quantity_check', 'c'),
            ('inventory_transactions', 'inventory_transactions_quantity_before_check', 'c'),
            ('inventory_transactions', 'inventory_transactions_quantity_after_check', 'c'),
            ('inventory_transactions', 'valid_transaction_quantity', 'c'),
            ('inventory_transactions', 'inventory_order_decrease_only', 'c'),
            ('order_items', 'order_items_quantity_positive', 'c'),
            ('order_items', 'order_items_price_nonnegative', 'c'),
            ('order_outbox', 'order_outbox_status_check', 'c'),
            ('order_outbox', 'order_outbox_attempts_nonnegative', 'c'),
            ('receipts', 'receipts_total_nonnegative', 'c'),
            ('receipts', 'receipts_items_array_check', 'c')
        ) AS t(tbl, con_name, con_type)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = format('public.%I', r.tbl)::regclass
              AND conname = r.con_name AND contype = r.con_type
        ) THEN
            RAISE EXCEPTION 'Missing constraint %.% (type %)', r.tbl, r.con_name, r.con_type;
        END IF;
    END LOOP;

    -- 7. Explicit indexes and partial order_outbox predicates
    FOR r IN
        SELECT unnest(ARRAY[
            'idx_inventory_transactions_product_created',
            'idx_inventory_transactions_order',
            'idx_orders_user_created',
            'supplier_products_product_id_idx',
            'idx_order_items_product',
            'idx_order_outbox_pending',
            'idx_order_outbox_expired_leases'
        ]) AS idx_name
    LOOP
        IF to_regclass(format('public.%I', r.idx_name)) IS NULL THEN
            RAISE EXCEPTION 'Missing expected index: public.%', r.idx_name;
        END IF;
    END LOOP;

    SELECT pg_get_expr(indpred, indrelid) INTO pred
    FROM pg_index WHERE indexrelid = 'public.idx_order_outbox_pending'::regclass;
    IF pred IS NULL OR pred NOT LIKE '%''pending''%' THEN
        RAISE EXCEPTION 'idx_order_outbox_pending predicate mismatch: %', pred;
    END IF;

    SELECT pg_get_expr(indpred, indrelid) INTO pred
    FROM pg_index WHERE indexrelid = 'public.idx_order_outbox_expired_leases'::regclass;
    IF pred IS NULL OR pred NOT LIKE '%''processing''%' THEN
        RAISE EXCEPTION 'idx_order_outbox_expired_leases predicate mismatch: %', pred;
    END IF;

    -- 8. Supplier validation function and trigger
    IF to_regprocedure('public.check_supplier_is_active()') IS NULL THEN
        RAISE EXCEPTION 'Missing function public.check_supplier_is_active()';
    END IF;

    SELECT COUNT(*) INTO actual_count
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND event_object_table = 'supplier_products'
      AND trigger_name = 'prevent_inactive_supplier_association'
      AND action_timing = 'BEFORE'
      AND event_manipulation IN ('INSERT', 'UPDATE');
    IF actual_count <> 2 THEN
        RAISE EXCEPTION 'Expected BEFORE INSERT/UPDATE trigger prevent_inactive_supplier_association, found %', actual_count;
    END IF;
END;
$$;

-- 9. Behavioral tests (rolled back cleanly)
BEGIN;

DO $$
DECLARE
    v_cat_id BIGINT;
    v_prod_id BIGINT;
    v_user_id BIGINT;
    v_order_id BIGINT;
    v_active_sup_id BIGINT;
    v_inactive_sup_id BIGINT;
    v_line_total NUMERIC(20,2);
    v_rejected BOOLEAN := FALSE;
BEGIN
    INSERT INTO categories (name) VALUES ('__assert_cat__') RETURNING id INTO v_cat_id;
    INSERT INTO products (category_id, name, sku, price)
    VALUES (v_cat_id, '__assert_prod__', '__ASSERT_SKU__', 25.50) RETURNING id INTO v_prod_id;
    INSERT INTO users (name, email, password_hash)
    VALUES ('__assert_user__', '__assert__@example.com', 'hash') RETURNING id INTO v_user_id;
    INSERT INTO orders (user_id, total_amount)
    VALUES (v_user_id, 76.50) RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, product_name, sku, unit_price, quantity)
    VALUES (v_order_id, v_prod_id, '__assert_prod__', '__ASSERT_SKU__', 25.50, 3)
    RETURNING line_total INTO v_line_total;
    IF v_line_total <> 76.50 THEN
        RAISE EXCEPTION 'order_items.line_total computed %, expected 76.50', v_line_total;
    END IF;

    INSERT INTO suppliers (name, email, is_active)
    VALUES ('__assert_active_sup__', 'active@example.com', TRUE) RETURNING id INTO v_active_sup_id;
    INSERT INTO suppliers (name, email, is_active)
    VALUES ('__assert_inactive_sup__', 'inactive@example.com', FALSE) RETURNING id INTO v_inactive_sup_id;

    INSERT INTO supplier_products (supplier_id, product_id) VALUES (v_active_sup_id, v_prod_id);

    BEGIN
        INSERT INTO supplier_products (supplier_id, product_id) VALUES (v_inactive_sup_id, v_prod_id);
    EXCEPTION WHEN check_violation THEN
        v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'Trigger allowed INSERT of inactive supplier association';
    END IF;

    v_rejected := FALSE;
    BEGIN
        UPDATE supplier_products SET supplier_id = v_inactive_sup_id
        WHERE supplier_id = v_active_sup_id AND product_id = v_prod_id;
    EXCEPTION WHEN check_violation THEN
        v_rejected := TRUE;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'Trigger allowed UPDATE to inactive supplier association';
    END IF;
END;
$$;

ROLLBACK;
