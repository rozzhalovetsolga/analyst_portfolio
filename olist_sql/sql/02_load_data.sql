-- Загрузка CSV в таблицы. Выполнять в psql, подключённом к базе olist:
--   psql olist
--   \i sql/02_load_data.sql   (из папки olist_sql, CSV лежат в data/)
-- \copy — команда psql, в DBeaver не работает.
-- Порядок как при создании таблиц: внешние ключи проверяются при загрузке.

\copy customers FROM 'data/olist_customers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy orders FROM 'data/olist_orders_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy order_payments FROM 'data/olist_order_payments_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy order_reviews FROM 'data/olist_order_reviews_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy category_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)
\copy products FROM 'data/olist_products_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy sellers FROM 'data/olist_sellers_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy order_items FROM 'data/olist_order_items_dataset.csv' WITH (FORMAT csv, HEADER true)
\copy geolocation FROM 'data/olist_geolocation_dataset.csv' WITH (FORMAT csv, HEADER true)

-- В справочнике переводов не хватает двух категорий (найдены anti-join, см. 03_explore.sql, 3.2).
-- Дописываем их и возвращаем внешний ключ products → category_translation.
INSERT INTO category_translation (product_category_name, product_category_name_english)
VALUES ('pc_gamer', 'gaming_pc'),
       ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_food_processors');

ALTER TABLE products
ADD FOREIGN KEY (product_category_name)
REFERENCES category_translation (product_category_name);
