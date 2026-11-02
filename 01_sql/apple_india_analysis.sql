
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS raw.apple_sales;
CREATE TABLE raw.apple_sales (
    invoice TEXT, transaction_type TEXT, original_invoice TEXT, invoicedate TEXT,
    stockcode TEXT, description TEXT, category TEXT, product_family TEXT,
    configuration TEXT, color TEXT, product_launch_date TEXT, quantity TEXT,
    unit_price_inr TEXT, gross_amount_inr TEXT, discount_type TEXT,
    discount_amount_inr TEXT, trade_in_device TEXT, trade_in_credit_inr TEXT,
    net_amount_inr TEXT, gst_amount_inr TEXT, applecare_plus TEXT,
    applecare_price_inr TEXT, total_amount_inr TEXT, customer_id TEXT,
    customer_type TEXT, customer_segment TEXT, company_industry TEXT, gender TEXT,
    age_group TEXT, city TEXT, state TEXT, city_tier TEXT, region TEXT, channel TEXT,
    store_or_partner TEXT, payment_method TEXT, card_bank TEXT, emi_tenure_months TEXT,
    is_gift TEXT, occasion TEXT, recipient TEXT, gift_message TEXT, engraving TEXT,
    fulfilment_type TEXT, delivery_days TEXT, order_status TEXT, return_reason TEXT,
    customer_rating TEXT
);

SELECT COUNT(*) FROM raw.apple_sales;

DROP TABLE IF EXISTS analytics.sales;
CREATE TABLE analytics.sales AS
SELECT
    invoice,
    transaction_type,
    original_invoice,
    to_timestamp(invoicedate, 'DD-MM-YYYY HH24:MI')::timestamp AS invoice_date,
    stockcode, description, category, product_family, configuration, color,
    to_date(product_launch_date, 'DD-MM-YYYY')                 AS product_launch_date,
    quantity::int                    AS quantity,
    unit_price_inr::numeric(12,2)    AS unit_price,
    gross_amount_inr::numeric(14,2)  AS gross_amount,
    discount_type,
    discount_amount_inr::numeric(14,2) AS discount_amount,
    trade_in_device,
    trade_in_credit_inr::numeric(14,2) AS trade_in_credit,
    net_amount_inr::numeric(14,2)    AS net_amount,
    gst_amount_inr::numeric(14,2)    AS gst_amount,
    applecare_plus,
    applecare_price_inr::numeric(14,2) AS applecare_price,
    total_amount_inr::numeric(14,2)  AS total_amount,
    customer_id, customer_type, customer_segment, company_industry, gender, age_group,
    city, state, city_tier::int AS city_tier, region, channel, store_or_partner,
    payment_method, card_bank, emi_tenure_months::int AS emi_tenure_months,
    is_gift, occasion, recipient, gift_message, engraving, fulfilment_type,
    delivery_days::int AS delivery_days, order_status, return_reason,
    customer_rating::int AS customer_rating
FROM raw.apple_sales;

CREATE INDEX ON analytics.sales (invoice_date);
CREATE INDEX ON analytics.sales (customer_id);
CREATE INDEX ON analytics.sales (invoice);


-------------ANALYSIS--------------------

SELECT
    SUM(total_amount)                                                      AS net_revenue,
    SUM(total_amount) FILTER (WHERE transaction_type = 'Sale')             AS gross_sales,
    -SUM(total_amount) FILTER (WHERE transaction_type <> 'Sale')           AS refunds,
    COUNT(DISTINCT invoice) FILTER (WHERE transaction_type = 'Sale')       AS orders,
    COUNT(DISTINCT customer_id)                                            AS customers,
    SUM(quantity) FILTER (WHERE transaction_type = 'Sale')                 AS units_sold,
    ROUND(SUM(total_amount) FILTER (WHERE transaction_type = 'Sale')
          / COUNT(DISTINCT invoice) FILTER (WHERE transaction_type = 'Sale'), 0) AS avg_order_value,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status <> 'Completed' AND transaction_type = 'Sale')
          / COUNT(*) FILTER (WHERE transaction_type = 'Sale'), 2)          AS return_or_cancel_rate_pct
FROM analytics.sales;

--MONTHLY TREND AND GROWTH ANALYSIS

WITH m AS (
    SELECT date_trunc('month', invoice_date)::date AS month,
           SUM(total_amount)                       AS revenue,
           COUNT(DISTINCT invoice) FILTER (WHERE transaction_type = 'Sale') AS orders
    FROM analytics.sales
    GROUP BY 1
)
SELECT month,
       ROUND(revenue / 1e7, 2)                                         AS revenue_cr,
       orders,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1)                  AS mom_growth_pct,
       ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY month))
             / LAG(revenue, 12) OVER (ORDER BY month), 1)              AS yoy_growth_pct
FROM m
ORDER BY month;

--BUSIEST WEEKDAYS

SELECT to_char(invoice_date, 'ID-Dy') AS weekday,
       COUNT(DISTINCT invoice)        AS orders,
       ROUND(SUM(total_amount) / 1e7, 1) AS revenue_cr
FROM analytics.sales
WHERE transaction_type = 'Sale'
GROUP BY 1
ORDER BY 1;

