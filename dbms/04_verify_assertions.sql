-- ============================================================================
-- 04_verify_assertions.sql
-- Executable assertions for the schema created by 03_schema.sql.
-- Run with:  psql -v ON_ERROR_STOP=1 -f 04_verify_assertions.sql
-- Any mismatch raises an exception, so psql exits non-zero and CI fails.
-- All failures are collected and reported together in one exception message.
-- ============================================================================

-- Session-local helpers (dropped automatically when the session ends).
-- They return NULL when the column does not exist, so callers must compare
-- with IS DISTINCT FROM (a missing column then counts as a failure).
CREATE FUNCTION pg_temp.col_not_null(t text, c text) RETURNS boolean
LANGUAGE sql AS $$
    SELECT a.attnotnull
    FROM pg_attribute a
    WHERE a.attrelid = to_regclass('public.' || t)
      AND a.attname = c
      AND NOT a.attisdropped
$$;

-- TRUE when a single-column, non-partial UNIQUE/PK index exists on the column.
CREATE FUNCTION pg_temp.col_is_unique(t text, c text) RETURNS boolean
LANGUAGE sql AS $$
    SELECT EXISTS (
        SELECT 1
        FROM pg_index i
        JOIN pg_attribute a
          ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
        WHERE i.indrelid = to_regclass('public.' || t)
          AND i.indisunique
          AND i.indnatts = 1
          AND i.indpred IS NULL
          AND a.attname = c
    )
$$;

DO $$
DECLARE
    errs            text[] := ARRAY[]::text[];
    r               record;
    expected_tables text[] := ARRAY[
        'categories','users','products','inventory','suppliers',
        'supplier_products','orders','order_items',
        'inventory_transactions','order_outbox','receipts'
    ];
    t               text;
    n               integer;
    v_enabled       "char";
    v_gen           "char";
    v_pred          text;
