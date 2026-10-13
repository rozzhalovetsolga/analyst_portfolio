-- Исследование данных Olist: от проверки загрузки до оконных функций.
-- Под каждым запросом — что получилось и какой вывод я из этого сделала.


-- ============================================================
-- Проверка загрузки
-- ============================================================

SELECT COUNT(*) FROM customers;
-- 99 441

SELECT COUNT(*) FROM orders;
-- 99 441 — совпадает, при загрузке ничего не потерялось.


-- ============================================================
-- Покупатели: customer_id или customer_unique_id
-- ============================================================

SELECT COUNT(DISTINCT customer_id) FROM customers;
-- 99 441 — столько же, сколько заказов: customer_id выдаётся заново на каждый заказ, это не человек.

SELECT COUNT(DISTINCT customer_unique_id) FROM customers;
-- 96 096 человек. Повторных заказов всего 3 345 (около 3,4%) —
-- первый сигнал, что покупатели почти не возвращаются. К этому вопросу ещё вернусь.


-- ============================================================
-- Отзывы: почему не загрузился первичный ключ по review_id
-- ============================================================

SELECT COUNT(*) FROM order_reviews;
-- 99 224

SELECT COUNT(DISTINCT review_id) FROM order_reviews;
-- 98 410 — review_id повторяется, поэтому первичный ключ по нему и не загрузился.

SELECT COUNT(DISTINCT (review_id, order_id)) FROM order_reviews;
-- 99 224 — а пара (order_id, review_id) уникальна. Делаю составной ключ:

ALTER TABLE order_reviews ADD PRIMARY KEY (order_id, review_id);


-- ============================================================
-- Уровень 1: SELECT, WHERE, ORDER BY, LIMIT
-- ============================================================

-- 1.1 Десять самых свежих заказов
SELECT order_id,
       order_status,
       order_purchase_timestamp
FROM orders
ORDER BY order_purchase_timestamp DESC
LIMIT 10;
-- Все десять — сентябрь–октябрь 2018, и все отменены. Похоже, выгрузка обрывается летом 2018:
-- последние месяцы неполные, сравнивать их с остальными нельзя.

-- 1.2 Какие бывают статусы заказа
SELECT DISTINCT order_status
FROM orders;
-- 8 статусов: created, approved, invoiced, processing, shipped,
-- delivered, canceled, unavailable

-- 1.3 Сколько заказов отменено
SELECT COUNT(*)
FROM orders
WHERE order_status = 'canceled';
-- 625 — около 0,6%. Отмены для этого бизнеса не главная проблема.

-- 1.4 Заказы за ноябрь 2017 (Black Friday — 24.11.2017)
SELECT COUNT(*)
FROM orders
WHERE order_purchase_timestamp >= '2017-11-01'
  AND order_purchase_timestamp <  '2017-12-01';
-- 7 544 — около 7,6% всех заказов за один месяц. Black Friday виден сразу.

-- 1.5 Доставленные заказы без даты доставки (проверка качества данных)
SELECT *
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
-- 8 заказов, у одного нет даже даты передачи в доставку. Мелочь, но при расчёте сроков
-- их нужно исключать, иначе NULL незаметно испортит среднее.

-- 1.6 Десять самых дорогих позиций
SELECT order_id,
       price,
       freight_value
FROM order_items
ORDER BY price DESC
LIMIT 10;
-- Максимум — 6 735 реалов. У дорогих товаров доставка почти ничего не стоит: 0,5–5% цены.

-- 1.7 Платежи ваучером больше 100 реалов
SELECT COUNT(*)
FROM order_payments
WHERE payment_type = 'voucher'
  AND payment_value > 100;
-- 895. С условием >= 100 — уже 1 134: ровно 100 реалов заплачено 239 раз.
-- Такая круглая сумма похожа на ваучеры номиналом 100. Граница в условии меняет ответ, поэтому проверяю её всегда.

-- 1.8 Позиции, где доставка дороже товара
SELECT COUNT(*)
FROM order_items
WHERE freight_value > price;
-- 4 124 позиции, около 3,7%. Это дешёвые товары: доставка съедает заказ, и покупатель это чувствует.

-- 1.9 Покупатели из Сан-Паулу и Рио-де-Жанейро
SELECT COUNT(*)
FROM customers
WHERE customer_city IN ('sao paulo', 'rio de janeiro');
-- 22 422 — но это заказы, а не люди: customer_id выдаётся на каждый заказ.

