-- Benchmark fixture for an empty disposable database after 03_schema.sql.
BEGIN;
INSERT INTO users(name,email,password_hash,google_subject)
SELECT 'Account '||n,'user'||n||'@example.test',CASE WHEN n<>2 THEN 'fixture' END,
       CASE WHEN n=2 THEN 'google-2' END FROM generate_series(1,256) n;
INSERT INTO stores(owner_id,name,slug,category,contact,pickup,published,slug_locked)
SELECT n,'Shop '||n,'shop-'||n,'Food','shop'||n||'@example.test','Counter '||n,n%4<>0,n%4<>0
FROM generate_series(1,32) n;
INSERT INTO categories(name) SELECT 'Category '||n FROM generate_series(1,16) n;
INSERT INTO products(category_id,name,sku,price,low_stock_threshold,store_id,archived,deleted_at)
SELECT 1+(n-1)%16,'Product '||n,'SKU-'||n,10,5,
       CASE WHEN n%5<>0 THEN 1+(n-1)%32 END,n%17=0,
       CASE WHEN n%17=0 AND n%5<>0 AND n%2=0 THEN now() END
FROM generate_series(1,2048) n;
INSERT INTO inventory(product_id,quantity) SELECT id,id%30 FROM products;
INSERT INTO inventory_transactions(product_id,performed_by,transaction_type,quantity,quantity_before,quantity_after)
SELECT product_id,1,'increase',quantity,0,quantity FROM inventory WHERE quantity>0;
INSERT INTO orders(user_id,store_id,total_amount,status,pickup_snapshot,buyer_details,checkout_key,checkout_fingerprint)
SELECT 33+(n-1)%224,p.store_id,10,CASE WHEN n%3=0 THEN 'completed' ELSE 'placed' END,
       'Counter '||p.store_id,'{"name":"Fixture buyer"}','key-'||n,'fingerprint-'||n
FROM generate_series(1,512) n JOIN products p ON p.id=n;
INSERT INTO order_items(order_id,product_id,product_name,sku,unit_price,quantity)
SELECT o.id,p.id,p.name,p.sku,p.price,1 FROM orders o JOIN products p ON p.id=o.id;
INSERT INTO order_outbox(event_type,order_id,payload,status,locked_until,claim_token)
SELECT 'order.receipt.requested',id,jsonb_build_object('orderId',id),
       CASE WHEN id=2 THEN 'processing' WHEN id%3=0 THEN 'dispatched' ELSE 'pending' END,
       CASE WHEN id=2 THEN now()+interval '1 day' END,
       CASE WHEN id=2 THEN '00000000-0000-4000-8000-000000000002'::uuid END FROM orders;
INSERT INTO receipts(order_id,receipt_number,user_id,total_amount,items)
SELECT o.id,'INV-'||o.id,o.user_id,o.total_amount,jsonb_build_array(to_jsonb(i))
FROM orders o JOIN order_items i ON i.order_id=o.id WHERE o.id%3=0;
INSERT INTO suppliers(name,email) SELECT 'Supplier '||n,'s'||n||'@example.test' FROM generate_series(1,32) n;
INSERT INTO supplier_products(supplier_id,product_id)
SELECT 1+(id/5-1)%32,id FROM products WHERE store_id IS NULL;
COMMIT;
ANALYZE;
