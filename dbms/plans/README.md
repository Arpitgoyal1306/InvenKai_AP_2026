# Reproduce the CP4 measurements

Each query has one text file containing its CP3 ID, exact prepared SQL, sample arguments, rollback transaction and three complete PostgreSQL plans. The timing report links directly to each file.

Use a new, empty local database so the fixture gets the same generated identifiers. From the repository root:

```sh
createdb invenkai_ap_bench
psql -X -v ON_ERROR_STOP=1 -d invenkai_ap_bench -f dbms/03_schema.sql -f dbms/plans/fixture.sql
```

Open a plan file and execute its block from `BEGIN` through `ROLLBACK` three times, each in a fresh psql connection. The sample transaction includes any setup needed by that operation. This isolates writes while allowing PostgreSQL to measure trigger work. Use the server’s Execution Time line in each plan for the mean. The parent [timing report](../05_query_timings.md) describes the dataset and environment.
