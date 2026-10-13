-- Схема базы olist: 9 таблиц маркетплейса Olist (Kaggle).
-- База создаётся заранее командой: createdb olist
-- Порядок создания: сначала таблицы, на которые ссылаются другие, потом зависимые.

CREATE TABLE customers (
    customer_id              uuid PRIMARY KEY,
    customer_unique_id       uuid,
    customer_zip_code_prefix text,
    customer_city            text,
    customer_state           varchar(2)
);

CREATE TABLE orders (
    order_id                      uuid PRIMARY KEY,
    customer_id                   uuid,
    order_status                  text,
    order_purchase_timestamp      timestamp,
    order_approved_at             timestamp,
    order_delivered_carrier_date  timestamp,
    order_delivered_customer_date timestamp,
    order_estimated_delivery_date timestamp,
    FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
);

CREATE TABLE order_payments (
    order_id             uuid,
    payment_sequential   smallint,
    payment_type         text,
    payment_installments smallint,
    payment_value        numeric(10, 2),
    PRIMARY KEY (order_id, payment_sequential),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

-- Ожидала, что review_id уникален, но нет: один отзыв привязан к нескольким заказам.
-- Уникальна пара (order_id, review_id).
CREATE TABLE order_reviews (
    review_id               uuid,
    order_id                uuid,
    review_score            smallint,
    review_comment_title    text,
    review_comment_message  text,
    review_creation_date    timestamp,
    review_answer_timestamp timestamp,
    PRIMARY KEY (order_id, review_id),
    FOREIGN KEY (order_id) REFERENCES orders (order_id)
);

CREATE TABLE category_translation (
    product_category_name         text PRIMARY KEY,
    product_category_name_english text
);

-- Внешний ключ на category_translation добавляется после загрузки (02_load_data.sql):
-- в исходном справочнике переводов не хватает двух категорий, их я дописала вручную.
CREATE TABLE products (
    product_id                 uuid PRIMARY KEY,
    product_category_name      text,
    product_name_length        smallint,
    product_description_length smallint,
    product_photos_qty         smallint,
    product_weight_g           integer,
    product_length_cm          smallint,
    product_height_cm          smallint,
    product_width_cm           smallint
);

CREATE TABLE sellers (
    seller_id              uuid PRIMARY KEY,
    seller_zip_code_prefix text,
    seller_city            text,
    seller_state           varchar(2)
);

CREATE TABLE order_items (
    order_id            uuid,
    order_item_id       smallint,
    product_id          uuid,
    seller_id           uuid,
    shipping_limit_date timestamp,
    price               numeric(10, 2),
    freight_value       numeric(10, 2),
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (order_id)   REFERENCES orders (order_id),
    FOREIGN KEY (product_id) REFERENCES products (product_id),
    FOREIGN KEY (seller_id)  REFERENCES sellers (seller_id)
);

-- Первичного ключа нет и не нужно: на один почтовый индекс приходится в среднем ~50 точек.
CREATE TABLE geolocation (
    geolocation_zip_code_prefix text,
    geolocation_lat             real,
    geolocation_lng             real,
    geolocation_city            text,
    geolocation_state           varchar(2)
);
