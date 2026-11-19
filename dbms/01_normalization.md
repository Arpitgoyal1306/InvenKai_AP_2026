# InvenKai Database Normalization (CP1)

## 1. Introduction and scope

This document analyzes the PostgreSQL schema defined by the InvenKai application's migrations. It covers the eleven current relations: `users`, `categories`, `products`, `inventory`, `inventory_transactions`, `suppliers`, `supplier_products`, `orders`, `order_items`, `order_outbox`, and `receipts`.

The walkthrough distinguishes between:

- **Actual schema facts:** columns, keys, unique constraints, foreign keys, generated columns, and checks declared by the migrations.
- **Illustrative starting relations:** hypothetical examples used only to demonstrate how a relation with repeating groups or transitive dependencies can be decomposed. They are not claims about the application's historical schema.
- **JSONB assumption:** `order_outbox.payload` and `receipts.items` are `JSONB` columns, which can hold nested structures. The analysis does not treat them as automatically atomic. Instead, it states an explicit modelling assumption (Section 3.2): each value is an opaque, immutable document that the database stores and returns as a whole, and no functional dependency is claimed on its internal contents.

The normalization walkthrough is organized as 1NF → 2NF → 3NF. Where a generated or constrained calculated attribute complicates a strict formal normal-form claim, that limitation is stated explicitly rather than hidden.

## 2. Actual relations, keys, and functional dependencies

A functional dependency (FD) `X → Y` means that a value of attribute set `X` determines exactly one value of attribute set `Y` in every valid row of the relation.

In the lists below, `id`-based and unique-key dependencies include all the other attributes in that row. They are expanded explicitly so the candidate-key analysis can be checked against the migrations.

### 2.1 `users`

**Relation:** `users(id, name, email, password_hash, role, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{email}` (`UNIQUE NOT NULL`).
- FDs:
  - `id → name, email, password_hash, role, created_at, updated_at`
  - `email → id, name, password_hash, role, created_at, updated_at`
- Foreign keys: none.

### 2.2 `categories`

**Relation:** `categories(id, name, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{name}` (`UNIQUE NOT NULL`).
- FDs:
  - `id → name, created_at, updated_at`
  - `name → id, created_at, updated_at`
- Foreign keys: none.

### 2.3 `products`

**Relation:** `products(id, category_id, name, description, sku, price, created_at, updated_at, low_stock_threshold)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{sku}` (`UNIQUE NOT NULL`).
- FDs:
  - `id → category_id, name, description, sku, price, created_at, updated_at, low_stock_threshold`
  - `sku → id, category_id, name, description, price, created_at, updated_at, low_stock_threshold`
- Foreign key: `category_id → categories.id` (referential relationship; it does not make `category_id` unique in `products`).
- `low_stock_threshold` is nullable and has a check allowing `NULL` or a non-negative value.

### 2.4 `inventory`

**Relation:** `inventory(id, product_id, quantity, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{product_id}` (`UNIQUE NOT NULL`).
- FDs:
  - `id → product_id, quantity, created_at, updated_at`
  - `product_id → id, quantity, created_at, updated_at`
- Foreign key: `product_id → products.id`.

### 2.5 `inventory_transactions`

**Relation:** `inventory_transactions(id, product_id, performed_by, transaction_type, quantity, quantity_before, quantity_after, created_at, order_id)`

- Primary key / candidate key: `{id}`.
- FD from the declared key:
  - `id → product_id, performed_by, transaction_type, quantity, quantity_before, quantity_after, created_at, order_id`
- Foreign keys:
  - `product_id → products.id`
  - `performed_by → users.id` (nullable; `ON DELETE SET NULL`)
  - `order_id → orders.id` (nullable; added by the orders migration)
- Additional FD implied by the arithmetic `CHECK` constraint:
  - `(transaction_type, quantity, quantity_before) → quantity_after`
  - The check requires `quantity_after = quantity_before + quantity` for an increase, or `quantity_after = quantity_before - quantity` for a decrease.
- The check also restricts `transaction_type` to `increase` or `decrease`, requires positive `quantity`, and requires non-negative before/after quantities. `order_id` must be `NULL` or the transaction type must be `decrease`.

### 2.6 `suppliers`

