-- ============================================================================
-- 04_verify_assertions.sql
-- Strict structural verification of the schema created by 03_schema.sql.
--
-- Run with:  psql -v ON_ERROR_STOP=1 -f dbms/04_verify_assertions.sql
-- Any mismatch raises "Schema verification FAILED ..." so psql exits non-zero.
--
-- How it works
--   1. A reference copy of the expected schema (tables, columns, types,
--      nullability, defaults, CHECK/UNIQUE/PK definitions, indexes, generated
--      column) is built in a scratch schema `expected_snapshot`. It is written
--      from the project's schema checklist and contains no FKs or triggers.
--   2. Both schemas are described with the SAME catalog queries
--      (format_type, pg_get_expr, pg_get_constraintdef, pg_get_indexdef) and
--      compared exactly, in both directions. PostgreSQL deparses both sides
--      identically, so a constraint with the right name but a weakened or
--      altered expression, a wrong index predicate, a wrong type/default/
--      nullability, an extra column, or an extra table all fail.
--   3. Foreign keys, primary/unique key columns, global totals, the trigger
--      definition, and cardinality-relevant nullability are asserted directly
--      from the catalogs.
--   4. A behavioural test proves the trigger rejects inactive suppliers and
--      accepts active ones; it runs in a sub-transaction that is rolled back.
-- ============================================================================

SET client_min_messages = warning;

-- ---------------------------------------------------------------------------
-- Session-local helpers (dropped automatically when the session ends)
-- ---------------------------------------------------------------------------

-- TRUE/FALSE = column NOT NULL flag; NULL when the column does not exist.
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

-- Ordered, comma-separated list of the plain columns of an index.
CREATE FUNCTION pg_temp.idx_cols(idx regclass) RETURNS text
LANGUAGE sql AS $$
    SELECT string_agg(a.attname::text, ',' ORDER BY k.ord)
    FROM pg_index i
    CROSS JOIN LATERAL unnest(i.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
    WHERE i.indexrelid = idx
$$;

-- Deparsed partial-index predicate (NULL when the index is not partial).
CREATE FUNCTION pg_temp.idx_pred(idx regclass) RETURNS text
LANGUAGE sql AS $$
    SELECT pg_get_expr(i.indpred, i.indrelid)
    FROM pg_index i
    WHERE i.indexrelid = idx
$$;

-- Describes the structure of every ordinary table in schema `s` as rows of
-- (kind, table, item). Used to compare the real schema with the reference.
CREATE FUNCTION pg_temp.snap(s text) RETURNS TABLE(kind text, tbl text, item text)
LANGUAGE sql AS $$
    SELECT 'table'::text, c.relname::text, ''::text
    FROM pg_class c
    WHERE c.relnamespace = to_regnamespace(s) AND c.relkind = 'r'
  UNION ALL
    SELECT 'column', c.relname::text,
           a.attname::text
           || ' | type=' || format_type(a.atttypid, a.atttypmod)
           || ' | notnull=' || a.attnotnull::text
           || ' | generated=' || a.attgenerated::text
           || ' | default=' || coalesce(replace(pg_get_expr(d.adbin, d.adrelid), s || '.', ''), '')
    FROM pg_class c
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE c.relnamespace = to_regnamespace(s) AND c.relkind = 'r'
  UNION ALL
    SELECT 'constraint', c.relname::text,
           k.conname::text || ' | ' || k.contype::text || ' | '
           || replace(pg_get_constraintdef(k.oid), s || '.', '')
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    WHERE c.relnamespace = to_regnamespace(s) AND k.contype IN ('c', 'u', 'p')
  UNION ALL
    SELECT 'index', t.relname::text,
           replace(pg_get_indexdef(i.indexrelid), s || '.', '')
    FROM pg_index i
    JOIN pg_class t ON t.oid = i.indrelid
    WHERE t.relnamespace = to_regnamespace(s)
$$;

-- ---------------------------------------------------------------------------
-- Reference schema (expected structure; no FKs, no triggers)
-- ---------------------------------------------------------------------------
DROP SCHEMA IF EXISTS expected_snapshot CASCADE;
CREATE SCHEMA expected_snapshot;
SET search_path = expected_snapshot, public;

CREATE TABLE categories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'customer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    category_id BIGINT NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    sku VARCHAR(100) NOT NULL UNIQUE,
    price NUMERIC(10, 2) NOT NULL,
    low_stock_threshold INTEGER DEFAULT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT products_low_stock_threshold_non_negative
        CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0)
);

