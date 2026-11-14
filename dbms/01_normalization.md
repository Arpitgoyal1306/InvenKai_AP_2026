# InvenKai Database Normalization (CP1)

## 1. Introduction

This document explains the normalization of the relational data used by **InvenKai**, an inventory and order management application.

The analysis is based on the PostgreSQL table definitions in the `backend/migrations/` directory of the InvenKai application repository. It describes the schema that is actually defined by those migrations, rather than adding hypothetical entities or attributes.

The purpose of normalization is to organize data so that it is stored consistently and unnecessary duplication is reduced. This helps prevent insertion, update, and deletion anomalies.

### 1.1 Application data covered

The current migrations define the following nine tables:

1. `users`
2. `categories`
3. `products`
4. `inventory`
5. `inventory_transactions`
6. `suppliers`
7. `supplier_products`
8. `orders`
9. `order_items`

> **Note:** The application has nine tables in the current migrations. The `supplier_products` table connects suppliers and products, while `order_items` connects orders and products.

## 2. Functional Dependencies and Keys

A functional dependency describes how one attribute or a group of attributes determines another attribute.

For example:

`product_id → quantity`

means that a particular `product_id` determines the quantity stored for that product's inventory record.

The following table summarizes the main keys and functional dependencies.

| Relation | Primary key | Other candidate keys / important dependencies |
|---|---|---|
| `users` | `id` | `email` is unique; `email → name, password_hash, role, created_at, updated_at` |
| `categories` | `id` | `name` is unique; `name → created_at, updated_at` |
| `products` | `id` | `sku` is unique; `sku → category_id, name, description, price, low_stock_threshold, created_at, updated_at` |
| `inventory` | `id` | `product_id` is unique; `product_id → quantity, created_at, updated_at` |
| `inventory_transactions` | `id` | `id` determines the product, user, transaction details, optional order reference, and timestamp |
| `suppliers` | `id` | `id` determines supplier contact and active-status details |
| `supplier_products` | (`supplier_id`, `product_id`) | The pair identifies one supplier–product association |
| `orders` | `id` | `id` determines user, status, total amount, and timestamps |
| `order_items` | `id` | (`order_id`, `product_id`) is also unique and identifies one product line within an order |

The schema also defines the following important relationships:

- Each product belongs to one category through `products.category_id`.
- Each inventory row belongs to one product. `inventory.product_id` is unique, so a product can have at most one inventory row.
- An inventory transaction refers to one product and can optionally refer to the user who performed it.
- A supplier can be associated with many products, and a product can be associated with many suppliers. `supplier_products` represents this many-to-many relationship.
- Each order belongs to one user.
- An order can contain multiple order items. Each order item refers to one product.
- An inventory transaction can optionally refer to an order.

## 3. First Normal Form (1NF)

A relation is in **First Normal Form (1NF)** when:

- Each table has rows that can be uniquely identified.
- Each cell contains a single, atomic value.
- There are no repeating groups or multiple values stored in one column.

### 3.1 Applying 1NF to InvenKai

The InvenKai schema follows 1NF because its columns store individual values.

Examples:

- `users.email` stores one email address for a user.
- `products.name` stores one product name.
- `products.price` stores one numeric price.
- `inventory.quantity` stores one stock quantity.
- `suppliers.phone` stores one phone value.
- `orders.status` stores one order status.
- `order_items.quantity` stores the quantity of one product line in an order.

The application does not store a list of products inside a single `orders` row. Instead, each product in an order is stored as a separate row in `order_items`.

Similarly, suppliers are not stored as a comma-separated list inside a product row. The association is represented using separate rows in `supplier_products`.

### 3.2 Example: Order and order items

A non-normalized design might store multiple products in one order row:

| order_id | user_id | products |
|---|---:|---|
| 101 | 5 | Mouse, Keyboard, Monitor |

The `products` cell contains multiple values, which makes searching and updating individual products difficult.

In InvenKai, the order and its items are separated:

**orders**

| id | user_id | status |
|---:|---:|---|
| 101 | 5 | placed |

**order_items**

