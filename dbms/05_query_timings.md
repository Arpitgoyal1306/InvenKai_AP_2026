# CP4 Query Timings

**Project:** InvenKai
**Database:** PostgreSQL
**Query source:** `dbms/04_queries.sql`
**Measurement status:** Pending local execution. No timings or scan types have been fabricated.

## Method

1. Use the same PostgreSQL version, schema, indexes, and representative dataset for all runs.
2. Run each query three times with `EXPLAIN (ANALYZE, BUFFERS)`.
3. Record the `Execution Time` value in milliseconds from each plan.
4. Calculate the arithmetic mean: `(Run 1 + Run 2 + Run 3) / 3`.
5. Record the scan type shown by the plan, such as Sequential Scan, Index Scan, Index Only Scan, or Bitmap Heap Scan. For write queries, use `—` unless a meaningful scan type is part of the plan.
6. Save the complete output of all three runs under `dbms/plans/`, using names such as `R1_run1.txt`, `R1_run2.txt`, and `R1_run3.txt`.

## Safe execution rules

- Run every write statement inside a transaction and finish with `ROLLBACK`, never `COMMIT`.
- For dependent writes, create the required fixture rows inside the same transaction before running `EXPLAIN (ANALYZE, BUFFERS)`. Roll back the fixture and tested write together.
- Use valid parameter values and existing referenced rows. A query failing because its fixture is invalid is not a performance measurement.
- Run read queries against a stable dataset. Record the approximate row counts or dataset description separately if the instructor expects reproducibility.
- Do not compare timings from different datasets, schema versions, PostgreSQL versions, or machine configurations as if they were equivalent.
- Run the three repetitions consecutively under the same conditions. Keep all raw plans even if a run is unusually slow.

## Timing table

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|---|---|---|---:|---:|---:|---:|---|
| R1 | READ | Login by normalized email | | | | | |
| R2 | READ | List products with pagination | | | | | |
| R3 | READ | Get product by ID | | | | | |
| R4 | READ | Lock product row before update | | | | | |
| R5 | READ | Get inventory for a product | | | | | |
| R6 | READ | List low-stock products | | | | | |
| R7 | READ | Lock inventory row before stock adjustment | | | | | |
| R8 | READ | List inventory transactions, optionally filtered by product | | | | | |
| R9 | READ | List active suppliers with pagination | | | | | |
| R10 | READ | Get active supplier by ID | | | | | |
| R11 | READ | Lock active supplier row before update | | | | | |
| R12 | READ | Verify user exists before listing orders | | | | | |
| R13 | READ | Count a user's orders | | | | | |
| R14 | READ | List paginated user orders with item counts | | | | | |
| R15 | READ | Get one user's order and item details | | | | | |
| R16 | READ | Lock requested products and inventory for checkout | | | | | |
| R17 | READ | Get saved items for a newly created order | | | | | |
| R18 | READ | Summarize product and inventory totals | | | | | |
| R19 | READ | Get category-wise product and stock totals | | | | | |
| R20 | READ | Calculate stock added and removed in a date range | | | | | |
| R21 | READ | Get daily stock movement in a date range | | | | | |
| R22 | READ | Get order and item snapshots for receipt generation | | | | | |
| R23 | READ | Get existing receipt after idempotent insert | | | | | |
| R24 | READ | Check for existing receipt before retrying a failed job | | | | | |
| R25 | READ | API database health check | | | | | |
| R26 | READ | Verify PostgreSQL before server startup | | | | | |
| W1 | WRITE | Register a user | | | | | — |
| W2 | WRITE | Create a product | | | | | — |
| W3 | WRITE | Update a product | | | | | — |
| W4 | WRITE | Delete a product | | | | | — |
| W5 | WRITE | Set inventory quantity during stock adjustment | | | | | — |
| W6 | WRITE | Record an inventory transaction | | | | | — |
| W7 | WRITE | Create a supplier | | | | | — |
| W8 | WRITE | Update an active supplier | | | | | — |
| W9 | WRITE | Deactivate a supplier | | | | | — |
| W10 | WRITE | Create an order | | | | | — |
| W11 | WRITE | Insert an order item snapshot | | | | | — |
| W12 | WRITE | Deduct inventory during checkout | | | | | — |
| W13 | WRITE | Record an order-related inventory deduction | | | | | — |
| W14 | WRITE | Update order total from order items | | | | | — |
| W15 | WRITE | Insert receipt-request outbox event | | | | | — |
| W16 | WRITE | Claim pending or expired outbox events | | | | | — |
| W17 | WRITE | Renew outbox event leases | | | | | — |
| W18 | WRITE | Mark an outbox event dispatched | | | | | — |
| W19 | WRITE | Release an outbox event for retry | | | | | — |
| W20 | WRITE | Create a receipt idempotently | | | | | — |