SELECT COUNT(DISTINCT customer_unique_id)
FROM customers
WHERE customer_city IN ('sao paulo', 'rio de janeiro');
-- 21 603 человека — почти четверть всех покупателей.
-- Возвращаются 3,7%, как и по всей базе: в крупных городах покупатели не лояльнее.

-- 1.10 Мебельные категории
SELECT DISTINCT product_category_name
FROM products
WHERE product_category_name ILIKE '%moveis%';
-- 6 категорий: спальня, гостиная, матрасы, декор, кухня и сад, офис

-- 1.11 Отзывы с оценкой 1 и текстом
SELECT review_id,
       review_score,
       review_comment_message
FROM order_reviews
WHERE review_score = 1
  AND review_comment_message IS NOT NULL
LIMIT 10;
-- Прочитала жалобы: 7 из 10 — про доставку (не пришло, опоздало, пришло не всё).
-- Гипотеза: низкие оценки ставит логистика, а не товар. Проверю на уровне 3.

-- 1.12 Ценовые группы позиций
SELECT order_id,
       price,
       CASE
           WHEN price < 50 THEN 'cheap'
           WHEN price >= 50 AND price <= 200 THEN 'mid'
           WHEN price > 200 THEN 'expensive'
       END AS price_group
FROM order_items
LIMIT 20;

-- 1.13 Опоздал ли заказ (сравнение по дням: обещанная дата без времени)
SELECT order_id,
       order_estimated_delivery_date,
       order_delivered_customer_date,
       CASE
           WHEN order_delivered_customer_date::date >  order_estimated_delivery_date::date THEN 'late'
           WHEN order_delivered_customer_date::date <= order_estimated_delivery_date::date THEN 'on_time'
       END AS delivery
FROM orders
WHERE order_status = 'delivered'
LIMIT 20;
-- Без ELSE заказ без даты доставки получает NULL, а не ложное on_time.
-- 19 из 20 приходят вовремя, часто на 1–3 недели раньше обещанного: запас в сроке большой.


-- ============================================================
-- Уровень 2: GROUP BY, HAVING, агрегаты
-- ============================================================

-- 2.1 Заказы по статусам
SELECT order_status,
       COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;
-- 97% доставлено. Интереснее другое: unavailable (609) почти столько же, сколько canceled (625) —
-- половина сорванных заказов срывается потому, что товара не оказалось у продавца.

-- 2.2 Заказы по месяцам
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS month,
       COUNT(*) AS orders
FROM orders
GROUP BY month
ORDER BY month;
-- 2016 — по сути тестовый запуск. Ноября 2016 в результате нет вовсе: GROUP BY не показывает пустые месяцы.
-- Дальше рост с 800 заказов (январь 2017) до 7 544 (ноябрь 2017), а в 2018 — плато 6–7 тыс.
-- Последний полный месяц — август 2018, дальше выгрузка обрывается.

SELECT MIN(order_purchase_timestamp::date) AS start_date,
       MAX(order_purchase_timestamp::date) AS end_date
FROM orders;
-- 2016-09-04 — 2018-10-17: границы данных, от них отталкиваюсь во всех расчётах по времени.

-- 2.3 Пять дней с наибольшим числом заказов
SELECT order_purchase_timestamp::date AS day,
       COUNT(*) AS orders
FROM orders
GROUP BY day
ORDER BY orders DESC
LIMIT 5;
-- Black Friday 24.11.2017 — 1 176 заказов, почти в 5 раз больше среднего дня ноября.
-- И весь топ-5 — одна неделя, 24–28 ноября.

-- 2.4 Десять штатов с наибольшим числом покупателей
SELECT customer_state,
       COUNT(DISTINCT customer_unique_id) AS customers
FROM customers
GROUP BY customer_state
ORDER BY customers DESC
LIMIT 10;
-- SP — 40 302 человека (42%); вместе с RJ и MG — две трети покупателей. Рынок сосредоточен на юго-востоке.

-- 2.5 Сколько людей сделали больше одного заказа
SELECT COUNT(*)
FROM (
    SELECT customer_unique_id,
           COUNT(*) AS orders
    FROM customers
    GROUP BY customer_unique_id
    HAVING COUNT(*) > 1
) AS t;
-- 2 997 человек, 3,1% (repeat purchase rate). Рекордсмен — 17 заказов. Для маркетплейса это очень мало,
-- и это главный вопрос исследования: почему не возвращаются? (В 4.5 цифра уточнится.)

