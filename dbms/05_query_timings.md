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

## Completion checklist

- [ ] All 26 READ queries measured three times.
- [ ] All 20 WRITE queries measured three times inside rollback-safe transactions.
- [ ] Average execution time calculated for all 46 query IDs.
- [ ] Scan type recorded from each query plan.
- [ ] Three raw plan files saved for every query ID.
- [ ] Execution environment documented.
