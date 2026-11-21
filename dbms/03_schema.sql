-- InvenKai · 20 application migrations at 33b5bbe. Apply to an empty database.
BEGIN;

CREATE FUNCTION public.check_supplier_is_active() RETURNS trigger
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
        RAISE EXCEPTION 'Cannot associate a product with an inactive supplier'
          USING ERRCODE = '23514';
      END IF;

      RETURN NEW;
    END;
    $$;

CREATE FUNCTION public.notify_market_inventory() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  DECLARE owner_key text; public_change boolean; store_key bigint;
  BEGIN
    IF TG_TABLE_NAME = 'inventory' THEN
      SELECT s.owner_id::text, s.published AND NOT p.archived, s.id
        INTO owner_key,public_change,store_key FROM products p JOIN stores s ON s.id=p.store_id
        WHERE p.id=NEW.product_id;
    ELSIF TG_TABLE_NAME = 'products' THEN
      SELECT s.owner_id::text, s.published AND (NOT NEW.archived OR NOT OLD.archived), s.id
        INTO owner_key,public_change,store_key FROM stores s WHERE s.id=NEW.store_id;
    ELSE
      owner_key := NEW.owner_id::text; store_key := NEW.id;
      public_change := NEW.published OR OLD.published;
    END IF;
    IF store_key IS NOT NULL THEN
      PERFORM pg_notify('market_inventory', json_build_object('owner',owner_key,'public',public_change)::text);
    END IF;
    RETURN NEW;
  END $$;

CREATE TABLE public.categories (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);

CREATE SEQUENCE public.categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.categories_id_seq OWNED BY public.categories.id;

CREATE TABLE public.inventory (
    id bigint NOT NULL,
    product_id bigint NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT inventory_quantity_check CHECK ((quantity >= 0))
);

CREATE SEQUENCE public.inventory_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.inventory_id_seq OWNED BY public.inventory.id;

CREATE TABLE public.inventory_transactions (
    id bigint NOT NULL,
    product_id bigint NOT NULL,
    performed_by bigint,
    transaction_type character varying(10) NOT NULL,
    quantity integer NOT NULL,
    quantity_before integer NOT NULL,
    quantity_after integer NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    order_id bigint,
    CONSTRAINT inventory_order_decrease_only CHECK (((order_id IS NULL) OR ((transaction_type)::text = 'decrease'::text))),
    CONSTRAINT inventory_transactions_quantity_after_check CHECK ((quantity_after >= 0)),
    CONSTRAINT inventory_transactions_quantity_before_check CHECK ((quantity_before >= 0)),
    CONSTRAINT inventory_transactions_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT inventory_transactions_transaction_type_check CHECK (transaction_type IN ('increase', 'decrease')),
    CONSTRAINT valid_transaction_quantity CHECK (((((transaction_type)::text = 'increase'::text) AND ((quantity_after)::bigint = ((quantity_before)::bigint + (quantity)::bigint))) OR (((transaction_type)::text = 'decrease'::text) AND ((quantity_after)::bigint = ((quantity_before)::bigint - (quantity)::bigint)))))
);

CREATE SEQUENCE public.inventory_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.inventory_transactions_id_seq OWNED BY public.inventory_transactions.id;

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    order_id bigint NOT NULL,
    product_id bigint NOT NULL,
    product_name character varying(200) NOT NULL,
    sku character varying(100),
    unit_price numeric(10,2) NOT NULL,
    quantity integer NOT NULL,
    line_total numeric(20,2) GENERATED ALWAYS AS ((unit_price * (quantity)::numeric)) STORED,
    CONSTRAINT order_items_price_nonnegative CHECK ((unit_price >= (0)::numeric)),
    CONSTRAINT order_items_quantity_positive CHECK ((quantity > 0))
);

CREATE SEQUENCE public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;