## Execution environment

| Field | Value |
|---|---|
| PostgreSQL version | Pending |
| Operating system | Pending |
| CPU / RAM | Pending |
| Dataset size / row counts | Pending |
| Schema commit / version | Pending |
| Date measured | Pending |

## Reproducible benchmark runbook

Complete this record on the machine and database actually used for measurement. Do not copy example values as environment facts. Keep the same database, schema revision, dataset, and parameter values for all three repetitions of a query.

### 1. Record the environment

Connect to the target database (for example, with `psql "$DATABASE_URL"`; keep the connection string and credentials private), then record:

```bash
psql --version
```

In the connected `psql` session:

```sql
SELECT version();
\conninfo

SELECT
  (SELECT COUNT(*) FROM users) AS users,
  (SELECT COUNT(*) FROM categories) AS categories,
  (SELECT COUNT(*) FROM products) AS products,
  (SELECT COUNT(*) FROM inventory) AS inventory,
  (SELECT COUNT(*) FROM suppliers) AS suppliers,
  (SELECT COUNT(*) FROM supplier_products) AS supplier_products,
  (SELECT COUNT(*) FROM orders) AS orders,
  (SELECT COUNT(*) FROM order_items) AS order_items,
  (SELECT COUNT(*) FROM inventory_transactions) AS inventory_transactions,
  (SELECT COUNT(*) FROM order_outbox) AS order_outbox,
  (SELECT COUNT(*) FROM receipts) AS receipts;
```

On the benchmark machine, record the output of `uname -a`. On macOS, use `sysctl -n machdep.cpu.brand_string` and `sysctl -n hw.memsize` for CPU model and memory bytes. On Linux, use `lscpu` and `free -h`. Record the actual outputs or concise values; do not infer hardware details from a cloud database provider.

From the checked-out repository, record the revision and date:

```bash
git rev-parse HEAD
git log -1 --format='%H %cs' -- dbms/03_schema.sql
date '+%Y-%m-%d %H:%M:%S %Z'
```

The first command identifies the repository revision; the second identifies the latest commit affecting the schema file. Also record the dataset/table counts above and the exact query parameter values used.

### 2. Run and capture a read query

The following is an example for R1 from `dbms/04_queries.sql`. Replace the example email with the chosen test value, record that value, and use the same value for each repetition:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, email, password_hash, role
FROM users
WHERE email = 'benchmark@example.com';
```

Run the statement three separate times against the same stable dataset. Save each complete plan output as `dbms/plans/R1_run1.txt`, `dbms/plans/R1_run2.txt`, and `dbms/plans/R1_run3.txt`. Repeat for each query ID, substituting its actual parameter values safely. The example value is not a claim that such a row exists in the database.

### 3. Record results

For every query, keep all three genuine execution outputs. Copy each plan's `Execution Time` (milliseconds) and the relevant scan node into the matching row in the timing table. Calculate the arithmetic mean as:

`(Run 1 + Run 2 + Run 3) / 3`

Do not reuse one execution as multiple runs, discard an unusually slow run, or fill in timings that were not measured. For write queries, follow the rollback-safe transaction procedure in [`dbms/plans/README.md`](plans/README.md). That file also defines the raw-plan naming convention and required plan contents.

## Completion checklist

- [ ] All 26 READ queries measured three times.
- [ ] All 20 WRITE queries measured three times inside rollback-safe transactions.
- [ ] Average execution time calculated for all 46 query IDs.
- [ ] Scan type recorded from each query plan.
- [ ] Three raw plan files saved for every query ID.
- [ ] Execution environment documented.