-- 2.6 Способы оплаты
SELECT payment_type,
       COUNT(*) AS payments,
       ROUND(SUM(payment_value), 2) AS total_value,
       ROUND(AVG(payment_value), 2) AS avg_payment
FROM order_payments
GROUP BY payment_type
ORDER BY total_value DESC;
-- Карта — около 78% суммы. Ваучер в среднем 66 реалов: им доплачивают часть заказа, а не платят целиком.
-- not_defined — 3 платежа на 0,00. Мусор в данных, на выводы не влияет.

-- 2.7 Продавцы с более чем 1 000 проданных позиций
SELECT seller_id,
       COUNT(*) AS items
FROM order_items
GROUP BY seller_id
HAVING COUNT(*) > 1000
ORDER BY items DESC;
-- 13 продавцов из 3 095 (0,4%) продают около 17% всех позиций. Классический длинный хвост.

-- 2.8 Доля опоздавших заказов
SELECT t.delivery,
       COUNT(*) AS orders
FROM (
    SELECT CASE
               WHEN order_delivered_customer_date::date >  order_estimated_delivery_date::date THEN 'late'
               WHEN order_delivered_customer_date::date <= order_estimated_delivery_date::date THEN 'on_time'
           END AS delivery
    FROM orders
    WHERE order_status = 'delivered'
) AS t
GROUP BY t.delivery;
-- late 6 534, on_time 89 936, NULL 8 — в сумме 96 478, ровно все доставленные. Проверка сошлась.

SELECT ROUND(AVG(CASE
                     WHEN order_delivered_customer_date::date > order_estimated_delivery_date::date THEN 1.0
                     ELSE 0
                 END) * 100, 2) AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
-- 6,77%. Если забыть WHERE, знаменателем станут все заказы, включая недоставленные, и выйдет 6,57%.
-- Разница небольшая, но это уже другая метрика.

-- 2.9 На сколько дней раньше обещанного приходит заказ
SELECT ROUND(AVG(order_estimated_delivery_date::date - order_delivered_customer_date::date), 1) AS avg_days_early,
       PERCENTILE_CONT(0.5) WITHIN GROUP (
           ORDER BY order_estimated_delivery_date::date - order_delivered_customer_date::date
       ) AS median_days_early
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
-- Среднее 11,9 дня, медиана 12,0: заказ приходит почти на две недели раньше обещанного.
-- И при таком запасе 6,8% всё равно опаздывают — значит, дело не в среднем сроке, а в разбросе.

-- 2.10 Доля опозданий по месяцам покупки
SELECT DATE_TRUNC('month', order_purchase_timestamp)::date AS orders_month,
       COUNT(*) AS delivered,
       ROUND(AVG(CASE
                     WHEN order_delivered_customer_date::date > order_estimated_delivery_date::date THEN 1.0
                     ELSE 0
                 END) * 100, 2) AS late_pct
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
GROUP BY orders_month
ORDER BY orders_month;
-- Сентябрь 2016: 100% опозданий — от одного заказа. Доля без количества рядом вводит в заблуждение.
-- Ноябрь 2017, пик заказов, — 12,4% против обычных 3–4%: логистика не выдержала Black Friday.
-- Но худшие месяцы — февраль и март 2018 (14% и 19%, около 1 330 опозданий в марте), и с пиком заказов они не связаны.
-- Июнь 2018 — 1,2%, но последние месяцы занижены: самые медленные заказы ещё не доехали до конца выгрузки.

-- 2.11 Распределение оценок отзывов
SELECT review_score,
       COUNT(*) AS count_reviews,
       ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM order_reviews), 2) AS pct
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;
-- 5 — 57,8%, 4 — 19,3%, 3 — 8,2%, 2 — 3,2%, 1 — 11,5%.
-- Единиц втрое больше, чем двоек: люди либо довольны, либо недовольны всерьёз. Средний балл это скрывает.


-- ============================================================
-- Уровень 3: JOIN
-- ============================================================

-- 3.1 Топ-10 категорий по выручке
SELECT p.product_category_name,
       ct.product_category_name_english,
       SUM(oi.price) AS revenue
FROM order_items AS oi
JOIN products AS p ON p.product_id = oi.product_id
LEFT JOIN category_translation AS ct ON ct.product_category_name = p.product_category_name
GROUP BY p.product_category_name, ct.product_category_name_english
ORDER BY revenue DESC
LIMIT 10;
-- Лидеры — health_beauty и watches_gifts, около 1,2 млн реалов каждая (~9% выручки по товарам).
-- Группирую по португальскому названию: по английскому категории без перевода слились бы в одну группу NULL.

