# InvenKai_AP_2026

PostgreSQL database documentation, normalization analysis, ER diagram, DDL schema, and schema assertions for the **InvenKai** inventory and order management project.

## Source of Truth

The application implementation and database migrations are maintained in `Arpitgoyal1306/InvenKai` under `backend/migrations/` (11 sequential migrations). All 11 tables, constraints, indexes, and triggers in this repository reflect the final state of those migrations.

## Repository Structure

```text
.
├── .github/workflows/db-schema-check.yml   # PostgreSQL 16 CI check
├── dbms/
│   ├── 01_normalization.md                 # 1NF–BCNF analysis (all 11 relations)
│   ├── 02_er_diagram.png                   # ER diagram (11 entities, 13 relationships)
│   ├── 03_schema.sql                       # PostgreSQL DDL matching all 11 migrations
│   └── 04_assertions.sql                   # Fail-fast schema & trigger assertions
└── README.md
```

## Database Technology

- **PostgreSQL 16+** (uses `GENERATED ALWAYS AS (...) STORED`, `TIMESTAMPTZ`, `JSONB`, `UUID`, partial indexes, and PL/pgSQL triggers).

## Local Execution

Run the schema and assertions against a clean PostgreSQL database:

```bash
createdb invenkai_test
psql -v ON_ERROR_STOP=1 -d invenkai_test -f dbms/03_schema.sql
psql -v ON_ERROR_STOP=1 -d invenkai_test -f dbms/04_assertions.sql
dropdb invenkai_test
```