BEGIN
    ---------------------------------------------------------------------
    -- 1. Tables: all 11 exist and there are exactly 11 in schema public
    ---------------------------------------------------------------------
    FOREACH t IN ARRAY expected_tables LOOP
        IF to_regclass('public.' || t) IS NULL THEN
            errs := errs || format('missing table: %s', t);
        END IF;
    END LOOP;

    SELECT count(*) INTO n
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    IF n <> 11 THEN
        errs := errs || format('expected exactly 11 tables in public, found %s', n);
    END IF;

    ---------------------------------------------------------------------
    -- 2. Foreign keys: exactly 13, and each expected one is present
    --    (child table, child column, parent table, ON DELETE action)
    --    confdeltype: a=NO ACTION r=RESTRICT c=CASCADE n=SET NULL
    ---------------------------------------------------------------------
    SELECT count(*) INTO n
    FROM pg_constraint
    WHERE contype = 'f' AND connamespace = 'public'::regnamespace;
    IF n <> 13 THEN
        errs := errs || format('expected exactly 13 foreign keys, found %s', n);
    END IF;

    FOR r IN
        SELECT * FROM (VALUES
            ('products',               'category_id',  'categories', 'r'),
            ('inventory',              'product_id',   'products',   'r'),
            ('supplier_products',      'supplier_id',  'suppliers',  'r'),
            ('supplier_products',      'product_id',   'products',   'r'),
            ('orders',                 'user_id',      'users',      'r'),
            ('order_items',            'order_id',     'orders',     'c'),
            ('order_items',            'product_id',   'products',   'r'),
            ('inventory_transactions', 'product_id',   'products',   'r'),
            ('inventory_transactions', 'performed_by', 'users',      'n'),
            ('inventory_transactions', 'order_id',     'orders',     'r'),
            ('order_outbox',           'order_id',     'orders',     'c'),
            ('receipts',               'order_id',     'orders',     'r'),
            ('receipts',               'user_id',      'users',      'r')
        ) AS v(child, col, parent, del_action)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint c
            JOIN pg_class cl ON cl.oid = c.conrelid
            JOIN pg_class pr ON pr.oid = c.confrelid
            JOIN pg_attribute a
              ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
            WHERE c.contype = 'f'
              AND c.connamespace = 'public'::regnamespace
              AND array_length(c.conkey, 1) = 1
              AND cl.relname = r.child
              AND a.attname  = r.col
              AND pr.relname = r.parent
              AND c.confdeltype = r.del_action::"char"
        ) THEN
            errs := errs || format('missing/incorrect FK: %s.%s -> %s (ON DELETE code %s)',
                                   r.child, r.col, r.parent, r.del_action);
        END IF;
    END LOOP;

    ---------------------------------------------------------------------
    -- 3. Trigger prevent_inactive_supplier_association exists and is enabled
    --    tgenabled: O = enabled (origin/local), D = disabled
    ---------------------------------------------------------------------
    SELECT tgenabled INTO v_enabled
    FROM pg_trigger
    WHERE tgname = 'prevent_inactive_supplier_association'
      AND tgrelid = to_regclass('public.supplier_products')
      AND NOT tgisinternal;
    IF NOT FOUND THEN
        errs := errs || 'missing trigger prevent_inactive_supplier_association on supplier_products';
    ELSIF v_enabled <> 'O' THEN
        errs := errs || format('trigger prevent_inactive_supplier_association is not enabled (tgenabled=%s)', v_enabled);
    END IF;

    ---------------------------------------------------------------------
    -- 4. order_items.line_total is a STORED generated column
    --    attgenerated: s = stored, v = virtual
    ---------------------------------------------------------------------
    SELECT attgenerated INTO v_gen
    FROM pg_attribute
    WHERE attrelid = to_regclass('public.order_items')
      AND attname = 'line_total'
      AND NOT attisdropped;
    IF NOT FOUND THEN
        errs := errs || 'missing column order_items.line_total';
    ELSIF v_gen <> 's' THEN
        errs := errs || format('order_items.line_total is not a stored generated column (attgenerated=%L)', v_gen);
    END IF;

    ---------------------------------------------------------------------
    -- 5a. Named constraints
    ---------------------------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
            ('products',               'products_low_stock_threshold_non_negative'),
            ('suppliers',              'suppliers_name_not_empty'),
            ('suppliers',              'suppliers_contact_required'),
            ('supplier_products',      'supplier_products_pkey'),
            ('orders',                 'orders_total_amount_nonnegative'),
            ('orders',                 'orders_status_check'),
            ('order_items',            'order_items_quantity_positive'),
            ('order_items',            'order_items_price_nonnegative'),
            ('order_items',            'order_items_unique_product'),
            ('inventory_transactions', 'valid_transaction_quantity'),
            ('inventory_transactions', 'fk_inventory_transactions_order'),
            ('inventory_transactions', 'inventory_order_decrease_only'),
            ('order_outbox',           'order_outbox_status_check'),
            ('order_outbox',           'order_outbox_attempts_nonnegative'),
            ('order_outbox',           'order_outbox_unique_event_per_order'),
            ('receipts',               'receipts_total_nonnegative'),
            ('receipts',               'receipts_items_array_check')
        ) AS v(tbl, conname)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = to_regclass('public.' || r.tbl)
              AND conname  = r.conname
        ) THEN
            errs := errs || format('missing constraint %s on %s', r.conname, r.tbl);
        END IF;
    END LOOP;

    ---------------------------------------------------------------------
    -- 5b. Named indexes
    ---------------------------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
            ('supplier_products',      'supplier_products_product_id_idx'),
            ('orders',                 'idx_orders_user_created'),
            ('order_items',            'idx_order_items_product'),
            ('inventory_transactions', 'idx_inventory_transactions_product_created'),
            ('inventory_transactions', 'idx_inventory_transactions_order'),
            ('order_outbox',           'idx_order_outbox_pending'),
            ('order_outbox',           'idx_order_outbox_expired_leases')
        ) AS v(tbl, idxname)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_indexes
            WHERE schemaname = 'public'
              AND tablename  = r.tbl
              AND indexname  = r.idxname
        ) THEN
            errs := errs || format('missing index %s on %s', r.idxname, r.tbl);
        END IF;
    END LOOP;

    -- 5c. The two outbox indexes must be PARTIAL with the right predicates
    SELECT pg_get_expr(i.indpred, i.indrelid) INTO v_pred
    FROM pg_index i
    JOIN pg_class ic ON ic.oid = i.indexrelid
    WHERE ic.relname = 'idx_order_outbox_pending'
      AND ic.relnamespace = 'public'::regnamespace;
    IF v_pred IS NULL OR position('pending' IN v_pred) = 0 THEN
        errs := errs || format('idx_order_outbox_pending is not a partial index on status = pending (predicate: %s)', coalesce(v_pred, 'none'));
    END IF;

    SELECT pg_get_expr(i.indpred, i.indrelid) INTO v_pred
    FROM pg_index i
    JOIN pg_class ic ON ic.oid = i.indexrelid
    WHERE ic.relname = 'idx_order_outbox_expired_leases'
      AND ic.relnamespace = 'public'::regnamespace;
    IF v_pred IS NULL OR position('processing' IN v_pred) = 0 THEN
        errs := errs || format('idx_order_outbox_expired_leases is not a partial index on status = processing (predicate: %s)', coalesce(v_pred, 'none'));
    END IF;

    ---------------------------------------------------------------------
    -- 6. Nullability / uniqueness of the cardinality-relevant FK columns
    ---------------------------------------------------------------------
    -- inventory.product_id: mandatory + unique  => products 1 : 0..1 inventory
    IF pg_temp.col_not_null('inventory', 'product_id') IS DISTINCT FROM true THEN
        errs := errs || 'inventory.product_id must be NOT NULL';
    END IF;
    IF pg_temp.col_is_unique('inventory', 'product_id') IS DISTINCT FROM true THEN
        errs := errs || 'inventory.product_id must be UNIQUE';
    END IF;

    -- receipts.order_id: mandatory + unique  => orders 1 : 0..1 receipts
    IF pg_temp.col_not_null('receipts', 'order_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.order_id must be NOT NULL';
    END IF;
    IF pg_temp.col_is_unique('receipts', 'order_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.order_id must be UNIQUE';
    END IF;

    -- receipts.user_id: mandatory, not unique
    IF pg_temp.col_not_null('receipts', 'user_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.user_id must be NOT NULL';
    END IF;

    -- inventory_transactions.performed_by / order_id: nullable, not unique
    IF pg_temp.col_not_null('inventory_transactions', 'performed_by') IS DISTINCT FROM false THEN
        errs := errs || 'inventory_transactions.performed_by must be nullable';
    END IF;
    IF pg_temp.col_is_unique('inventory_transactions', 'performed_by') THEN
        errs := errs || 'inventory_transactions.performed_by must not be UNIQUE';
    END IF;
    IF pg_temp.col_not_null('inventory_transactions', 'order_id') IS DISTINCT FROM false THEN
        errs := errs || 'inventory_transactions.order_id must be nullable';
    END IF;
    IF pg_temp.col_is_unique('inventory_transactions', 'order_id') THEN
        errs := errs || 'inventory_transactions.order_id must not be UNIQUE';
    END IF;

    ---------------------------------------------------------------------
    -- Result
    ---------------------------------------------------------------------
    IF array_length(errs, 1) IS NOT NULL THEN
        RAISE EXCEPTION E'Schema verification FAILED (% problem(s)):\n - %',
            array_length(errs, 1), array_to_string(errs, E'\n - ');
    END IF;

    RAISE NOTICE 'Schema verification PASSED: 11 tables, 13 foreign keys, trigger, generated column, constraints, indexes, and FK cardinalities all as expected.';
END
$$;