-- 3.2 Категории без перевода (anti-join)
SELECT DISTINCT p.product_category_name,
       ct.product_category_name_english
FROM products AS p
LEFT JOIN category_translation AS ct ON ct.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL;
-- Не хватает двух: pc_gamer (3 товара) и portateis_cozinha_e_preparadores_de_alimentos (10 товаров).
-- Из-за них при загрузке и не прошёл внешний ключ. Перевод дописала в 02_load_data.sql.

-- 3.3 Оценки у опоздавших и доставленных вовремя
SELECT CASE
           WHEN o.order_delivered_customer_date::date >  o.order_estimated_delivery_date::date THEN 'late'
           WHEN o.order_delivered_customer_date::date <= o.order_estimated_delivery_date::date THEN 'on_time'
       END AS delivery,
       ROUND(AVG(r.review_score), 2) AS avg_score,
       COUNT(r.review_id) AS reviews
FROM orders AS o
JOIN order_reviews AS r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY delivery
ORDER BY delivery;
-- Вовремя — 4,29 (89 944 отзыва), с опозданием — 2,27 (6 409), без даты доставки — 4,50 (8).
-- Недоставленные заказы, если убрать фильтр по статусу, — 1,76.
-- Опоздание отнимает 2 балла из 5. Гипотеза из 1.11 подтвердилась: оценку во многом ставит логистика.

-- 3.4 Доля опозданий по штатам покупателя
SELECT c.customer_state,
       COUNT(*) AS orders,
       ROUND(AVG(CASE
                     WHEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date THEN 1.0
                     ELSE 0
                 END) * 100, 2) AS late_pct
FROM orders AS o
JOIN customers AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY late_pct DESC;
-- Хуже всех Северо-Восток: AL 21%, MA 17%, SE 15%, PI 14%, CE 14%. RJ — 12% при 12 тыс. заказов.
-- А дальний Север (AM, RO, AP, AC) опаздывает в 3–4% случаев — реже, чем SP (4,5%).
-- Я ожидала «чем дальше, тем чаще опоздания», данные это не подтвердили. Нужно смотреть на обещанный срок.

-- 3.5 Реальный и обещанный срок доставки по штатам
SELECT c.customer_state,
       COUNT(*) AS orders,
       ROUND(AVG(o.order_estimated_delivery_date::date - o.order_purchase_timestamp::date), 2) AS avg_promised_days,
       ROUND(AVG(o.order_delivered_customer_date::date - o.order_purchase_timestamp::date), 2) AS avg_actual_days,
       ROUND(AVG(o.order_estimated_delivery_date::date - o.order_delivered_customer_date::date), 2) AS buffer_days
FROM orders AS o
JOIN customers AS c ON c.customer_id = o.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_actual_days DESC;
-- Реальный срок: SP — 8,7 дня, Север — 26–29. Но Северу обещают с запасом в 19–21 день, и опоздания там 3–4%.
-- Северо-Востоку запас дают 9–10 дней — опоздания 15–21%; у AL запас 8,7 дня и 21% опозданий.
-- Вывод: опоздания определяет запас в обещанном сроке, а не расстояние. RJ — отдельный случай:
-- запас как в SP, а опозданий втрое больше — там сроки сильно скачут.

-- 3.6 Категории, где доставка чаще всего дороже товара
SELECT p.product_category_name,
       COUNT(*) AS items,
       SUM(CASE WHEN oi.freight_value > oi.price THEN 1 ELSE 0 END) AS expensive_delivery,
       ROUND(AVG(CASE WHEN oi.freight_value > oi.price THEN 1.0 ELSE 0 END) * 100, 2) AS expensive_delivery_pct
FROM products AS p
JOIN order_items AS oi ON oi.product_id = p.product_id
GROUP BY p.product_category_name
HAVING COUNT(*) >= 100
ORDER BY expensive_delivery_pct DESC
LIMIT 10;
-- По доле: ёлочные украшения 22%, электроника 22%, бельё и пляжная мода 12%, знаки и безопасность 12%, аудио 10%.
-- По количеству: электроника (611), телефония (430), товары для дома (385).
-- HAVING >= 100: в категории из пяти позиций доля 40% — случайность, а не закономерность.