**Relation:** `suppliers(id, name, contact_name, email, phone, is_active, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- FD:
  - `id → name, contact_name, email, phone, is_active, created_at, updated_at`
- Foreign keys: none.
- **Important constraint distinction:** the migrations do not declare `email` or `phone` as unique. They are not candidate keys. The checks require a non-blank name and at least one non-blank contact method (email or phone), but do not establish uniqueness.

### 2.7 `supplier_products`

**Relation:** `supplier_products(supplier_id, product_id)`

- Composite primary key / only candidate key: `{supplier_id, product_id}`.
- FD:
  - `(supplier_id, product_id) →` the complete association row.
- There are no non-key attributes in this relation.
- Foreign keys: `supplier_id → suppliers.id`; `product_id → products.id`.

### 2.8 `orders`

**Relation:** `orders(id, user_id, status, total_amount, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- FD:
  - `id → user_id, status, total_amount, created_at, updated_at`
- Foreign key: `user_id → users.id`.
- `status` is restricted to `placed`, `processing`, `completed`, or `cancelled`. `total_amount` is constrained to be non-negative.
- `total_amount` is a stored order-level aggregate. The migrations shown define the column and its non-negative check, but do not define a trigger that recalculates it from `order_items`. Its consistency with the order items must therefore be maintained by the application or other logic not shown in these migrations. It is not a within-row FD of the `orders` relation that `id` determines the individual `order_items` rows.

### 2.9 `order_items`

**Relation:** `order_items(id, order_id, product_id, product_name, sku, unit_price, quantity, line_total)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{order_id, product_id}` (`UNIQUE NOT NULL`).
- FDs from both candidate keys:
  - `id → order_id, product_id, product_name, sku, unit_price, quantity, line_total`
  - `(order_id, product_id) → id, product_name, sku, unit_price, quantity, line_total`
- Foreign keys: `order_id → orders.id`; `product_id → products.id`.
- Ordinary stored facts: `order_id`, `product_id`, `product_name`, `sku`, `unit_price`, and `quantity`. `product_name`, `sku`, and `unit_price` are intentional order-time snapshots. They describe what was recorded for that particular order line; they are not assumed to equal the current product values forever.
- Generated attribute: `line_total` is a **stored generated column** defined as `unit_price * quantity`. Thus the row also has the calculated dependency `(unit_price, quantity) → line_total`.
- Checks: `quantity > 0` and `unit_price >= 0`.

### 2.10 `order_outbox`

**Relation:** `order_outbox(id, event_type, order_id, payload, status, attempts, available_at, locked_until, claim_token, last_error, dispatched_at, created_at, updated_at)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate key: `{event_type, order_id}` (`UNIQUE (event_type, order_id)`, both columns `NOT NULL`). At most one outbox event of a given type exists per order.
- FDs:
  - `id → event_type, order_id, payload, status, attempts, available_at, locked_until, claim_token, last_error, dispatched_at, created_at, updated_at`
  - `(event_type, order_id) → id, payload, status, attempts, available_at, locked_until, claim_token, last_error, dispatched_at, created_at, updated_at`
- Foreign key: `order_id → orders.id` (`ON DELETE CASCADE`, mandatory).
- Checks: `status` is `pending`, `processing`, or `dispatched`; `attempts >= 0`.
- `payload` is a `JSONB` event document; see the assumption in Section 3.2. No FD from `event_type` alone or `order_id` alone is declared: one order can have several event types, and one event type applies to many orders.
- The two partial indexes (`status = 'pending'` and `status = 'processing'`) are access paths for the dispatcher. They do not declare additional keys or FDs.

### 2.11 `receipts`

**Relation:** `receipts(id, order_id, receipt_number, user_id, total_amount, items, issued_at)`

- Primary key / candidate key: `{id}`.
- Declared alternate candidate keys: `{order_id}` (`UNIQUE NOT NULL`) and `{receipt_number}` (`UNIQUE NOT NULL`).
- FDs:
  - `id → order_id, receipt_number, user_id, total_amount, items, issued_at`
  - `order_id → id, receipt_number, user_id, total_amount, items, issued_at`
  - `receipt_number → id, order_id, user_id, total_amount, items, issued_at`
- Foreign keys: `order_id → orders.id` (`ON DELETE RESTRICT`, mandatory; one order has zero or one receipt) and `user_id → users.id` (`ON DELETE RESTRICT`, mandatory).
- Checks: `total_amount >= 0`; `jsonb_typeof(items) = 'array'`.
- `total_amount` and `items` are an issue-time snapshot of the order, like the snapshot columns of `order_items`. `items` is a `JSONB` array; see Section 3.2. `user_id` and `total_amount` are copies of values that also live in `orders`. The migrations declare no composite foreign key or trigger that forces them to match the order, so that agreement is a cross-relation rule maintained outside the schema (see Section 5.3).

### 2.12 Declared candidate keys versus business assumptions

A candidate key must be supported by a uniqueness rule in the schema (or be explicitly established as a business rule for the relation being analyzed). The migrations declare uniqueness for `users.email`, `categories.name`, `products.sku`, `inventory.product_id`, `order_items(order_id, product_id)`, `order_outbox(event_type, order_id)`, `receipts.order_id`, and `receipts.receipt_number`, in addition to each table's primary key. They do **not** declare supplier email or phone unique. This document does not assume uniqueness merely because an attribute may commonly be unique in a business setting.

Foreign-key relationships and check constraints enforce referential or value rules; they do not automatically create candidate keys.

## 3. First Normal Form (1NF)

A relation is in 1NF when every attribute value is atomic for the intended use of the relation and there are no repeating groups or list-valued cells. Each row must also be identifiable by a key.

### 3.1 Actual InvenKai relations

The eleven migrated relations use individual columns for their values. For example:

- `orders` has one `id`, one `user_id`, one `status`, and one `total_amount` per row.
- Each product ordered is represented by a separate `order_items` row, not by a list of product IDs in an `orders` cell.
- Each supplier–product association is represented by one `supplier_products` row.
- `inventory_transactions` represents each stock movement as its own row.
- `order_outbox` represents each pending or dispatched event as its own row, keyed by `(event_type, order_id)`.
- `receipts` has one row per issued receipt; the line items of the receipt are kept in the `items` document discussed below.

Therefore, the actual relations are structured to satisfy 1NF: their repeating business details are represented as rows in related relations rather than as repeating groups in a single cell.

### 3.2 JSONB attributes (`order_outbox.payload`, `receipts.items`)

`JSONB` can hold arrays and nested objects, so it is **not atomic in general**. The 1NF claim for these two columns therefore rests on an explicit assumption about the intended relational model:

- Each value is treated as a single opaque document that is written once and read back whole. The application never queries, joins on, updates, or constrains individual elements inside it using relational keys.
- No FD is claimed from or to anything inside the document. The only dependencies are those on the document as a whole: `id → payload` and `(event_type, order_id) → payload` in `order_outbox`, and each candidate key `→ items` in `receipts`.
- `receipts.items` is an immutable snapshot of the order lines at issue time. The queryable, normalized representation of the same order lines is `order_items`; the receipt copy exists to preserve what was issued, not to be the source of truth for line data.
- The database enforces only that `items` is a JSON array (`jsonb_typeof(items) = 'array'`) and that `payload` is non-null. It does not validate the structure of the elements.

Under this assumption `order_outbox` and `receipts` satisfy 1NF. If the application later starts filtering, joining, or updating individual receipt lines or payload fields as relational data, the assumption would no longer hold and the document contents would need to be decomposed into their own relations (for example a `receipt_items` table).

### 3.3 Illustrative alternative design (not the actual schema)

Suppose an order were initially recorded in this hypothetical, non-1NF relation:

`OrderDraft(order_id, user_id, product_ids, product_names, quantities)`

| order_id | user_id | product_ids | product_names | quantities |
|---:|---:|---|---|---|
| 501 | 7 | `P10, P11` | `Mouse, Keyboard` | `1, 2` |

The three list-valued attributes contain repeating groups. A single product's quantity cannot be safely updated without editing a list inside the row.

**1NF decomposition:**

`Orders(order_id, user_id)`

| order_id (PK) | user_id |
|---:|---:|
| 501 | 7 |

`OrderLines(order_id, product_id, product_name, quantity)`

| order_id (PK, FK) | product_id (PK) | product_name | quantity |
|---:|---:|---|---:|
| 501 | 10 | Mouse | 1 |
| 501 | 11 | Keyboard | 2 |

- `Orders` primary key: `order_id`.
- `OrderLines` composite primary key: `(order_id, product_id)`; `order_id` is a foreign key to `Orders`.
- The values are now atomic and each product line is a separate row.

This is a teaching illustration of the same row-based pattern used by the actual `orders` and `order_items` relations. It is not a claim that the InvenKai migrations ever created `OrderDraft`.

## 4. Second Normal Form (2NF)

A relation is in 2NF when it is in 1NF and every non-prime attribute is fully dependent on every candidate key; in particular, no non-key attribute may depend on only a proper subset of a composite candidate key. A relation whose candidate keys are all single-attribute has no possible partial dependency on a subset of one of those keys.

### 4.1 Actual relations with single-attribute candidate keys

The relations `users`, `categories`, `products`, `inventory`, `inventory_transactions`, `suppliers`, `orders`, and `receipts` have only single-attribute candidate keys in the migrations (`receipts` has `id`, `order_id`, and `receipt_number`). Their non-key attributes depend on their respective row identifier (`id`), and a partial dependency on part of a single-attribute key is not possible.

`inventory` also has the declared alternate candidate key `product_id`, which is single-attribute. `users`, `categories`, and `products` similarly have single-attribute alternate candidate keys (`email`, `name`, and `sku`). These do not introduce a composite-key partial dependency.

### 4.2 `supplier_products`

The actual relation is:

`SupplierProducts(supplier_id, product_id)`

- Candidate key: `(supplier_id, product_id)`.
- FD: `(supplier_id, product_id) →` the complete row.
- Non-key attributes: none.

Because there are no non-key attributes, there cannot be a partial dependency of a non-key attribute on only `supplier_id` or only `product_id`. This relation satisfies 2NF.

### 4.3 `order_items`: both candidate keys

The actual relation has two candidate keys: `id` and `(order_id, product_id)`. The composite candidate key must be checked explicitly.

For the composite key, the relevant FD is:

`(order_id, product_id) → product_name, sku, unit_price, quantity, line_total` (and `id`, because the pair is declared unique).

There is no declared FD `product_id → product_name, sku, unit_price` for the order-item relation. Although `product_id` references the current `products` row, `product_name`, `sku`, and `unit_price` in `order_items` are order-time snapshots. The same product can have different snapshot values on different orders if its name, SKU, or price changes between purchases. Therefore, these snapshot attributes are treated as facts about the order line, determined by the complete `(order_id, product_id)` key, not by `product_id` alone.

`quantity` is also a fact about a particular order line. It is not determined by `product_id` alone because different orders can purchase different quantities. `line_total` is calculated from the line's `unit_price` and `quantity`; its special generated-column dependency is discussed in Sections 5.3 and 6.

The other candidate key, `id`, is a single attribute, so it cannot have a partial dependency. On the stated snapshot semantics, there is no partial dependency under the composite candidate key either. Thus, the ordinary order-line facts satisfy the 2NF test. The generated `line_total` has an additional derived FD that is treated separately below; it does not create a dependency on only `order_id` or only `product_id`.

### 4.4 `order_outbox`: both candidate keys

`order_outbox` has the single-attribute candidate key `id` and the composite candidate key `(event_type, order_id)`. The composite key must be checked explicitly.

The non-prime attributes are `payload`, `status`, `attempts`, `available_at`, `locked_until`, `claim_token`, `last_error`, `dispatched_at`, `created_at`, and `updated_at`. For a partial dependency to exist, one of them would have to be determined by `event_type` alone or by `order_id` alone. Neither is declared, and neither holds under the stated semantics:

- `order_id` alone does not determine them, because one order can have several outbox events of different types, each with its own payload, status, and attempt count.
- `event_type` alone does not determine them, because the same event type is emitted for many orders, each with its own delivery state.

So every non-prime attribute depends on the whole of `(event_type, order_id)`, and `order_outbox` satisfies 2NF. The single-attribute key `id` cannot have a partial dependency.

### 4.5 Illustrative 2NF decomposition (not the actual schema)

Consider this hypothetical relation, designed only to demonstrate a partial dependency:

`SupplierProductDetails(supplier_id, product_id, supplier_name, product_name, agreed_price)`

Assume its composite key is `(supplier_id, product_id)` and the following illustrative FDs hold:

- `(supplier_id, product_id) → agreed_price`
- `supplier_id → supplier_name`
- `product_id → product_name`

`supplier_name` depends only on `supplier_id`, and `product_name` depends only on `product_id`. These are partial dependencies, so the relation is not in 2NF.

Decompose it into:

- `Suppliers(supplier_id PK, supplier_name)`
- `Products(product_id PK, product_name)`
- `SupplierProduct(supplier_id PK/FK, product_id PK/FK, agreed_price)`

The supplier and product descriptions now depend on their own complete single-column keys. `agreed_price` depends on the complete pair. This is an illustrative decomposition, not the actual InvenKai schema. The actual application uses a narrower `supplier_products(supplier_id, product_id)` relation with no non-key attributes and stores supplier/product descriptions in their own tables.

## 5. Third Normal Form (3NF)

A relation is in 3NF when it is in 2NF and, for every non-trivial FD `X → A`, either `X` is a superkey or `A` is a prime attribute (an attribute that belongs to at least one candidate key). In the common teaching case, this means non-key descriptive attributes should not depend transitively on a key through another non-key attribute.

### 5.1 Actual entity separation

The actual schema already separates several entity descriptions from the relations that reference them:

- `orders` stores `user_id`; user name, email, password hash, and role are in `users`.
- `products` stores `category_id`; category name is in `categories`.
- `inventory` stores `product_id` and quantity; product name, SKU, and price are in `products`.
- `supplier_products` stores only supplier/product identifiers; supplier details are in `suppliers`, and product details are in `products`.
- `inventory_transactions` references products, users, and optionally orders by their identifiers rather than copying all of those entities' current descriptive columns.
- `order_outbox` references its order through `order_id` and does not copy order details such as the customer or status; event delivery state (`status`, `attempts`, `available_at`, and so on) is a fact about the event row itself.
- `receipts` references its order and user by identifier. It also stores a deliberate snapshot (`total_amount`, `items`) of the order at issue time; this is treated like the `order_items` snapshots, as a fact about the issued receipt rather than a live copy of `orders` or `products`.

For these relationships, the foreign key identifies a row in the referenced relation. The referenced table's primary key then determines its descriptive attributes. Those attributes are not repeated in the referencing relation, avoiding the corresponding transitive descriptive dependency there.

### 5.2 Illustrative 3NF decomposition (not the actual schema)

Suppose a hypothetical order relation stored the customer's name and email on every order:

`OrderWithCustomer(order_id, user_id, user_name, user_email, status)`

Assume these FDs:

- `order_id → user_id, user_name, user_email, status`
- `user_id → user_name, user_email`

Then `order_id → user_id → user_name, user_email` is a transitive dependency through the non-key attribute `user_id`. The relation repeats customer details across orders and is not in 3NF under these FDs.

Decompose into:

- `Users(user_id PK, user_name, user_email)`
- `Orders(order_id PK, user_id FK, status)`

In `Users`, `user_id` determines the user's details. In `Orders`, `order_id` determines `user_id` and `status`; the customer details are obtained through the foreign key rather than duplicated. This illustrates the separation already used by the actual `users` and `orders` relations.

A second example is category information. A hypothetical `ProductWithCategory(product_id, product_name, category_id, category_name)` with `product_id → category_id, product_name` and `category_id → category_name` has a transitive dependency `product_id → category_id → category_name`. Separating `Categories(category_id PK, category_name)` and `Products(product_id PK, product_name, category_id FK)` removes the repeated category description. The actual InvenKai migrations already use these separate relations.

### 5.3 Physical-schema qualifications: generated and constrained derived attributes

The preceding entity-separation analysis describes the ordinary identifying and descriptive facts. A strict formal analysis must also consider dependencies introduced by calculated attributes and checks in the physical schema.

**`order_items.line_total` — generated column**

The migration declares `line_total` as a stored generated column:

`line_total = unit_price * quantity`

Therefore, in the physical relation there is an FD:

`(unit_price, quantity) → line_total`

The determinant `(unit_price, quantity)` is not a superkey: two different order lines may have the same unit price and quantity. `line_total` is not a prime attribute because it is not part of either candidate key (`id` or `(order_id, product_id)`). Under the standard FD definition, this non-trivial dependency violates 3NF and BCNF for the physical `order_items` relation.

For a conceptual normalization analysis that excludes generated columns from the set of independently stored facts, the base order-line relation without `line_total` has no such generated-attribute FD and passes the 3NF check based on the FDs listed above. However, the actual physical table does include the stored generated column, so the document does not claim that the complete physical relation is strictly in 3NF/BCNF.

**`inventory_transactions.quantity_after` — constrained calculated value**

The migration's `CHECK` constraint requires:

- for `increase`: `quantity_after = quantity_before + quantity`;
- for `decrease`: `quantity_after = quantity_before - quantity`.

Together with the allowed values of `transaction_type`, this means:

`(transaction_type, quantity, quantity_before) → quantity_after`

The determinant is not a superkey, and `quantity_after` is not a prime attribute. Treating all dependencies implied by the valid-row constraints as FDs, this is another 3NF and BCNF violation in the physical `inventory_transactions` relation. The migration stores `quantity_after` as an ordinary column and enforces the equation with a check; unlike `line_total`, it is not declared as a generated column.

If the design instead calculated `quantity_after` when displaying a transaction, it could omit that stored value and avoid this particular within-row dependency. The current migration does store it, so the qualification must remain in the normalization conclusion.

**`orders.total_amount` — order-level aggregate**

`orders.total_amount` is stored on the order row, but its value represents an aggregate over the related `order_items` rows. This is a cross-table consistency rule, not a normal within-row FD such as `X → Y` among attributes of one `orders` tuple. The migrations declare a non-negative check but do not show a trigger that recalculates the total when order items change. Therefore, application logic or other logic outside the listed migrations is responsible for keeping `total_amount` consistent with the order's items. It should not be described as automatically synchronized by the database based on these migrations alone.

**`receipts.user_id` and `receipts.total_amount` — cross-relation copies**

Within `receipts`, every non-key attribute depends only on candidate keys (`id`, `order_id`, `receipt_number`), so there is no within-relation transitive dependency. However, `order_id → user_id` also holds in `orders`, and `receipts.total_amount` mirrors `orders.total_amount` at issue time. The migrations do not enforce that `receipts.user_id` equals the owning order's `user_id`, nor that the totals match. This is a cross-relation consistency rule, analogous to `orders.total_amount`, and is maintained by application logic rather than by a constraint in the migrations.

### 5.4 3NF conclusion

The core entity relations are decomposed to keep user, category, product, and supplier descriptions with their own identifiers, and the ordinary attributes in the relations have key-based dependencies. The ordinary order-item facts also pass the 2NF test when the snapshot semantics are respected.

However, when every dependency implied by the actual physical schema is included, `order_items` has the generated-column FD `(unit_price, quantity) → line_total`, and `inventory_transactions` has the check-implied FD `(transaction_type, quantity, quantity_before) → quantity_after`. Neither determinant is a superkey and neither dependent attribute is prime. Thus, the full physical schema is **not strictly in 3NF for those two relations**. This is a deliberate storage choice for a generated line total and a checked transaction result, not evidence that the ordinary entity descriptions have been mixed into the wrong tables.

`order_outbox` and `receipts` are in 3NF: every declared FD has a candidate key as its determinant (`id` or `(event_type, order_id)` for `order_outbox`; `id`, `order_id`, or `receipt_number` for `receipts`), so no transitive dependency through a non-key attribute exists. This conclusion holds under the JSONB assumption in Section 3.2 (no FDs are claimed on the contents of `payload` or `items`) and for the within-relation FDs only; the cross-relation copies in `receipts` noted above are consistency rules, not within-relation FDs.

## 6. BCNF (optional extension)

BCNF requires the determinant of every non-trivial FD to be a superkey. It is stricter than 3NF.

For the key-based FDs in the eleven relations, the declared primary and alternate candidate keys are determinants and therefore superkeys. This includes `order_outbox` (`id` and `(event_type, order_id)`) and `receipts` (`id`, `order_id`, and `receipt_number`). `supplier_products` has only its composite key and no non-key attributes. `suppliers.email` and `suppliers.phone` are not treated as determinants because the migrations do not declare them unique.

The complete physical schema nevertheless has at least these non-key determinants:

- `order_items`: `(unit_price, quantity) → line_total`.
- `inventory_transactions`: `(transaction_type, quantity, quantity_before) → quantity_after`.

Neither determinant is a superkey, so these relations do not satisfy BCNF when these generated/constrained dependencies are included. The same two dependencies also prevent a strict 3NF claim, as explained above. `orders.total_amount` is a cross-row aggregate consistency concern, not an additional within-row FD in the `orders` relation.

`order_outbox` and `receipts` have no non-key determinants among the FDs listed, so they satisfy BCNF, again under the Section 3.2 assumption that no FDs are claimed on the contents of the `JSONB` attributes.

Accordingly, the key-based entity structure is BCNF with respect to the key-based FDs listed, but the complete physical relations `order_items` and `inventory_transactions` are not BCNF under the additional calculated dependencies. This is the qualified conclusion; listing keys alone would not prove BCNF.

## 7. Summary

| Stage | Actual-schema analysis | Result |
|---|---|---|
| 1NF | The eleven relations use atomic column values; repeating order lines and supplier/product associations are represented as rows. `order_outbox.payload` and `receipts.items` are `JSONB`, treated as opaque whole documents (Section 3.2). | The actual relations satisfy 1NF, with the stated JSONB assumption for the two document columns. |
| 2NF | Single-column candidate keys cannot have partial dependencies; `supplier_products` has no non-key attributes; `order_items` is checked under both `id` and `(order_id, product_id)`, with snapshots depending on the full order-line key; `order_outbox` is checked under both `id` and `(event_type, order_id)`; `receipts` has only single-attribute candidate keys. | Ordinary stored facts satisfy the 2NF test, including `order_outbox` and `receipts`; the generated `line_total` is separately identified as derived. |
| 3NF | Entity descriptions are separated into their own relations; `order_outbox` and `receipts` have only key-determined attributes (receipt copies of `user_id` and `total_amount` are cross-relation consistency rules). The physical FDs for generated `line_total` and check-constrained `quantity_after` have non-superkey determinants and non-prime dependents. | Core entity facts, `order_outbox`, and `receipts` are decomposed appropriately, but the complete physical `order_items` and `inventory_transactions` relations are not strictly 3NF when those derived dependencies are included. |
| BCNF (optional) | Key-based FDs, including those of `order_outbox` and `receipts`, have candidate-key determinants. The two calculated dependencies have non-superkey determinants. | The full physical `order_items` and `inventory_transactions` relations are not BCNF under the stated FDs. |

## 8. Conclusion

The InvenKai migrations define eleven related tables and use primary keys, declared unique constraints, foreign keys, and check constraints to protect data integrity. The 1NF walkthrough shows how atomic values and separate rows represent repeating order lines. The 2NF analysis checks every composite candidate key, including both candidate keys in `order_items`, and distinguishes order-time snapshots from current product attributes. The 3NF walkthrough demonstrates how separating users, categories, products, and suppliers prevents repeated descriptive information.

The formal analysis also identifies two physical-schema qualifications: the generated `order_items.line_total` and the check-constrained `inventory_transactions.quantity_after` each have a non-superkey determinant. Consequently, it would be inaccurate to claim that every physical relation strictly satisfies 3NF or BCNF without excluding those derived dependencies. `orders.total_amount` is a stored order-level aggregate whose synchronization is not implemented by a trigger in the migrations reviewed.

The two relations added by the outbox/receipts migration, `order_outbox` and `receipts`, are integrated into every stage above. Both satisfy 1NF, 2NF, 3NF, and BCNF with respect to their declared keys, provided the `JSONB` columns `payload` and `items` are treated as opaque, immutable documents (Section 3.2). `receipts` additionally stores `user_id` and `total_amount` as copies of order data, and their agreement with `orders` is not enforced by the schema.

## 9. Migration source files

This analysis is based on these files in the InvenKai application repository:

- `backend/migrations/1791302634749_create-categories.js`
- `backend/migrations/1791375780922_create-users.js`
- `backend/migrations/1791479591493_products.js`
- `backend/migrations/1791565549521_inventory.js`
- `backend/migrations/1793954366512_inventory-transactions.js`
- `backend/migrations/1793986878067_create-suppliers-and-supplier-products.js`
- `backend/migrations/1793991125708_prevent-inactive-supplier-associations.js`
- `backend/migrations/1793999172515_update-inactive-supplier-trigger.js`
- `backend/migrations/1794030177261_add-low-stock-threshold-to-products.js`
- `backend/migrations/1794100000000_create-orders.js`
- `backend/migrations/1794200000000_create-order-outbox-and-receipts.js` (introduces `order_outbox` and `receipts`)