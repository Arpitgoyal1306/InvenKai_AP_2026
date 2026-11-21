# CP4 · Application query timings

All 111 query shapes in CP3 ran three times (66 reads, 45 writes). Each query ID links to its parameter values, transaction setup and three complete PostgreSQL plans.

## Measurement conditions

- Local 18.6 (Homebrew) on arm64. Single client, no competing application traffic. Source commit `33b5bbe`.
- Built a new database from `03_schema.sql`, loaded [the synthetic fixture](plans/fixture.sql) and ran `ANALYZE`. It includes 256 accounts, 32 shops, 16 categories, 2,048 products and inventory rows, 512 orders with one line and outbox event each, and 32 suppliers. It exercises public shops, unpublished shops, archived products, and warehouse stock.
- Three consecutive runs per query, each in a fresh connection and a rolled-back transaction. Runs shared the server’s PostgreSQL buffers and OS cache. Cache contents could carry over between repetitions. Setup statements and planning time are excluded. Each mean is the arithmetic mean of the three server execution times, rounded to 0.001 ms.
- Measurements describe individual SQL statements on this fixture. End-to-end HTTP latency, Redis traffic, and concurrent checkout waits require separate measurements.

| Query | Type | Operation | Run 1 ms | Run 2 ms | Run 3 ms | Mean ms | Scan nodes |
|---|---|---|---:|---:|---:|---:|---|
| [R1](plans/R1.txt) | READ | Startup clock probe | 0.016 | 0.016 | 0.014 | 0.015 | — |
| [R2](plans/R2.txt) | READ | Database readiness | 0.013 | 0.012 | 0.012 | 0.012 | — |
| [R3](plans/R3.txt) | READ | Database identity | 0.017 | 0.015 | 0.015 | 0.016 | — |
| [R4](plans/R4.txt) | READ | Google-only account check | 0.023 | 0.023 | 0.018 | 0.021 | Seq Scan |
| [R5](plans/R5.txt) | READ | Buyer catalog | 0.191 | 0.186 | 0.178 | 0.185 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R6](plans/R6.txt) | READ | Owner low-stock catalog | 0.193 | 0.168 | 0.176 | 0.179 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R7](plans/R7.txt) | READ | Store catalog categories | 0.091 | 0.079 | 0.074 | 0.081 | Bitmap Heap Scan, Bitmap Index Scan, Seq Scan |
| [R8](plans/R8.txt) | READ | Published shop directory and previews | 0.307 | 0.287 | 0.254 | 0.283 | Seq Scan, Index Scan |
| [R9](plans/R9.txt) | READ | Public directory categories | 0.041 | 0.038 | 0.036 | 0.038 | Seq Scan |
| [R10](plans/R10.txt) | READ | Published store details | 0.030 | 0.025 | 0.023 | 0.026 | Seq Scan |
| [R11](plans/R11.txt) | READ | Refresh cart products | 0.028 | 0.026 | 0.025 | 0.026 | Index Scan, Seq Scan |
| [R12](plans/R12.txt) | READ | Buyer purchase history | 0.051 | 0.045 | 0.043 | 0.046 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R13](plans/R13.txt) | READ | Current owner's store | 0.011 | 0.009 | 0.009 | 0.010 | Seq Scan |
| [R14](plans/R14.txt) | READ | Owner category suggestions | 0.107 | 0.092 | 0.084 | 0.094 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R15](plans/R15.txt) | READ | Slug claimed by another owner | 0.012 | 0.012 | 0.010 | 0.011 | Seq Scan |
| [W1](plans/W1.txt) | WRITE | Save store profile | 0.737 | 0.717 | 0.674 | 0.709 | — |
| [W2](plans/W2.txt) | WRITE | Publish store | 0.825 | 0.726 | 0.945 | 0.832 | Index Only Scan, Seq Scan |
| [R16](plans/R16.txt) | READ | Category lookup | 0.011 | 0.010 | 0.010 | 0.010 | Seq Scan |
| [W3](plans/W3.txt) | WRITE | Create seller category | 0.084 | 0.076 | 0.075 | 0.078 | — |
| [W4](plans/W4.txt) | WRITE | Edit seller product | 1.025 | 0.816 | 0.821 | 0.887 | Index Scan |
| [W5](plans/W5.txt) | WRITE | Create seller product | 0.443 | 0.402 | 0.367 | 0.404 | — |
| [W6](plans/W6.txt) | WRITE | Initialize seller stock | 1.175 | 1.157 | 1.083 | 1.138 | — |
| [W7](plans/W7.txt) | WRITE | Record starting seller stock | 0.480 | 0.442 | 0.500 | 0.474 | — |
| [W8](plans/W8.txt) | WRITE | Hide seller product | 0.896 | 0.929 | 1.010 | 0.945 | Index Scan |
| [W9](plans/W9.txt) | WRITE | Soft-delete seller product | 0.893 | 0.846 | 0.985 | 0.908 | Index Scan |
| [R17](plans/R17.txt) | READ | Lock seller stock | 0.050 | 0.034 | 0.038 | 0.041 | Index Scan |
| [W10](plans/W10.txt) | WRITE | Adjust seller stock and write audit row | 1.402 | 1.329 | 1.493 | 1.408 | Index Scan, CTE Scan |
| [R18](plans/R18.txt) | READ | Owner stock history | 0.173 | 0.207 | 0.170 | 0.183 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R19](plans/R19.txt) | READ | Owner inventory totals | 0.193 | 0.165 | 0.166 | 0.175 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R20](plans/R20.txt) | READ | Owner order and sales totals | 0.040 | 0.049 | 0.042 | 0.044 | Bitmap Heap Scan, Bitmap Index Scan |
| [R21](plans/R21.txt) | READ | Owner low-stock alerts | 0.167 | 0.209 | 0.192 | 0.189 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R22](plans/R22.txt) | READ | Seller order list | 0.070 | 0.101 | 0.069 | 0.080 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R23](plans/R23.txt) | READ | Seller order details | 0.038 | 0.042 | 0.039 | 0.040 | Seq Scan, Index Scan |
| [R24](plans/R24.txt) | READ | Seller order lines | 0.023 | 0.030 | 0.021 | 0.025 | Index Scan |
| [W11](plans/W11.txt) | WRITE | Advance fulfillment | 0.297 | 0.141 | 0.131 | 0.190 | Index Scan |
| [R25](plans/R25.txt) | READ | Staff category list | 0.028 | 0.031 | 0.030 | 0.030 | Seq Scan |
| [W12](plans/W12.txt) | WRITE | Create warehouse category | 0.087 | 0.090 | 0.079 | 0.085 | — |
| [R26](plans/R26.txt) | READ | Check active supplier | 0.010 | 0.011 | 0.010 | 0.010 | Seq Scan |
| [R27](plans/R27.txt) | READ | List products for supplier linking | 0.188 | 0.197 | 0.194 | 0.193 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [W13](plans/W13.txt) | WRITE | Link warehouse product to supplier | 0.795 | 0.881 | 0.805 | 0.827 | CTE Scan, Index Scan |
| [W14](plans/W14.txt) | WRITE | Unlink warehouse product | 0.064 | 0.067 | 0.056 | 0.062 | Index Scan |
| [R28](plans/R28.txt) | READ | Buyer receipt lookup | 0.019 | 0.020 | 0.018 | 0.019 | Index Scan |
| [R29](plans/R29.txt) | READ | Operations queue totals | 0.089 | 0.089 | 0.085 | 0.088 | Seq Scan |
| [R30](plans/R30.txt) | READ | Check receipt before retry | 0.011 | 0.010 | 0.011 | 0.011 | Index Scan |
| [R31](plans/R31.txt) | READ | Identify seeded shop owner | 0.024 | 0.024 | 0.023 | 0.024 | Index Scan, Seq Scan |
| [W15](plans/W15.txt) | WRITE | Create sample shop owner | 0.137 | 0.119 | 0.113 | 0.123 | — |
| [W16](plans/W16.txt) | WRITE | Create sample shop | 0.305 | 0.299 | 0.281 | 0.295 | — |
| [W17](plans/W17.txt) | WRITE | Ensure sample category exists | 0.101 | 0.105 | 0.100 | 0.102 | — |
| [W18](plans/W18.txt) | WRITE | Create sample product | 0.297 | 0.313 | 0.288 | 0.299 | Seq Scan |
| [W19](plans/W19.txt) | WRITE | Register password account | 0.113 | 0.106 | 0.108 | 0.109 | — |
| [R32](plans/R32.txt) | READ | Password login lookup | 0.021 | 0.021 | 0.022 | 0.021 | Seq Scan |
| [W20](plans/W20.txt) | WRITE | Refresh Google avatar | 0.101 | 0.096 | 0.108 | 0.102 | Seq Scan |
| [W21](plans/W21.txt) | WRITE | Create Google account | 0.123 | 0.107 | 0.119 | 0.116 | — |
| [W22](plans/W22.txt) | WRITE | Link verified Google account | 0.109 | 0.124 | 0.103 | 0.112 | Seq Scan |
| [R33](plans/R33.txt) | READ | Find linked Google account | 0.023 | 0.018 | 0.019 | 0.020 | Seq Scan |
| [R34](plans/R34.txt) | READ | Account profile | 0.017 | 0.016 | 0.014 | 0.016 | Seq Scan |
| [R35](plans/R35.txt) | READ | Check profile-edit credential | 0.017 | 0.015 | 0.014 | 0.015 | Seq Scan |
| [W23](plans/W23.txt) | WRITE | Save buyer profile | 0.107 | 0.097 | 0.095 | 0.100 | Index Scan |
| [R36](plans/R36.txt) | READ | Look up warehouse stock | 0.043 | 0.037 | 0.037 | 0.039 | Index Only Scan, Index Scan |
| [R37](plans/R37.txt) | READ | Warehouse low-stock list | 0.336 | 0.310 | 0.304 | 0.317 | Seq Scan |
| [R38](plans/R38.txt) | READ | Lock warehouse inventory | 0.039 | 0.031 | 0.031 | 0.034 | Index Scan |
| [W24](plans/W24.txt) | WRITE | Set warehouse quantity | 1.127 | 1.074 | 1.034 | 1.078 | Index Scan |
| [W25](plans/W25.txt) | WRITE | Record warehouse movement | 0.532 | 0.467 | 0.458 | 0.486 | — |
| [R39](plans/R39.txt) | READ | All warehouse movements | 0.236 | 0.224 | 0.219 | 0.226 | Seq Scan, Index Only Scan |
| [R40](plans/R40.txt) | READ | Movements for one warehouse product | 0.040 | 0.034 | 0.031 | 0.035 | Index Scan |
| [R41](plans/R41.txt) | READ | Warehouse inventory page | 0.058 | 0.061 | 0.057 | 0.059 | Index Scan |
| [R42](plans/R42.txt) | READ | Warehouse inventory count | 0.191 | 0.187 | 0.181 | 0.186 | Seq Scan, Index Only Scan |
| [W26](plans/W26.txt) | WRITE | Claim pending receipt jobs | 0.214 | 0.202 | 0.192 | 0.203 | Index Scan, Seq Scan, CTE Scan |
| [W27](plans/W27.txt) | WRITE | Renew dispatch lease | 0.106 | 0.093 | 0.144 | 0.114 | Index Scan |
| [W28](plans/W28.txt) | WRITE | Mark event dispatched | 0.107 | 0.099 | 0.095 | 0.100 | Index Scan |
| [W29](plans/W29.txt) | WRITE | Release failed dispatch | 0.143 | 0.145 | 0.122 | 0.137 | Index Scan |
| [W30](plans/W30.txt) | WRITE | Enqueue receipt event | 0.293 | 0.238 | 0.228 | 0.253 | — |
| [R43](plans/R43.txt) | READ | Verify buyer exists | 0.020 | 0.015 | 0.015 | 0.017 | Seq Scan |
| [R44](plans/R44.txt) | READ | Buyer order count | 0.028 | 0.025 | 0.024 | 0.026 | Bitmap Heap Scan, Bitmap Index Scan |
| [R45](plans/R45.txt) | READ | Buyer order page and item counts | 0.107 | 0.081 | 0.079 | 0.089 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R46](plans/R46.txt) | READ | Buyer order with items | 0.038 | 0.029 | 0.028 | 0.032 | Index Scan |
| [R47](plans/R47.txt) | READ | Serialize same-key checkout | 0.007 | 0.006 | 0.006 | 0.006 | — |
| [R48](plans/R48.txt) | READ | Look up prior checkout | 0.015 | 0.013 | 0.011 | 0.013 | Index Scan |
| [R49](plans/R49.txt) | READ | Lock store for checkout | 0.023 | 0.024 | 0.020 | 0.022 | Seq Scan |
| [R50](plans/R50.txt) | READ | Lock checkout products and inventory | 0.032 | 0.038 | 0.026 | 0.032 | Index Scan |
| [W31](plans/W31.txt) | WRITE | Open order | 0.374 | 0.365 | 0.335 | 0.358 | — |
| [W32](plans/W32.txt) | WRITE | Save checkout snapshots | 0.128 | 0.134 | 0.144 | 0.135 | Index Scan |
| [W33](plans/W33.txt) | WRITE | Record retry identity | 0.124 | 0.168 | 0.120 | 0.137 | Index Scan |
| [W34](plans/W34.txt) | WRITE | Insert order line | 0.463 | 0.494 | 0.510 | 0.489 | — |
| [W35](plans/W35.txt) | WRITE | Deduct available stock | 1.043 | 1.187 | 1.198 | 1.143 | Index Scan |
| [W36](plans/W36.txt) | WRITE | Record order stock movement | 0.638 | 0.672 | 0.611 | 0.640 | — |
| [W37](plans/W37.txt) | WRITE | Calculate order total | 0.140 | 0.148 | 0.158 | 0.149 | Index Scan |
| [R51](plans/R51.txt) | READ | Read saved order lines | 0.021 | 0.022 | 0.023 | 0.022 | Index Scan |
| [W38](plans/W38.txt) | WRITE | Create warehouse product | 0.338 | 0.376 | 0.312 | 0.342 | — |
| [W39](plans/W39.txt) | WRITE | Initialize warehouse stock | 1.005 | 1.127 | 1.066 | 1.066 | — |
| [R52](plans/R52.txt) | READ | Warehouse product page | 0.022 | 0.023 | 0.022 | 0.022 | Index Scan |
| [R53](plans/R53.txt) | READ | Warehouse product details | 0.014 | 0.014 | 0.012 | 0.013 | Index Scan |
| [R54](plans/R54.txt) | READ | Lock warehouse product | 0.023 | 0.025 | 0.021 | 0.023 | Index Scan |
| [W40](plans/W40.txt) | WRITE | Edit warehouse product | 0.906 | 1.003 | 0.920 | 0.943 | Index Scan |
| [W41](plans/W41.txt) | WRITE | Archive warehouse product | 0.796 | 0.814 | 0.764 | 0.791 | Index Scan |
| [R55](plans/R55.txt) | READ | Warehouse product count | 0.068 | 0.066 | 0.059 | 0.064 | Index Only Scan |
| [R56](plans/R56.txt) | READ | Warehouse stock summary | 0.187 | 0.192 | 0.188 | 0.189 | Seq Scan, Index Only Scan |
| [R57](plans/R57.txt) | READ | Stock by category | 0.408 | 0.399 | 0.406 | 0.404 | Seq Scan |
| [R58](plans/R58.txt) | READ | Stock for one category | 0.257 | 0.205 | 0.203 | 0.222 | Seq Scan, Bitmap Heap Scan, Bitmap Index Scan |
| [R59](plans/R59.txt) | READ | Total warehouse movements | 0.224 | 0.223 | 0.221 | 0.223 | Seq Scan, Index Only Scan |
| [R60](plans/R60.txt) | READ | Daily warehouse movements | 1.575 | 1.770 | 1.576 | 1.640 | Seq Scan, Index Only Scan |
| [W42](plans/W42.txt) | WRITE | Create supplier | 0.116 | 0.080 | 0.078 | 0.091 | — |
| [R61](plans/R61.txt) | READ | Active supplier page | 0.025 | 0.021 | 0.019 | 0.022 | Seq Scan |
| [R62](plans/R62.txt) | READ | Supplier details | 0.014 | 0.010 | 0.010 | 0.011 | Seq Scan |
| [R63](plans/R63.txt) | READ | Lock supplier for editing | 0.022 | 0.025 | 0.024 | 0.024 | Seq Scan |
| [W43](plans/W43.txt) | WRITE | Edit supplier | 0.082 | 0.086 | 0.092 | 0.087 | Seq Scan |
| [W44](plans/W44.txt) | WRITE | Deactivate supplier | 0.085 | 0.081 | 0.077 | 0.081 | Seq Scan |
| [R64](plans/R64.txt) | READ | Active supplier count | 0.031 | 0.027 | 0.027 | 0.028 | Seq Scan |
| [R65](plans/R65.txt) | READ | Receipt generation inputs | 0.038 | 0.033 | 0.033 | 0.035 | Index Scan |
| [W45](plans/W45.txt) | WRITE | Issue immutable receipt | 0.483 | 0.465 | 0.402 | 0.450 | — |
| [R66](plans/R66.txt) | READ | Read existing receipt | 0.010 | 0.011 | 0.009 | 0.010 | Index Scan |