-- 3.7 Выручка по месяцам: позиции против платежей
-- Первая попытка была ошибочной: соединила orders + order_items + order_payments напрямую, и суммы раздулись —
-- каждая позиция повторилась на каждый платёж, и наоборот.
-- Исправление: свести обе таблицы к одной строке на заказ и только потом соединять.
SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
       ROUND(SUM(oi.items_total), 2) AS revenue_items,
       ROUND(SUM(op.paid_total), 2) AS revenue_payments
FROM orders AS o
JOIN (
    SELECT order_id,
           SUM(price + freight_value) AS items_total
    FROM order_items
    GROUP BY order_id
) AS oi ON oi.order_id = o.order_id
JOIN (
    SELECT order_id,
           SUM(payment_value) AS paid_total
    FROM order_payments
    GROUP BY order_id
) AS op ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY month
ORDER BY month;
-- Ноябрь 2017: по позициям 1 153 364, по платежам 1 153 528. Расхождение меньше 0,1% — скорее всего, проценты за рассрочку.
-- При прямом соединении было 1 194 874 и 1 548 683: завышение на 4% и на 34%. Вот цена лишнего JOIN.

-- 3.8 Доставленные заказы без отзыва (anti-join)
SELECT COUNT(*) AS without_reviews
FROM orders AS o
LEFT JOIN order_reviews AS r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND r.review_id IS NULL;
-- 646, около 0,7%. Отзыв есть почти у всех — значит, это анкета после доставки, а не добровольные отзывы.
-- Для выводов об оценках это важно: выборка почти полная, а не только самые недовольные.

-- 3.9 Заказы по месяцам с пустыми месяцами (календарь + LEFT JOIN)
SELECT cal.month,
       COUNT(o.order_id) AS orders
FROM (
    SELECT generate_series('2016-09-01'::date, '2018-10-01'::date, INTERVAL '1 month')::date AS month
) AS cal
LEFT JOIN orders AS o ON DATE_TRUNC('month', o.order_purchase_timestamp)::date = cal.month
GROUP BY cal.month
ORDER BY cal.month;
-- 26 месяцев, ноябрь 2016 теперь виден как 0. Считаю COUNT(o.order_id), а не COUNT(*):
-- иначе пустой месяц дал бы 1 — саму строку календаря.

-- 3.10 Продавец и покупатель в одном штате
SELECT CASE
           WHEN s.seller_state = c.customer_state THEN 'same_state'
           ELSE 'other_state'
       END AS route,
       COUNT(*) AS items,
       ROUND(AVG(o.order_delivered_customer_date::date - o.order_purchase_timestamp::date), 2) AS avg_days,
       ROUND(AVG(CASE
                     WHEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date THEN 1.0
                     ELSE 0
                 END) * 100, 2) AS late_pct
FROM orders AS o
JOIN customers AS c ON c.customer_id = o.customer_id
JOIN order_items AS oi ON oi.order_id = o.order_id
JOIN sellers AS s ON s.seller_id = oi.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY route
ORDER BY route DESC;
-- 36% позиций продаются внутри своего штата: 7,9 дня и 4,5% опозданий; между штатами — 15,0 дня и 7,8%.
-- Срок отличается вдвое, а опоздания — меньше: обещанный срок уже учитывает расстояние. Тот же вывод, что в 3.5.


-- ============================================================
-- Уровень 4: подзапросы, CTE
-- ============================================================

-- 4.1 Выручка по месяцам: позиции и платежи, предагрегация в CTE
WITH items_per_order AS (
    SELECT order_id,
           SUM(price + freight_value) AS revenue_from_oi
    FROM order_items
    GROUP BY order_id
),
payments_per_order AS (
    SELECT order_id,
           SUM(payment_value) AS revenue_from_op
    FROM order_payments
    GROUP BY order_id
)
SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
       ROUND(SUM(items.revenue_from_oi), 2) AS revenue_oi,
       ROUND(SUM(payments.revenue_from_op), 2) AS revenue_op
FROM orders AS o
JOIN items_per_order AS items ON items.order_id = o.order_id
JOIN payments_per_order AS payments ON payments.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY month;
-- Совпадает с 3.7 (ноябрь 2017: 1 153 364,20 / 1 153 528,05). Два способа — один ответ.

-- 4.2 Доля заказов дороже среднего заказа
WITH price_orders AS (
    SELECT oi.order_id,
           SUM(oi.price + oi.freight_value) AS price
    FROM order_items AS oi
    JOIN orders AS o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
)
SELECT ROUND(AVG(CASE
                     WHEN price > (SELECT AVG(price) FROM price_orders) THEN 1.0
                     ELSE 0
                 END) * 100, 2) AS pct