--HOUR OF DAY ONLINE VS OFFLINE STORE

SELECT channel,
       EXTRACT(HOUR FROM invoice_date)::int AS hour_of_day,
       COUNT(DISTINCT invoice)              AS orders
FROM analytics.sales
WHERE transaction_type = 'Sale' AND channel IN ('Apple Store Online', 'Apple Retail Store')
GROUP BY 1, 2
ORDER BY 1, 2;

--PRODUCTS : CATEGORY SHARE

SELECT category,
       ROUND(SUM(total_amount) / 1e7, 1)                               AS revenue_cr,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS revenue_share_pct,
       SUM(quantity) FILTER (WHERE transaction_type = 'Sale')         AS units,
       ROUND(AVG(unit_price) FILTER (WHERE transaction_type = 'Sale'), 0) AS avg_price
FROM analytics.sales
GROUP BY category
ORDER BY revenue_cr DESC;

--TOP 3 PRODUCTS PER CATEGORY

WITH p AS (
    SELECT category, product_family,
           SUM(total_amount) AS revenue,
           SUM(quantity) FILTER (WHERE transaction_type = 'Sale') AS units
    FROM analytics.sales
    GROUP BY 1, 2
)
SELECT *
FROM (
    SELECT category, product_family,
           ROUND(revenue / 1e7, 1) AS revenue_cr, units,
           RANK() OVER (PARTITION BY category ORDER BY revenue DESC) AS rank_in_category
    FROM p
) r
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

-- CHANNEL COMPARISON

SELECT channel,
       ROUND(SUM(total_amount) / 1e7, 1)                                    AS revenue_cr,
       ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(discount_amount) FILTER (WHERE transaction_type = 'Sale')
             / SUM(gross_amount) FILTER (WHERE transaction_type = 'Sale'), 1) AS avg_discount_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Returned' AND transaction_type = 'Sale')
             / COUNT(*) FILTER (WHERE transaction_type = 'Sale'), 2)          AS return_rate_pct
FROM analytics.sales
GROUP BY channel
ORDER BY revenue_cr DESC;

--APPLE STORE COMPARISON
SELECT store_or_partner AS apple_store,
       MIN(invoice_date)::date            AS first_sale,
       COUNT(DISTINCT invoice)            AS orders,
       ROUND(SUM(total_amount) / 1e7, 1)  AS revenue_cr,
       ROUND(SUM(total_amount) / COUNT(DISTINCT invoice)) AS avg_order_value
FROM analytics.sales
WHERE channel = 'Apple Retail Store'
GROUP BY 1
ORDER BY revenue_cr DESC;

-- BENGALURU BEFORE VS AFTER APPLE HEBBAL OPENED
SELECT CASE WHEN invoice_date < '2025-09-02' THEN '1_before Hebbal opened'
            ELSE '2_after Hebbal opened' END AS period,
       channel,
       ROUND(100.0 * SUM(total_amount)
             / SUM(SUM(total_amount)) OVER (PARTITION BY CASE WHEN invoice_date < '2025-09-02' THEN 1 ELSE 2 END), 1)
             AS share_of_bengaluru_revenue_pct
FROM analytics.sales
WHERE city = 'Bengaluru' AND customer_segment <> 'Corporate'
GROUP BY 1, 2, CASE WHEN invoice_date < '2025-09-02' THEN 1 ELSE 2 END
ORDER BY 1, 3 DESC;

--APPLE CARE RATE

SELECT channel,
       ROUND(100.0 * COUNT(*) FILTER (WHERE applecare_plus = 'Yes')
             / COUNT(*), 1) AS applecare_attach_pct
FROM analytics.sales
WHERE transaction_type = 'Sale' AND category IN ('iPhone', 'Mac', 'iPad', 'Apple Watch')
GROUP BY channel
ORDER BY 2 DESC;

-- FESTIVAL GIFTING (FESTIVAL UPLIFT)
WITH daily AS (
    SELECT invoice_date::date AS day, SUM(total_amount) AS revenue
    FROM analytics.sales
    GROUP BY 1
),
labelled AS (
    SELECT day, revenue,
           CASE
             WHEN day BETWEEN '2024-10-27' AND '2024-11-01'
               OR day BETWEEN '2025-10-08' AND '2025-10-21'
               OR day BETWEEN '2026-10-15' AND '2026-10-26' THEN 'Diwali period'
             WHEN day BETWEEN '2025-09-19' AND '2025-09-30'
               OR day BETWEEN '2026-09-18' AND '2026-09-30' THEN 'iPhone launch weeks'
             WHEN (EXTRACT(MONTH FROM day) = 12 AND EXTRACT(DAY FROM day) >= 18) THEN 'Christmas & New Year'
             WHEN (EXTRACT(MONTH FROM day) = 2 AND EXTRACT(DAY FROM day) BETWEEN 7 AND 14) THEN 'Valentine week'
             ELSE 'Normal day'
           END AS period
    FROM daily
)
SELECT period,
       COUNT(*)                                        AS days,
       ROUND(AVG(revenue) / 1e5, 1)                    AS avg_daily_revenue_lakh,
       ROUND(AVG(revenue) / AVG(AVG(revenue)) FILTER (WHERE period = 'Normal day') OVER (), 2) AS times_a_normal_day