CREATE TABLE public.order_outbox (
    id bigint NOT NULL,
    event_type character varying(80) NOT NULL,
    order_id bigint NOT NULL,
    payload jsonb NOT NULL,
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    available_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    locked_until timestamp with time zone,
    claim_token uuid,
    last_error text,
    dispatched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT order_outbox_attempts_nonnegative CHECK ((attempts >= 0)),
    CONSTRAINT order_outbox_status_check CHECK (status IN ('pending', 'processing', 'dispatched'))
);

CREATE SEQUENCE public.order_outbox_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.order_outbox_id_seq OWNED BY public.order_outbox.id;

CREATE TABLE public.orders (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    status character varying(20) DEFAULT 'placed'::character varying NOT NULL,
    total_amount numeric(22,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    store_id bigint,
    pickup_snapshot text,
    buyer_details jsonb,
    checkout_key character varying(128),
    checkout_fingerprint text,
    CONSTRAINT orders_status_check CHECK (status IN ('placed', 'processing', 'completed', 'cancelled')),
    CONSTRAINT orders_total_amount_nonnegative CHECK ((total_amount >= (0)::numeric))
);

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;

CREATE TABLE public.products (
    id bigint NOT NULL,
    category_id bigint NOT NULL,
    name character varying(200) NOT NULL,
    description text,
    sku character varying(100) NOT NULL,
    price numeric(10,2) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    low_stock_threshold integer,
    store_id bigint,
    archived boolean DEFAULT false NOT NULL,
    photo text DEFAULT ''::text NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT products_deleted_seller_archived CHECK (((deleted_at IS NULL) OR ((store_id IS NOT NULL) AND archived))),
    CONSTRAINT products_low_stock_threshold_non_negative CHECK (((low_stock_threshold IS NULL) OR (low_stock_threshold >= 0)))
);

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;

CREATE TABLE public.receipts (
    id bigint NOT NULL,
    order_id bigint NOT NULL,
    receipt_number character varying(40) NOT NULL,
    user_id bigint NOT NULL,
    total_amount numeric(22,2) NOT NULL,
    items jsonb NOT NULL,
    issued_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT receipts_items_array_check CHECK ((jsonb_typeof(items) = 'array'::text)),
    CONSTRAINT receipts_total_nonnegative CHECK ((total_amount >= (0)::numeric))
);

CREATE SEQUENCE public.receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.receipts_id_seq OWNED BY public.receipts.id;

CREATE TABLE public.stores (
    id bigint NOT NULL,
    owner_id bigint NOT NULL,
    name character varying(120) NOT NULL,
    slug character varying(68) NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    category character varying(100) NOT NULL,
    contact character varying(254) NOT NULL,
    pickup text NOT NULL,
    logo text DEFAULT ''::text NOT NULL,
    cover text DEFAULT ''::text NOT NULL,
    published boolean DEFAULT false NOT NULL,
    slug_locked boolean DEFAULT false NOT NULL
);

CREATE SEQUENCE public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.stores_id_seq OWNED BY public.stores.id;

CREATE TABLE public.supplier_products (
    supplier_id bigint NOT NULL,
    product_id bigint NOT NULL
);

CREATE TABLE public.suppliers (
    id bigint NOT NULL,
    name character varying(200) NOT NULL,
    contact_name character varying(100),
    email character varying(255),
    phone character varying(30),
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT suppliers_contact_required CHECK ((((email IS NOT NULL) AND (btrim((email)::text) <> ''::text)) OR ((phone IS NOT NULL) AND (btrim((phone)::text) <> ''::text)))),
    CONSTRAINT suppliers_name_not_empty CHECK ((btrim((name)::text) <> ''::text))
);

CREATE SEQUENCE public.suppliers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.suppliers_id_seq OWNED BY public.suppliers.id;

CREATE TABLE public.users (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255),
    role character varying(20) DEFAULT 'customer'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    phone character varying(28),
    pickup_address jsonb,
    google_subject text,
    avatar_url text,
    CONSTRAINT users_sign_in_method CHECK (((password_hash IS NOT NULL) OR (google_subject IS NOT NULL)))
);

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;

ALTER TABLE ONLY public.categories ALTER COLUMN id SET DEFAULT nextval('public.categories_id_seq'::regclass);