FROM price_orders;
-- 29,57%. Дороже среднего — меньше трети заказов: среднее тянут вверх редкие дорогие заказы.
-- Для «типичного заказа» здесь честнее медиана.

-- 4.3 Люди, покупавшие и в 2017, и в 2018
WITH people AS (
    SELECT c.customer_unique_id AS customer,
           EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
),
years_17_18 AS (
    SELECT customer
    FROM people
    WHERE year IN (2017, 2018)
    GROUP BY customer
    HAVING COUNT(DISTINCT year) = 2
)
SELECT COUNT(*) FROM years_17_18;
-- 682 человека. Условие «и в 2017, и в 2018» нельзя проверить внутри одной строки —
-- только по всем строкам человека (группа) или через IN.

-- Тренировка IN / EXISTS
-- A. Заказы с оплатой ваучером: IN
SELECT COUNT(*)
FROM orders
WHERE order_id IN (
    SELECT order_id
    FROM order_payments
    WHERE payment_type = 'voucher'
);
-- 3 866. Обычный JOIN дал бы больше, если в заказе несколько ваучеров; IN строки не размножает.

-- B. То же через EXISTS
SELECT COUNT(*)
FROM orders AS o
WHERE EXISTS (
    SELECT 1
    FROM order_payments AS op
    WHERE op.order_id = o.order_id
      AND op.payment_type = 'voucher'
);
-- 3 866 — тот же ответ.

-- C. Покупатели из штатов без единого продавца: NOT EXISTS и NOT IN
SELECT COUNT(*)
FROM customers AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM sellers AS s
    WHERE s.seller_state = c.customer_state
);
-- 807 покупателей (с EXISTS — 98 634, вместе 99 441, сходится). Штаты AL, AP, RR, TO:
-- там нет ни одного продавца, всё везут издалека. Кандидаты для привлечения местных продавцов.

SELECT DISTINCT c.customer_state
FROM customers AS c
WHERE c.customer_state NOT IN (
    SELECT seller_state
    FROM sellers
)
ORDER BY c.customer_state;

-- D. Заказы без единой позиции дороже 100
SELECT COUNT(*)
FROM orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM order_items AS oi
    WHERE oi.order_id = o.order_id
      AND oi.price > 100
);
-- 62 175.

WITH cheap_orders AS (
    SELECT oi.order_id
    FROM order_items AS oi
    GROUP BY oi.order_id
    HAVING MAX(oi.price) <= 100
)
SELECT COUNT(*) FROM cheap_orders;
-- 61 400. Разница 775 — заказы вообще без позиций. NOT EXISTS считает их «дешёвыми»:
-- у них нет ни одной позиции дороже 100. Формально верно, по смыслу — нет.

SELECT COUNT(*)
FROM orders AS o
WHERE NOT EXISTS (
    SELECT 1
    FROM order_items AS oi
    WHERE oi.order_id = o.order_id
);
-- 775 — проверка подтвердила.

-- 4.4 Продавцы без продаж в beleza_saude: NOT EXISTS и NOT IN
WITH sell_beleza_saude AS (
    SELECT oi.seller_id
    FROM order_items AS oi
    JOIN products AS p ON p.product_id = oi.product_id
    WHERE p.product_category_name = 'beleza_saude'
)
SELECT COUNT(s.seller_id)
FROM sellers AS s
WHERE NOT EXISTS (
    SELECT 1
    FROM sell_beleza_saude AS sbs
    WHERE sbs.seller_id = s.seller_id
);
-- 2 603.

WITH sell_beleza_saude AS (
    SELECT oi.seller_id
    FROM order_items AS oi
    JOIN products AS p ON p.product_id = oi.product_id
    WHERE p.product_category_name = 'beleza_saude'
)
SELECT COUNT(s.seller_id)
FROM sellers AS s
WHERE s.seller_id NOT IN (
    SELECT sbs.seller_id
    FROM sell_beleza_saude AS sbs
    WHERE sbs.seller_id IS NOT NULL
);
-- 2 603 — оба способа сходятся. Продавали в категории 492; 492 + 2 603 = 3 095, все продавцы на месте.