FROM labelled
GROUP BY period
ORDER BY times_a_normal_day DESC;

-- occasion * recipient

SELECT occasion, recipient,
       COUNT(DISTINCT invoice)                  AS orders,
       ROUND(SUM(total_amount) / 1e7, 2)        AS revenue_cr
FROM analytics.sales
WHERE is_gift = 'Yes' AND transaction_type = 'Sale' AND customer_segment <> 'Corporate'
GROUP BY 1, 2
ORDER BY orders DESC
LIMIT 15;

--gift vs self purchase

SELECT is_gift,
       COUNT(DISTINCT invoice)                                     AS orders,
       ROUND(SUM(total_amount) / COUNT(DISTINCT invoice), 0)       AS avg_order_value,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Returned') / COUNT(*), 2) AS return_rate_pct,
       mode() WITHIN GROUP (ORDER BY category)                     AS most_common_category
FROM analytics.sales
WHERE transaction_type = 'Sale' AND customer_segment <> 'Corporate'
GROUP BY is_gift;

--CUSTOMERS (most valuable customers)

WITH base AS (
    SELECT customer_id,
           ('2026-10-27'::date - MAX(invoice_date)::date)   AS recency_days,
           COUNT(DISTINCT invoice)                          AS frequency,
           SUM(total_amount)                                AS monetary
    FROM analytics.sales
    WHERE transaction_type = 'Sale'
      AND customer_id IS NOT NULL
      AND customer_segment <> 'Corporate'
    GROUP BY customer_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
           NTILE(5) OVER (ORDER BY frequency)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary)          AS m_score
    FROM base
),
segmented AS (
    SELECT *,
           CASE
             WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
             WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
             WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
             WHEN r_score  = 3                                   THEN 'Needs Attention'
             WHEN r_score  = 2                                   THEN 'At Risk'
             ELSE                                                     'Lost'
           END AS segment
    FROM scored
)
SELECT segment,
       COUNT(*)                                                       AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_customers,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)   AS pct_revenue,
       ROUND(AVG(recency_days))                                       AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                       AS avg_orders,
       ROUND(AVG(monetary))                                           AS avg_spend
FROM segmented
GROUP BY segment
ORDER BY pct_revenue DESC;

--how long do customers take to come back

WITH orders AS (
    SELECT DISTINCT customer_id, invoice, invoice_date::date AS d
    FROM analytics.sales
    WHERE transaction_type = 'Sale' AND customer_id LIKE 'CUST-%'
),
gaps AS (
    SELECT customer_id,
           d - LAG(d) OVER (PARTITION BY customer_id ORDER BY d) AS days_since_previous
    FROM orders
)
SELECT
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY days_since_previous) AS median_gap_days,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_since_previous) AS p75_gap_days,
    PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY days_since_previous) AS p90_gap_days
FROM gaps
WHERE days_since_previous IS NOT NULL;

--CHURN RATE

WITH last_buy AS (
    SELECT customer_id, MAX(invoice_date)::date AS last_purchase
    FROM analytics.sales
    WHERE transaction_type = 'Sale' AND customer_id LIKE 'CUST-%'
    GROUP BY customer_id
)
SELECT COUNT(*)                                                                 AS customers,
       COUNT(*) FILTER (WHERE '2026-10-27'::date - last_purchase > 180)         AS churned_180d,
       ROUND(100.0 * COUNT(*) FILTER (WHERE '2026-10-27'::date - last_purchase > 180) / COUNT(*), 1) AS churn_rate_pct
FROM last_buy;


--PAYMENTS SECTION

SELECT CASE WHEN order_value < 10000  THEN '1. Under 10K'
            WHEN order_value < 50000  THEN '2. 10K–50K'
            WHEN order_value < 100000 THEN '3. 50K–1L'
            ELSE                           '4. Above 1L' END AS order_band,
       payment_method,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY
            CASE WHEN order_value < 10000 THEN 1 WHEN order_value < 50000 THEN 2
                 WHEN order_value < 100000 THEN 3 ELSE 4 END), 1) AS pct_of_band
FROM (
    SELECT invoice, MAX(payment_method) AS payment_method, SUM(gross_amount) AS order_value
    FROM analytics.sales
    WHERE transaction_type = 'Sale' AND customer_segment <> 'Corporate'
    GROUP BY invoice
) o
GROUP BY 1, 2, CASE WHEN order_value < 10000 THEN 1 WHEN order_value < 50000 THEN 2
                    WHEN order_value < 100000 THEN 3 ELSE 4 END
ORDER BY 1, orders DESC;



--GEOGRAPHY

SELECT city, state, city_tier,
       ROUND(SUM(total_amount) / 1e7, 1) AS revenue_cr,
       COUNT(DISTINCT customer_id)       AS customers,
       RANK() OVER (ORDER BY SUM(total_amount) DESC) AS city_rank
FROM analytics.sales
GROUP BY city, state, city_tier
ORDER BY city_rank
LIMIT 10;