CREATE TABLE inventory (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE suppliers (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    contact_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(30),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT suppliers_name_not_empty CHECK (BTRIM(name) <> ''),
    CONSTRAINT suppliers_contact_required CHECK (
        (email IS NOT NULL AND BTRIM(email) <> '') OR
        (phone IS NOT NULL AND BTRIM(phone) <> '')
    )
);

CREATE TABLE supplier_products (
    supplier_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    CONSTRAINT supplier_products_pkey PRIMARY KEY (supplier_id, product_id)
);
CREATE INDEX supplier_products_product_id_idx
    ON supplier_products (product_id);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'placed',
    total_amount NUMERIC(22, 2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT orders_total_amount_nonnegative CHECK (total_amount >= 0),
    CONSTRAINT orders_status_check CHECK (status IN ('placed', 'processing', 'completed', 'cancelled'))
);
CREATE INDEX idx_orders_user_created
    ON orders (user_id, created_at);

CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(200) NOT NULL,
    sku VARCHAR(100),
    unit_price NUMERIC(10, 2) NOT NULL,
    quantity INTEGER NOT NULL,
    line_total NUMERIC(20, 2) GENERATED ALWAYS AS (unit_price * quantity) STORED,
    CONSTRAINT order_items_quantity_positive CHECK (quantity > 0),
    CONSTRAINT order_items_price_nonnegative CHECK (unit_price >= 0),
    CONSTRAINT order_items_unique_product UNIQUE (order_id, product_id)
);
CREATE INDEX idx_order_items_product
    ON order_items (product_id);