-- 4.5 Опоздание первого заказа и повторные покупки
WITH customers_dates AS (
    SELECT c.customer_unique_id AS unique_c_id,
           o.order_id,
           o.order_purchase_timestamp AS purchase_date,
           o.order_delivered_customer_date::date AS delivered_date,
           o.order_estimated_delivery_date::date AS estimated_date,
           o.order_status,
           CASE
               WHEN o.order_estimated_delivery_date::date >= o.order_delivered_customer_date::date THEN 'on_time'
               WHEN o.order_estimated_delivery_date::date < o.order_delivered_customer_date::date THEN 'late'
           END AS status_order
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
),
first_dates AS (
    SELECT unique_c_id,
           COUNT(DISTINCT purchase_date) AS count_dates,
           MIN(purchase_date) AS first_date
    FROM customers_dates
    GROUP BY unique_c_id
),
first_orders AS (
    SELECT cd.*,
           fd.count_dates
    FROM customers_dates AS cd
    JOIN first_dates AS fd
      ON fd.unique_c_id = cd.unique_c_id
     AND cd.purchase_date = fd.first_date
)
SELECT status_order,
       COUNT(DISTINCT unique_c_id) AS people,
       ROUND(AVG(CASE WHEN count_dates > 1 THEN 1.0 ELSE 0 END) * 100, 2) AS repeat_pct
FROM first_orders
WHERE order_status = 'delivered'
  AND status_order IS NOT NULL
GROUP BY status_order;
-- После опоздания первого заказа возвращаются 2,34% (из 6 355), после своевременного — 2,87% (из 86 919).
-- Опоздание снижает повторные покупки примерно на 18%. Но и при доставке вовремя возвращаются меньше 3% —
-- удержание зависит не только от логистики.
-- Попутно нашла ловушку: 276 человек оформили 2–3 заказа в одну секунду — это одна корзина, а не возврат.
-- Поэтому «вернулся» = COUNT(DISTINCT purchase_date) > 1: 2 740 человек, а не 2 997.

-- 4.6 Продавцы со средней оценкой ниже 3 и от 30 отзывов
WITH all_info AS (
    SELECT DISTINCT
           oi.seller_id,
           rev.review_id,
           rev.review_score
    FROM order_reviews AS rev
    JOIN order_items AS oi ON oi.order_id = rev.order_id
),
filter_for_sellers AS (
    SELECT seller_id,
           COUNT(review_id) AS count_reviews,
           ROUND(AVG(review_score), 2) AS avg_score
    FROM all_info
    GROUP BY seller_id
    HAVING COUNT(review_id) >= 30
       AND AVG(review_score) < 3
)
SELECT *
FROM filter_for_sellers
ORDER BY avg_score;
-- 2 продавца (2,33 и 2,69). Без DISTINCT отзыв засчитывался по разу на каждую позицию заказа, и выходило 6:
-- четверо попали бы в «плохие» только из-за ошибки подсчёта.

-- 4.7 Заказы, ехавшие дольше среднего по штату покупателя
-- Способ 1: CTE + JOIN
WITH state_info AS (
    SELECT c.customer_state,
           o.order_id,
           o.order_delivered_customer_date::date - o.order_purchase_timestamp::date AS delivery_days
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
),
avg_info_per_state AS (
    SELECT customer_state,
           COUNT(order_id) AS count_orders,
           AVG(delivery_days) AS avg_days
    FROM state_info
    GROUP BY customer_state
)
SELECT COUNT(*)
FROM state_info AS si
JOIN avg_info_per_state AS sa ON sa.customer_state = si.customer_state
WHERE si.delivery_days > sa.avg_days;
-- 37 172 из 96 470 (38,5%). Дольше среднего ехали меньше половины заказов:
-- среднее тянет вверх хвост очень долгих доставок. Для AC — 27 заказов, 0,079 с.

-- Способ 2: коррелированный подзапрос (только AC — на всей таблице очень медленно)
WITH state_info AS (
    SELECT c.customer_state,
           o.order_id,
           o.order_delivered_customer_date::date - o.order_purchase_timestamp::date AS delivery_days
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT COUNT(*)
FROM state_info AS si
WHERE si.delivery_days > (
          SELECT AVG(si2.delivery_days)
          FROM state_info AS si2
          WHERE si2.customer_state = si.customer_state
      )
  AND si.customer_state = 'AC';
-- 27 — ответ тот же, но 0,36 с против 0,079: подзапрос пересчитывает среднее для каждой строки.
-- На одном штате это терпимо, на всей таблице — уже нет.


-- ============================================================
-- Уровень 5: оконные функции
-- ============================================================

-- 5.1 Первый заказ каждого человека (ROW_NUMBER)
WITH numbered_orders AS (
    SELECT c.customer_unique_id,
           o.order_id,
           o.order_purchase_timestamp,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp, o.order_id) AS order_num
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
)
SELECT COUNT(*)
FROM numbered_orders
WHERE order_num = 1;
-- 96 096 — ровно один первый заказ на человека. MIN + JOIN в 4.5 давал 96 374:
-- человек с несколькими заказами в одну секунду попадал туда несколько раз.

