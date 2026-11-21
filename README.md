# InvenKai · AP database submission

Team T0032 models the PostgreSQL data behind InvenKai’s buyer marketplace, seller storefronts and warehouse operations. This submission follows [application commit 33b5bbe](https://github.com/Arpitgoyal1306/InvenKai/tree/33b5bbe), including all 20 migrations under `server/migrations/`.

| AP checkpoint | Deliverable |
|---|---|
| CP0 | The tracker assigns setup to the DE repository. |
| CP1 | [Normalization and functional dependencies](dbms/01_normalization.md) |
| CP2 | [ER diagram](dbms/02_er_diagram.png), [PostgreSQL schema](dbms/03_schema.sql) and [schema assertions](dbms/04_assertions.sql) |
| CP3 | [Application SQL inventory](dbms/04_queries.sql) |
| CP4 | [Measured timings](dbms/05_query_timings.md), [execution plans and reproduction steps](dbms/plans/) |

## From storefront to receipt

1. Buyers browse published stores in React. The cart stays in browser session storage. Password and Google sign-in both resolve to a user account. Store ownership grants access to a seller’s listings, stock and incoming orders.
2. The Express API checks the storefront, locks the requested products and inventory in a consistent order, and checks availability. Checkout commits the order, buyer and pickup snapshots, line items, stock deductions, audit records and receipt outbox event together. A per-buyer retry key and request fingerprint protect repeated submissions.
3. The dispatcher claims outbox events and submits jobs to BullMQ in Redis. The receipt worker stores an immutable receipt snapshot in PostgreSQL. The buyer can view purchases and receipts while the seller advances fulfillment.
4. PostgreSQL notifications prompt public and owner-specific marketplace refreshes over Server-Sent Events. Staff tools use the warehouse inventory, supplier and reporting paths, with Redis and WebSocket inventory updates.

The schema has 12 application tables and 16 foreign keys. The application migrations also backfill zero-stock inventory for older products and convert historical order timestamps using the verified deployment timezone. The standalone SQL creates the resulting schema in an empty database. Apply the app migrations when upgrading existing application data.

## Verify the submission

From the repository root, using an empty local PostgreSQL database:

```sh
createdb invenkai_ap_check
psql -X -v ON_ERROR_STOP=1 -d invenkai_ap_check -f dbms/03_schema.sql -f dbms/04_assertions.sql
```

Use a separate empty database for the [benchmark fixture](dbms/plans/README.md). Its generated IDs are referenced by the captured query parameters.
