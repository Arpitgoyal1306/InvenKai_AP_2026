# CP4 Execution Plans

This directory stores the raw PostgreSQL execution plans for the 46 query IDs in `../04_queries.sql`.

## Required files

Save three complete plan outputs for every query:

- `R1_run1.txt`
- `R1_run2.txt`
- `R1_run3.txt`
- Repeat for `R2` through `R26` and `W1` through `W20`.

That is 138 plan files when all 46 queries have three successful runs.

## Capture format

Use:

```sql
EXPLAIN (ANALYZE, BUFFERS)
<the exact parameterized query with test values substituted safely>;
```

Use SQL literals only for local measurement. Never interpolate untrusted input into application code.

For each write query, use a rollback-safe transaction:

```sql
BEGIN;

EXPLAIN (ANALYZE, BUFFERS)
<write statement with valid test values>;

ROLLBACK;
```

For a write that depends on another row, insert the fixture row(s) after `BEGIN`, run the explained statement, and roll back the entire transaction. Keep the setup and query in the same transaction so the measured operation sees valid references.

## Important

- Preserve the full plan text, including Planning Time, Execution Time, buffer details, and node-level scan information.
- Do not save only a screenshot or a manually summarized plan.
- Do not invent or estimate missing timings.
- The corresponding three execution times and scan type must be entered in `../05_query_timings.md`.
- Use the same database, schema, data volume, and environment for all repetitions.