CREATE TABLE inventory_transactions (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL,
    performed_by BIGINT,
    order_id BIGINT,
    transaction_type VARCHAR(10) NOT NULL CHECK (transaction_type IN ('increase', 'decrease')),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    quantity_before INTEGER NOT NULL CHECK (quantity_before >= 0),
    quantity_after INTEGER NOT NULL CHECK (quantity_after >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_transaction_quantity CHECK (
        (
            transaction_type = 'increase'
            AND quantity_after::BIGINT = quantity_before::BIGINT + quantity::BIGINT
        )
        OR
        (
            transaction_type = 'decrease'
            AND quantity_after::BIGINT = quantity_before::BIGINT - quantity::BIGINT
        )
    ),
    CONSTRAINT inventory_order_decrease_only
        CHECK (order_id IS NULL OR transaction_type = 'decrease')
);
CREATE INDEX idx_inventory_transactions_product_created
    ON inventory_transactions (product_id, created_at DESC);
CREATE INDEX idx_inventory_transactions_order
    ON inventory_transactions (order_id);

CREATE TABLE order_outbox (
    id BIGSERIAL PRIMARY KEY,
    event_type VARCHAR(80) NOT NULL,
    order_id BIGINT NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    available_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    locked_until TIMESTAMPTZ,
    claim_token UUID,
    last_error TEXT,
    dispatched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT order_outbox_status_check CHECK (status IN ('pending', 'processing', 'dispatched')),
    CONSTRAINT order_outbox_attempts_nonnegative CHECK (attempts >= 0),
    CONSTRAINT order_outbox_unique_event_per_order UNIQUE (event_type, order_id)
);
CREATE INDEX idx_order_outbox_pending
    ON order_outbox (status, available_at, id)
    WHERE status = 'pending';
CREATE INDEX idx_order_outbox_expired_leases
    ON order_outbox (locked_until)
    WHERE status = 'processing';

CREATE TABLE receipts (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL UNIQUE,
    receipt_number VARCHAR(40) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    total_amount NUMERIC(22, 2) NOT NULL,
    items JSONB NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT receipts_total_nonnegative CHECK (total_amount >= 0),
    CONSTRAINT receipts_items_array_check CHECK (jsonb_typeof(items) = 'array')
);

RESET search_path;
RESET client_min_messages;

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    errs     text[] := ARRAY[]::text[];
    r        record;
    n        integer;
    v_text   text;
    v_text2  text;
    v_trg    record;
    v_func   oid;
    v_cat    bigint;
    v_prod   bigint;
    v_sup_a  bigint;
    v_sup_i  bigint;
BEGIN
    ---------------------------------------------------------------------
    -- 1. Exact structure: tables, columns (type, nullability, default,
    --    generated), CHECK / UNIQUE / PRIMARY KEY definitions, and every
    --    index (columns, order, uniqueness, DESC, partial predicate).
    --    Compared in both directions against the reference schema.
    ---------------------------------------------------------------------
    FOR r IN
        SELECT kind, tbl, item FROM (
            SELECT * FROM pg_temp.snap('public')
            EXCEPT
            SELECT * FROM pg_temp.snap('expected_snapshot')
        ) x ORDER BY 1, 2, 3
    LOOP
        errs := errs || format('unexpected or altered %s on %s: %s', r.kind, r.tbl, r.item);
    END LOOP;

    FOR r IN
        SELECT kind, tbl, item FROM (
            SELECT * FROM pg_temp.snap('expected_snapshot')
            EXCEPT
            SELECT * FROM pg_temp.snap('public')
        ) x ORDER BY 1, 2, 3
    LOOP
        errs := errs || format('expected but missing/different %s on %s: %s', r.kind, r.tbl, r.item);
    END LOOP;

    ---------------------------------------------------------------------
    -- 2. Global totals
    ---------------------------------------------------------------------
    SELECT count(*) INTO n
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    IF n <> 11 THEN errs := errs || format('expected exactly 11 tables in public, found %s', n); END IF;

    SELECT count(*) INTO n FROM pg_constraint
    WHERE contype = 'p' AND connamespace = 'public'::regnamespace;
    IF n <> 11 THEN errs := errs || format('expected exactly 11 primary keys, found %s', n); END IF;

    SELECT count(*) INTO n FROM pg_constraint
    WHERE contype = 'f' AND connamespace = 'public'::regnamespace;
    IF n <> 13 THEN errs := errs || format('expected exactly 13 foreign keys, found %s', n); END IF;

    SELECT count(*) INTO n FROM pg_constraint
    WHERE contype = 'u' AND connamespace = 'public'::regnamespace;
    IF n <> 8 THEN errs := errs || format('expected exactly 8 alternate UNIQUE constraints, found %s', n); END IF;

    SELECT count(*) INTO n
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind = 'r'
      AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = 's';
    IF n <> 1 THEN errs := errs || format('expected exactly 1 STORED generated column, found %s', n); END IF;

    ---------------------------------------------------------------------
    -- 3. Primary keys and alternate unique keys: right table, right columns,
    --    right order, together in ONE constraint (composite keys).
    ---------------------------------------------------------------------
    FOR r IN
        SELECT * FROM (VALUES
            ('categories',             'p', 'id'),
            ('users',                  'p', 'id'),
            ('products',               'p', 'id'),
            ('inventory',              'p', 'id'),
            ('suppliers',              'p', 'id'),
            ('supplier_products',      'p', 'supplier_id,product_id'),
            ('orders',                 'p', 'id'),
            ('order_items',            'p', 'id'),
            ('inventory_transactions', 'p', 'id'),
            ('order_outbox',           'p', 'id'),
            ('receipts',               'p', 'id'),
            ('users',                  'u', 'email'),
            ('categories',             'u', 'name'),
            ('products',               'u', 'sku'),
            ('inventory',              'u', 'product_id'),
            ('order_items',            'u', 'order_id,product_id'),
            ('order_outbox',           'u', 'event_type,order_id'),
            ('receipts',               'u', 'order_id'),
            ('receipts',               'u', 'receipt_number')
        ) AS v(tbl, ctype, cols)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM (
                SELECT c.oid,
                       string_agg(a.attname::text, ',' ORDER BY k.ord) AS cols
                FROM pg_constraint c
                CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                WHERE c.conrelid = to_regclass('public.' || r.tbl)
                  AND c.contype = r.ctype::"char"
                GROUP BY c.oid
            ) s
            WHERE s.cols = r.cols
        ) THEN
            errs := errs || format('missing %s key on %s(%s)',
                                   CASE r.ctype WHEN 'p' THEN 'PRIMARY' ELSE 'UNIQUE' END,
                                   r.tbl, r.cols);
        END IF;
    END LOOP;

    ---------------------------------------------------------------------
    -- 4. Foreign keys: child column, parent table + column (id), ON DELETE
    --    action, ON UPDATE NO ACTION, not deferrable.
    --    confdeltype: a=NO ACTION r=RESTRICT c=CASCADE n=SET NULL
    ---------------------------------------------------------------------
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
            JOIN pg_class cl ON cl.oid = c.conrelid AND cl.relnamespace = 'public'::regnamespace
            JOIN pg_class pr ON pr.oid = c.confrelid
            JOIN pg_attribute a  ON a.attrelid  = c.conrelid  AND a.attnum  = c.conkey[1]
            JOIN pg_attribute fa ON fa.attrelid = c.confrelid AND fa.attnum = c.confkey[1]
            WHERE c.contype = 'f'
              AND array_length(c.conkey, 1) = 1
              AND array_length(c.confkey, 1) = 1
              AND cl.relname = r.child
              AND a.attname  = r.col
              AND pr.relname = r.parent
              AND fa.attname = 'id'
              AND c.confdeltype = r.del_action::"char"
              AND c.confupdtype = 'a'
              AND NOT c.condeferrable
        ) THEN
            errs := errs || format('missing/incorrect FK: %s.%s -> %s.id (ON DELETE code %s, ON UPDATE NO ACTION)',
                                   r.child, r.col, r.parent, r.del_action);
        END IF;
    END LOOP;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE contype = 'f' AND conname = 'fk_inventory_transactions_order'
          AND conrelid = to_regclass('public.inventory_transactions')
    ) THEN
        errs := errs || 'missing named FK fk_inventory_transactions_order on inventory_transactions';
    END IF;

    ---------------------------------------------------------------------
    -- 5. Partial outbox indexes, asserted explicitly (in addition to the
    --    exact index comparison in section 1): indexed columns in order and
    --    the full predicate compared as a whole expression, not by substring.
    ---------------------------------------------------------------------
    v_text := pg_temp.idx_cols(to_regclass('public.idx_order_outbox_pending'));
    IF v_text IS DISTINCT FROM 'status,available_at,id' THEN
        errs := errs || format('idx_order_outbox_pending columns must be (status, available_at, id), found (%s)', coalesce(v_text, 'missing'));
    END IF;
    v_text  := pg_temp.idx_pred(to_regclass('public.idx_order_outbox_pending'));
    v_text2 := pg_temp.idx_pred(to_regclass('expected_snapshot.idx_order_outbox_pending'));
    IF v_text IS NULL OR v_text IS DISTINCT FROM v_text2 THEN
        errs := errs || format('idx_order_outbox_pending predicate must be exactly status = ''pending'' (found: %s, expected: %s)', coalesce(v_text, 'none'), coalesce(v_text2, 'none'));
    END IF;

    v_text := pg_temp.idx_cols(to_regclass('public.idx_order_outbox_expired_leases'));
    IF v_text IS DISTINCT FROM 'locked_until' THEN
        errs := errs || format('idx_order_outbox_expired_leases columns must be (locked_until), found (%s)', coalesce(v_text, 'missing'));
    END IF;
    v_text  := pg_temp.idx_pred(to_regclass('public.idx_order_outbox_expired_leases'));
    v_text2 := pg_temp.idx_pred(to_regclass('expected_snapshot.idx_order_outbox_expired_leases'));
    IF v_text IS NULL OR v_text IS DISTINCT FROM v_text2 THEN
        errs := errs || format('idx_order_outbox_expired_leases predicate must be exactly status = ''processing'' (found: %s, expected: %s)', coalesce(v_text, 'none'), coalesce(v_text2, 'none'));
    END IF;

    ---------------------------------------------------------------------
    -- 6. Trigger: name, table, timing, events, columns, function, enabled
    --    tgtype bits: 1=ROW 2=BEFORE 4=INSERT 8=DELETE 16=UPDATE
    --    expected: ROW + BEFORE + INSERT + UPDATE = 23
    ---------------------------------------------------------------------
    SELECT count(*) INTO n
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relnamespace = 'public'::regnamespace AND NOT t.tgisinternal;
    IF n <> 1 THEN errs := errs || format('expected exactly 1 application trigger, found %s', n); END IF;

    SELECT p.oid INTO v_func
    FROM pg_proc p
    WHERE p.proname = 'check_supplier_is_active'
      AND p.pronamespace = 'public'::regnamespace;

    SELECT t.tgenabled, t.tgtype, t.tgfoid, (t.tgqual IS NULL) AS no_when,
           (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
              FROM unnest(t.tgattr::int2[]) AS u(attnum)
              JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = u.attnum) AS upd_cols
    INTO v_trg
    FROM pg_trigger t
    WHERE t.tgname = 'prevent_inactive_supplier_association'
      AND t.tgrelid = to_regclass('public.supplier_products')
      AND NOT t.tgisinternal;

    IF NOT FOUND THEN
        errs := errs || 'missing trigger prevent_inactive_supplier_association on supplier_products';
    ELSE
        IF v_trg.tgenabled <> 'O' THEN
            errs := errs || format('trigger prevent_inactive_supplier_association is not enabled (tgenabled=%s)', v_trg.tgenabled);
        END IF;
        IF v_trg.tgtype <> 23 THEN
            errs := errs || format('trigger must be BEFORE INSERT OR UPDATE ... FOR EACH ROW (tgtype 23), found tgtype=%s', v_trg.tgtype);
        END IF;
        IF v_trg.upd_cols IS DISTINCT FROM 'product_id,supplier_id' THEN
            errs := errs || format('trigger must be UPDATE OF supplier_id, product_id, found: %s', coalesce(v_trg.upd_cols, 'no column list'));
        END IF;
        IF v_trg.tgfoid IS DISTINCT FROM v_func THEN
            errs := errs || 'trigger does not execute function check_supplier_is_active()';
        END IF;
        IF NOT v_trg.no_when THEN
            errs := errs || 'trigger must not have a WHEN condition';
        END IF;
    END IF;

    ---------------------------------------------------------------------
    -- 7. Generated column: STORED and exactly unit_price * quantity
    --    (the expression itself is compared in section 1; checked here too)
    ---------------------------------------------------------------------
    SELECT a.attgenerated::text, pg_get_expr(d.adbin, d.adrelid)
    INTO v_text, v_text2
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = to_regclass('public.order_items')
      AND a.attname = 'line_total' AND NOT a.attisdropped;
    IF NOT FOUND THEN
        errs := errs || 'missing column order_items.line_total';
    ELSIF v_text IS DISTINCT FROM 's' THEN
        errs := errs || format('order_items.line_total is not STORED generated (attgenerated=%L)', v_text);
    ELSIF v_text2 IS DISTINCT FROM (
            SELECT pg_get_expr(d.adbin, d.adrelid)
            FROM pg_attribute a
            JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
            WHERE a.attrelid = to_regclass('expected_snapshot.order_items')
              AND a.attname = 'line_total') THEN
        errs := errs || format('order_items.line_total expression must be unit_price * quantity, found: %s', v_text2);
    END IF;

    ---------------------------------------------------------------------
    -- 8. Cardinality-relevant nullability / uniqueness of FK columns
    ---------------------------------------------------------------------
    IF pg_temp.col_not_null('inventory', 'product_id') IS DISTINCT FROM true THEN
        errs := errs || 'inventory.product_id must be NOT NULL';
    END IF;
    IF pg_temp.col_is_unique('inventory', 'product_id') IS DISTINCT FROM true THEN
        errs := errs || 'inventory.product_id must be UNIQUE';
    END IF;
    IF pg_temp.col_not_null('receipts', 'order_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.order_id must be NOT NULL';
    END IF;
    IF pg_temp.col_is_unique('receipts', 'order_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.order_id must be UNIQUE';
    END IF;
    IF pg_temp.col_not_null('receipts', 'user_id') IS DISTINCT FROM true THEN
        errs := errs || 'receipts.user_id must be NOT NULL';
    END IF;
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
    -- 9. Trigger behaviour: an active supplier can be associated with a
    --    product; an inactive one cannot (INSERT and UPDATE paths).
    --    Runs in a sub-transaction that is always rolled back, so no data
    --    is left behind. Skipped if the structure is already wrong.
    ---------------------------------------------------------------------
    IF array_length(errs, 1) IS NULL THEN
        BEGIN
            INSERT INTO categories (name) VALUES ('zz_verify_probe_category') RETURNING id INTO v_cat;
            INSERT INTO products (category_id, name, sku, price)
                VALUES (v_cat, 'zz verify probe', 'ZZ-VERIFY-PROBE', 1.00) RETURNING id INTO v_prod;
            INSERT INTO suppliers (name, email, is_active)
                VALUES ('zz active supplier', 'active@probe.invalid', TRUE) RETURNING id INTO v_sup_a;
            INSERT INTO suppliers (name, email, is_active)
                VALUES ('zz inactive supplier', 'inactive@probe.invalid', FALSE) RETURNING id INTO v_sup_i;

            -- active supplier: must succeed (an error here is caught below)
            INSERT INTO supplier_products (supplier_id, product_id) VALUES (v_sup_a, v_prod);

            -- inactive supplier via INSERT: must be rejected with 23514
            BEGIN
                INSERT INTO supplier_products (supplier_id, product_id) VALUES (v_sup_i, v_prod);
                errs := errs || 'trigger allowed INSERT of a product for an inactive supplier';
            EXCEPTION WHEN SQLSTATE '23514' THEN
                NULL;
            END;

            -- inactive supplier via UPDATE of supplier_id: must be rejected with 23514
            BEGIN
                UPDATE supplier_products SET supplier_id = v_sup_i
                WHERE supplier_id = v_sup_a AND product_id = v_prod;
                errs := errs || 'trigger allowed UPDATE moving a product to an inactive supplier';
            EXCEPTION WHEN SQLSTATE '23514' THEN
                NULL;
            END;

            RAISE EXCEPTION 'probe rollback' USING ERRCODE = 'XX999';
        EXCEPTION
            WHEN SQLSTATE 'XX999' THEN
                NULL;  -- normal path: everything above is rolled back
            WHEN OTHERS THEN
                errs := errs || format('trigger behavioural test errored: %s (SQLSTATE %s)', SQLERRM, SQLSTATE);
        END;
    END IF;

    ---------------------------------------------------------------------
    -- Result
    ---------------------------------------------------------------------
    IF array_length(errs, 1) IS NOT NULL THEN
        RAISE EXCEPTION E'Schema verification FAILED (% problem(s)):\n - %',
            array_length(errs, 1), array_to_string(errs, E'\n - ');
    END IF;

    RAISE NOTICE 'Schema verification PASSED: 11 tables, exact columns/types/defaults/nullability, 11 PKs, 8 alternate unique keys, 13 FKs, exact CHECK/index definitions, trigger definition and behaviour, stored generated column.';
END
$$;

DROP SCHEMA expected_snapshot CASCADE;