ALTER TABLE ONLY public.inventory ALTER COLUMN id SET DEFAULT nextval('public.inventory_id_seq'::regclass);

ALTER TABLE ONLY public.inventory_transactions ALTER COLUMN id SET DEFAULT nextval('public.inventory_transactions_id_seq'::regclass);

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);

ALTER TABLE ONLY public.order_outbox ALTER COLUMN id SET DEFAULT nextval('public.order_outbox_id_seq'::regclass);

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);

ALTER TABLE ONLY public.receipts ALTER COLUMN id SET DEFAULT nextval('public.receipts_id_seq'::regclass);

ALTER TABLE ONLY public.stores ALTER COLUMN id SET DEFAULT nextval('public.stores_id_seq'::regclass);

ALTER TABLE ONLY public.suppliers ALTER COLUMN id SET DEFAULT nextval('public.suppliers_id_seq'::regclass);

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_product_id_key UNIQUE (product_id);

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_unique_product UNIQUE (order_id, product_id);

ALTER TABLE ONLY public.order_outbox
    ADD CONSTRAINT order_outbox_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.order_outbox
    ADD CONSTRAINT order_outbox_unique_event_per_order UNIQUE (event_type, order_id);

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_sku_key UNIQUE (sku);

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_order_id_key UNIQUE (order_id);

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_receipt_number_key UNIQUE (receipt_number);

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_owner_id_key UNIQUE (owner_id);

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_slug_key UNIQUE (slug);

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT supplier_products_pkey PRIMARY KEY (supplier_id, product_id);

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_google_subject_key UNIQUE (google_subject);

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);

CREATE INDEX idx_inventory_transactions_order ON public.inventory_transactions USING btree (order_id);

CREATE INDEX idx_inventory_transactions_product_created ON public.inventory_transactions USING btree (product_id, created_at DESC);

CREATE INDEX idx_order_items_product ON public.order_items USING btree (product_id);

CREATE INDEX idx_order_outbox_expired_leases ON public.order_outbox USING btree (locked_until) WHERE ((status)::text = 'processing'::text);

CREATE INDEX idx_order_outbox_pending ON public.order_outbox USING btree (status, available_at, id) WHERE ((status)::text = 'pending'::text);

CREATE INDEX idx_orders_user_created ON public.orders USING btree (user_id, created_at);

CREATE INDEX market_orders ON public.orders USING btree (store_id, created_at DESC);

CREATE INDEX market_products ON public.products USING btree (store_id, archived, id);

CREATE UNIQUE INDEX orders_checkout_key ON public.orders USING btree (user_id, checkout_key) WHERE (checkout_key IS NOT NULL);

CREATE INDEX supplier_products_product_id_index ON public.supplier_products USING btree (product_id);

CREATE TRIGGER market_inventory_change AFTER INSERT OR UPDATE OF quantity ON public.inventory FOR EACH ROW EXECUTE FUNCTION public.notify_market_inventory();

CREATE TRIGGER market_product_change AFTER UPDATE OF name, price, description, category_id, photo, archived, low_stock_threshold ON public.products FOR EACH ROW EXECUTE FUNCTION public.notify_market_inventory();

CREATE TRIGGER market_store_change AFTER UPDATE ON public.stores FOR EACH ROW EXECUTE FUNCTION public.notify_market_inventory();

CREATE TRIGGER prevent_inactive_supplier_association BEFORE INSERT OR UPDATE OF supplier_id, product_id ON public.supplier_products FOR EACH ROW EXECUTE FUNCTION public.check_supplier_is_active();

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT fk_inventory_transactions_order FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory
    ADD CONSTRAINT inventory_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES public.users(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.inventory_transactions
    ADD CONSTRAINT inventory_transactions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.order_outbox
    ADD CONSTRAINT order_outbox_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id);

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.receipts
    ADD CONSTRAINT receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT supplier_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.supplier_products
    ADD CONSTRAINT supplier_products_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE RESTRICT;

COMMIT;
