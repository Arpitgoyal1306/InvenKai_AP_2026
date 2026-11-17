-- ============================================================
-- InvenKai Database Schema
-- Database: PostgreSQL
-- Source: InvenKai application migrations
-- ============================================================

BEGIN;

-- 1. Categories
CREATE TABLE categories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 2. Users
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'customer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Suppliers
CREATE TABLE suppliers (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    contact_name VARCHAR(100),
    email VARCHAR(255),
    phone VARCHAR(30),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT suppliers_name_not_empty
        CHECK (BTRIM(name) <> ''),

    CONSTRAINT suppliers_contact_required
        CHECK (
            (email IS NOT NULL AND BTRIM(email) <> '')
            OR
            (phone IS NOT NULL AND BTRIM(phone) <> '')
        )
);

-- 4. Products
CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    category_id BIGINT NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    sku VARCHAR(100) NOT NULL UNIQUE,
    price NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    low_stock_threshold INTEGER DEFAULT NULL,

    CONSTRAINT products_category_fk
        FOREIGN KEY (category_id)
        REFERENCES categories(id)
        ON DELETE RESTRICT,

    CONSTRAINT products_low_stock_threshold_non_negative
        CHECK (
            low_stock_threshold IS NULL
            OR low_stock_threshold >= 0
        )
);

-- 5. Inventory
CREATE TABLE inventory (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL UNIQUE,
    quantity INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT inventory_product_fk
        FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT,

    CONSTRAINT inventory_quantity_check
        CHECK (quantity >= 0)
);

-- 6. Orders
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'placed',
    total_amount NUMERIC(22,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT orders_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT orders_status_check
        CHECK (status IN (
            'placed',
            'processing',
            'completed',
            'cancelled'
        )),

    CONSTRAINT orders_total_amount_nonnegative
        CHECK (total_amount >= 0)
);

-- 7. Inventory Transactions
CREATE TABLE inventory_transactions (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL,
    performed_by BIGINT,
    transaction_type VARCHAR(10) NOT NULL,
    quantity INTEGER NOT NULL,
    quantity_before INTEGER NOT NULL,
    quantity_after INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_id BIGINT,

    CONSTRAINT inventory_transactions_product_fk
        FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT,

    CONSTRAINT inventory_transactions_user_fk
        FOREIGN KEY (performed_by)
        REFERENCES users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_inventory_transactions_order
        FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE RESTRICT,

    CONSTRAINT inventory_transactions_type_check
        CHECK (transaction_type IN ('increase', 'decrease')),

    CONSTRAINT inventory_transactions_quantity_check
        CHECK (quantity > 0),

    CONSTRAINT inventory_transactions_before_check
        CHECK (quantity_before >= 0),

    CONSTRAINT inventory_transactions_after_check
        CHECK (quantity_after >= 0),

    CONSTRAINT valid_transaction_quantity
        CHECK (
            (
                transaction_type = 'increase'
                AND quantity_after::BIGINT =
                    quantity_before::BIGINT + quantity::BIGINT
            )
            OR
            (
                transaction_type = 'decrease'
                AND quantity_after::BIGINT =
                    quantity_before::BIGINT - quantity::BIGINT
            )
        ),

    CONSTRAINT inventory_order_decrease_only
        CHECK (
            order_id IS NULL
            OR transaction_type = 'decrease'
        )
);

-- 8. Supplier Products (many-to-many junction table)
CREATE TABLE supplier_products (
    supplier_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,

    CONSTRAINT supplier_products_pkey
        PRIMARY KEY (supplier_id, product_id),

    CONSTRAINT supplier_products_supplier_fk
        FOREIGN KEY (supplier_id)
        REFERENCES suppliers(id)
        ON DELETE RESTRICT,

    CONSTRAINT supplier_products_product_fk
        FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT
);

-- 9. Order Items
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    product_name VARCHAR(200) NOT NULL,
    sku VARCHAR(100),
    unit_price NUMERIC(10,2) NOT NULL,
    quantity INTEGER NOT NULL,

    line_total NUMERIC(20,2)
        GENERATED ALWAYS AS (unit_price * quantity) STORED,

    CONSTRAINT order_items_order_fk
        FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE CASCADE,

    CONSTRAINT order_items_product_fk
        FOREIGN KEY (product_id)
        REFERENCES products(id)
        ON DELETE RESTRICT,

    CONSTRAINT order_items_quantity_positive
        CHECK (quantity > 0),

    CONSTRAINT order_items_price_nonnegative
        CHECK (unit_price >= 0),

    CONSTRAINT order_items_unique_product
        UNIQUE (order_id, product_id)
);

-- 10. Order Outbox
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

    CONSTRAINT order_outbox_order_fk
        FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE CASCADE,

    CONSTRAINT order_outbox_status_check
        CHECK (status IN ('pending', 'processing', 'dispatched')),

    CONSTRAINT order_outbox_attempts_nonnegative
        CHECK (attempts >= 0),

    CONSTRAINT order_outbox_unique_event_per_order
        UNIQUE (event_type, order_id)
);

-- 11. Receipts
CREATE TABLE receipts (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL UNIQUE,
    receipt_number VARCHAR(40) NOT NULL UNIQUE,
    user_id BIGINT NOT NULL,
    total_amount NUMERIC(22,2) NOT NULL,
    items JSONB NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT receipts_order_fk
        FOREIGN KEY (order_id)
        REFERENCES orders(id)
        ON DELETE RESTRICT,

    CONSTRAINT receipts_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT receipts_total_nonnegative
        CHECK (total_amount >= 0),

    CONSTRAINT receipts_items_array_check
        CHECK (jsonb_typeof(items) = 'array')
);

-- ============================================================
-- Indexes declared by the application migrations
-- ============================================================

CREATE INDEX idx_inventory_transactions_product_created
    ON inventory_transactions (product_id, created_at DESC);

CREATE INDEX idx_inventory_transactions_order
    ON inventory_transactions (order_id);

CREATE INDEX idx_orders_user_created
    ON orders (user_id, created_at);

CREATE INDEX supplier_products_product_id_idx
    ON supplier_products (product_id);

CREATE INDEX idx_order_items_product
    ON order_items (product_id);

CREATE INDEX idx_order_outbox_pending
    ON order_outbox (status, available_at, id)
    WHERE status = 'pending';

CREATE INDEX idx_order_outbox_expired_leases
    ON order_outbox (locked_until)
    WHERE status = 'processing';

-- ============================================================
-- Supplier validation trigger
-- Prevents associations with inactive suppliers
-- ============================================================

CREATE OR REPLACE FUNCTION check_supplier_is_active()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    supplier_active BOOLEAN;
BEGIN
    SELECT is_active
    INTO supplier_active
    FROM suppliers
    WHERE id = NEW.supplier_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Supplier does not exist'
            USING ERRCODE = '23503';
    END IF;

    IF supplier_active = FALSE THEN
        RAISE EXCEPTION
            'Cannot associate a product with an inactive supplier'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER prevent_inactive_supplier_association
BEFORE INSERT OR UPDATE OF supplier_id, product_id
ON supplier_products
FOR EACH ROW
EXECUTE FUNCTION check_supplier_is_active();

COMMIT;

-- ============================================================
-- End of InvenKai schema
-- ============================================================