-- 5.2 Последний доставленный заказ каждого человека с суммой
WITH order_revenue AS (
    SELECT order_id,
           SUM(price + freight_value) AS revenue
    FROM order_items
    GROUP BY order_id
),
numbered_orders AS (
    SELECT o.order_id,
           c.customer_unique_id,
           o.order_purchase_timestamp AS purchase_date,
           ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                              ORDER BY o.order_purchase_timestamp DESC, o.order_id) AS order_num
    FROM orders AS o
    JOIN customers AS c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
)
SELECT n.customer_unique_id,
       n.purchase_date,
       r.revenue
FROM numbered_orders AS n
JOIN order_revenue AS r ON r.order_id = n.order_id
WHERE n.order_num = 1;
-- 93 358 человек. Без фильтра delivered — 95 374, и ещё 722 человека выпадают из-за пустого последнего заказа.
-- Фильтр стоит до нумерации: так берётся предыдущий доставленный заказ, а не теряется сам человек.

-- 5.3 Топ-3 товара по выручке в каждой категории: ROW_NUMBER, RANK, DENSE_RANK
WITH category_info AS (
    SELECT p.product_id,
           p.product_category_name AS category,
           SUM(oi.price) AS revenue
    FROM order_items AS oi
    JOIN products AS p ON p.product_id = oi.product_id
    WHERE p.product_category_name IS NOT NULL
    GROUP BY p.product_id, p.product_category_name
),
ranked AS (
    SELECT product_id,
           category,
           revenue,
           ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC) AS rn,
           RANK()       OVER (PARTITION BY category ORDER BY revenue DESC) AS r,
           DENSE_RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS dr
    FROM category_info
)
SELECT *
FROM ranked
WHERE r <= 3
ORDER BY category, revenue DESC;
-- В двух категориях (fashion_roupa_infanto_juvenil, moveis_colchao_e_estofado) ничья на 3-м месте:
-- RANK показывает 4 товара, ROW_NUMBER молча теряет один. В cds_dvds_musicais товар всего один.

-- 5.4 Нарастающая выручка: с начала данных и с начала года
WITH general_info AS (
    SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
           SUM(oi.price + oi.freight_value) AS revenue
    FROM order_items AS oi
    JOIN orders AS o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 1
)
SELECT month,
       revenue,
       SUM(revenue) OVER (ORDER BY month) AS running_total,
       SUM(revenue) OVER (PARTITION BY DATE_TRUNC('year', month) ORDER BY month) AS ytd_total
FROM general_info
ORDER BY month;
-- Всего за выгрузку 15 419 773,75. Январь–август: 2017 — 3 472 898, 2018 — 8 451 585, рост в 2,4 раза.
-- Если сравнить полный 2017 с неполным 2018, вышло бы всего +22%. Сравниваю только одинаковые периоды.

-- 5.5 Рост заказов к прошлому месяцу (LAG)
WITH monthly AS (
    SELECT DATE_TRUNC('month', o.order_purchase_timestamp)::date AS month,
           COUNT(DISTINCT o.order_id) AS orders
    FROM order_items AS oi
    JOIN orders AS o ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
    GROUP BY 1
),
with_prev AS (
    SELECT month,
           orders,
           LAG(orders) OVER (ORDER BY month) AS prev_orders
    FROM monthly
)
SELECT month,
       orders,
       prev_orders,
       ROUND((orders - prev_orders) * 100.0 / prev_orders, 1) AS growth_pct
FROM with_prev
ORDER BY month;
-- 2016 убираю: в сентябре и декабре по одному заказу, а ноября нет вовсе — LAG сравнил бы декабрь с октябрём.
-- Фильтр ставлю до окна: в финальном WHERE январь 2017 всё равно сравнился бы с декабрём 2016 (+74 900%).
-- Самый сильный рост — ноябрь 2017, +62,8% (Black Friday), потом декабрь −24,4%.
-- В 2018 заказы стоят на плато 6–7 тыс. в месяц: рост год к году из 5.4 набран ещё в 2017-м.