| id | order_id | product_id | quantity |
|---:|---:|---:|---:|
| 1 | 101 | 10 | 1 |
| 2 | 101 | 11 | 2 |
| 3 | 101 | 12 | 1 |

Each row represents one order item, and each cell contains one value.

**Conclusion:** The current table structure satisfies 1NF because it uses atomic column values and represents repeating data using separate rows and related tables.

## 4. Second Normal Form (2NF)

A relation is in **Second Normal Form (2NF)** when:

- It is already in 1NF.
- Every non-key attribute depends on the whole candidate key, not just a part of a composite candidate key.

A partial dependency can occur when a table has a composite key and a non-key attribute depends on only one part of that key.

### 4.1 Applying 2NF to InvenKai

Most InvenKai tables use a single-column primary key, such as `users.id`, `products.id`, `orders.id`, and `suppliers.id`.

With a single-column key, a partial dependency on only part of that primary key cannot occur.

The `supplier_products` table is an important example because it uses a composite primary key:

`(supplier_id, product_id)`

This pair identifies one supplier–product association.

The table contains no additional non-key attributes. Therefore, there is no non-key attribute that depends on only `supplier_id` or only `product_id`.

### 4.2 Example: Supplier–product association

The relationship is represented as:

| supplier_id | product_id |
|---:|---:|
| 1 | 10 |
| 1 | 11 |
| 2 | 10 |

The composite key is:

`(supplier_id, product_id)`

The same supplier can supply different products, and the same product can be supplied by different suppliers.

If supplier details such as `supplier_name` were copied into this table, they would depend only on `supplier_id`, not on the complete pair. That would create a partial dependency and unnecessary duplication.

Instead, InvenKai stores supplier details in `suppliers` and product details in `products`. The junction table stores only the two foreign keys.

### 4.3 Order items

The `order_items` table has a single-column primary key `id` and also has a unique constraint on `(order_id, product_id)`.

The order-item details describe a particular product line in a particular order. The stored `product_name`, `sku`, and `unit_price` are historical snapshots for that order item; they preserve what was recorded when the order was placed, even if the current product information changes later.

**Conclusion:** The current tables avoid partial dependencies. In particular, the composite-key table `supplier_products` contains no non-key attributes, and the other main tables use single-column primary keys.

## 5. Third Normal Form (3NF)

A relation is in **Third Normal Form (3NF)** when:

- It is already in 2NF.
- Non-key attributes do not depend on other non-key attributes (there should be no inappropriate transitive dependency of a non-key attribute on the key).

In simple terms, non-key attributes should describe the key, the whole key, and nothing but the key.

### 5.1 Applying 3NF to InvenKai

The schema separates information about different real-world entities into their own tables.

#### A. Users and orders

The `orders` table stores `user_id` as a foreign key. User details such as name and email remain in `users`.

If the user's email and name were also stored in every order row, the same user details would be repeated across orders. Updating a user's email would then require updating multiple order rows.

In InvenKai:

- `users` stores user information.
- `orders` stores order information and references the user through `user_id`.

This avoids unnecessary duplication of current user details in the orders table.

#### B. Categories and products

The `products` table stores `category_id` as a foreign key. The category name is stored in `categories`.

The category name is not repeated in every product row.

For example:

**categories**

| id | name |
|---:|---|
| 1 | Electronics |

**products**

| id | category_id | name |
|---:|---:|---|
| 10 | 1 | Wireless Mouse |
| 11 | 1 | Keyboard |

If the category name changes, it needs to be updated in one place: the `categories` table.

#### C. Products and inventory

The `inventory` table stores the quantity for a product and refers to it through `product_id`.

Product details such as name, SKU, and price remain in `products`. They are not copied into the inventory table.

The unique constraint on `inventory.product_id` ensures that a product has at most one inventory row.

#### D. Suppliers and products

Supplier details are stored in `suppliers`, product details are stored in `products`, and their many-to-many association is stored in `supplier_products`.

This avoids repeating supplier and product details in association records.

#### E. Inventory transaction history

The `inventory_transactions` table stores the details of each stock change, including:

- `product_id`
- `performed_by`
- `transaction_type`
- `quantity`
- `quantity_before`
- `quantity_after`
- `order_id` (optional)
- `created_at`

The transaction stores the stock values at the time of the event. These are historical transaction facts, not copies of the current inventory row.

#### F. Order items and historical product details

The `order_items` table contains `product_name`, `sku`, and `unit_price` in addition to `product_id`.

These fields are intentionally stored as **order-time snapshots**. They preserve the product description and price recorded for the purchase. They should not be treated as copies that must always match the current `products` row.

For example, if a product's name or price changes after an order is placed, the old order should continue to show the name and price recorded at the time of purchase.

This is a deliberate historical-data requirement.

### 5.2 Derived values and normalization note

Two calculated values are present in the schema:

- `order_items.line_total` is a generated column calculated as `unit_price * quantity`.
- `orders.total_amount` stores the total amount for the order.

These values are useful for reading order totals, but they are derived from order-item information. In a strictly non-redundant design, they can be calculated when needed. Keeping calculated totals can be a deliberate design choice, but the application must keep them consistent with the order items.

**Conclusion:** The schema separates users, categories, products, suppliers, inventory, transactions, orders, and order items into related tables. It avoids common transitive dependencies by keeping each entity's descriptive details in its own table. Historical order-item snapshots are retained intentionally.

## 6. Boyce–Codd Normal Form (BCNF) — Optional

A relation is in **Boyce–Codd Normal Form (BCNF)** when, for every non-trivial functional dependency:

`X → Y`

`X` must be a superkey.

BCNF is stricter than 3NF.

### 6.1 Applying BCNF to InvenKai

The main entity tables use primary keys to identify their rows. The schema also defines unique constraints for important alternate identifiers:

- `users.email`
- `categories.name`
- `products.sku`
- `inventory.product_id`
- `order_items(order_id, product_id)`

The `supplier_products` table uses `(supplier_id, product_id)` as its composite primary key.

These keys ensure that the main identifying dependencies are based on candidate keys.

### 6.2 Derived attributes and BCNF consideration

The generated `order_items.line_total` is calculated from `unit_price` and `quantity`.

The expression:

`line_total = unit_price * quantity`

is a calculation, not an independent fact that needs to be entered by a user. Since the database stores it as a generated column, it is maintained from the source values. For a strictly minimal relational design, `line_total` could instead be calculated in a query.

Likewise, `orders.total_amount` is an order-level total based on its order items. It is a stored aggregate and should be kept consistent with those items.

These calculated values are the main places where the physical schema intentionally stores derived information. They should be considered when discussing strict BCNF.

**Conclusion:** The key-based table structures are designed around candidate keys. The generated line total and stored order total are deliberate derived values; a fully minimal design could calculate them instead of storing them. BCNF is therefore discussed with this qualification rather than claiming that every stored calculated value is a non-redundant attribute.

## 7. Summary

| Normal form | Main requirement | How InvenKai addresses it |
|---|---|---|
| 1NF | Atomic values and no repeating groups | Each column stores individual values. Repeated order items and supplier–product associations use separate rows. |
| 2NF | No partial dependency on part of a composite key | `supplier_products` has a composite key and no non-key attributes. Other main tables use single-column primary keys. |
| 3NF | No inappropriate transitive dependency between non-key attributes | User, category, product, supplier, inventory, order, and transaction details are separated into their own tables. |
| BCNF | Every determinant in a non-trivial functional dependency is a superkey | Main identifiers use primary or unique keys. Derived order totals are noted as intentional calculated values. |

## 8. Conclusion

The InvenKai database uses separate relational tables for users, categories, products, inventory, inventory transactions, suppliers, supplier–product associations, orders, and order items.

The design uses primary keys, foreign keys, unique constraints, and check constraints to maintain data integrity. It also separates entity details from their relationships, which reduces unnecessary duplication and helps prevent common insertion, update, and deletion anomalies.

The schema follows the main principles of 1NF, 2NF, and 3NF. BCNF is considered as an additional, stricter level, with the generated order-item line total and stored order total identified as deliberate derived values.

## 9. Source Files

This analysis is based on the following files in the InvenKai application repository:

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
