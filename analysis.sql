/* ============================================================================
 *  PROJECT      : Olist — Customer Retention, Cohort & RFM Analysis (Project 2)
 *  FILE         : analysis.sql
 *  PURPOSE      : 15 retention-focused queries grouped into 6 sections.
 *                 Every query is preceded by the BUSINESS QUESTION it answers.
 *  AUTHOR       : Khushi
 *  PREREQ       : schema.sql has been executed (indexes created).
 *  CONVENTIONS  :
 *      - Customer identity = customer_unique_id  (NOT customer_id, which is
 *        regenerated per-order in the Olist dataset).
 *      - Revenue universe  = orders WHERE order_status = 'delivered'.
 *      - Snapshot date     = MAX(order_purchase_timestamp) — the dataset's
 *        analytical "today" for recency / churn calculations.
 *      - Cohort            = first delivered-order month per customer.
 *      - Churn definition  = no delivered order in the last 90 days from
 *        snapshot date (~2× the average inter-order gap of 45 days).
 * ============================================================================
 */

USE olist_retention;


/* ############################################################################
 *  SECTION A : SANITY CHECKS & FOUNDATIONS
 * ############################################################################
 */

-- Q1. How many unique people actually exist?
--     customer_id is per-order; customer_unique_id is per-person.
--     This is the single most important distinction for retention work.
SELECT
    COUNT(*)                                AS customer_id_rows,
    COUNT(DISTINCT customer_unique_id)      AS unique_people,
    COUNT(*) - COUNT(DISTINCT customer_unique_id) AS extra_rows_from_repeat_buyers
FROM customers;


-- Q2. What is the analytical date range of this dataset?
SELECT
    MIN(order_purchase_timestamp)                          AS earliest_order,
    MAX(order_purchase_timestamp)                          AS snapshot_date,
    DATEDIFF(MAX(order_purchase_timestamp),
             MIN(order_purchase_timestamp))                AS days_in_dataset,
    ROUND(DATEDIFF(MAX(order_purchase_timestamp),
                   MIN(order_purchase_timestamp)) / 30.44, 1) AS approx_months
FROM orders
WHERE order_status = 'delivered';


-- Q3. Repeat-buyer baseline — the headline number that motivates this whole
--     project. How many unique customers ever placed >1 delivered order?
WITH per_customer AS (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS orders
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                                  AS unique_customers,
    SUM(CASE WHEN orders = 1 THEN 1 ELSE 0 END)               AS one_time_buyers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)               AS repeat_buyers,
    ROUND(SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 2)                                      AS repeat_rate_pct
FROM per_customer;


/* ############################################################################
 *  SECTION B : COHORT RETENTION MATRIX
 * ############################################################################
 */

-- Q4. Cohort assignment — what is each customer's first-purchase month?
--     Preview only. Used downstream as the cohort label.
SELECT
    c.customer_unique_id,
    DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m') AS cohort
FROM   customers c
JOIN   orders    o ON o.customer_id = c.customer_id
WHERE  o.order_status = 'delivered'
GROUP BY c.customer_unique_id
LIMIT 20;


-- Q5. Cohort sizes — how many NEW customers did the platform acquire each month?
WITH first_purchase AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m') AS cohort
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    cohort,
    COUNT(*)                                                AS new_customers,
    SUM(COUNT(*)) OVER (ORDER BY cohort)                    AS cumulative_customers
FROM first_purchase
GROUP BY cohort
ORDER BY cohort;


-- Q6. Cohort retention matrix (absolute customer counts) — the centerpiece.
--     Rows  = first-purchase month (cohort).
--     Cols  = months since first purchase (M0 = first purchase itself).
--     Cell  = how many customers from that cohort were active that month.
WITH first_purchase AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m-01') AS cohort_date
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
activity AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS activity_date
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
),
cohort_activity AS (
    SELECT fp.cohort_date,
           a.customer_unique_id,
           TIMESTAMPDIFF(MONTH, fp.cohort_date, a.activity_date) AS month_number
    FROM   first_purchase fp
    JOIN   activity       a ON a.customer_unique_id = fp.customer_unique_id
)
SELECT
    DATE_FORMAT(cohort_date, '%Y-%m') AS cohort,
    COUNT(DISTINCT CASE WHEN month_number = 0 THEN customer_unique_id END) AS m0,
    COUNT(DISTINCT CASE WHEN month_number = 1 THEN customer_unique_id END) AS m1,
    COUNT(DISTINCT CASE WHEN month_number = 2 THEN customer_unique_id END) AS m2,
    COUNT(DISTINCT CASE WHEN month_number = 3 THEN customer_unique_id END) AS m3,
    COUNT(DISTINCT CASE WHEN month_number = 4 THEN customer_unique_id END) AS m4,
    COUNT(DISTINCT CASE WHEN month_number = 5 THEN customer_unique_id END) AS m5,
    COUNT(DISTINCT CASE WHEN month_number = 6 THEN customer_unique_id END) AS m6
FROM cohort_activity
GROUP BY cohort_date
ORDER BY cohort_date;


-- Q7. Cohort retention matrix (PERCENTAGES) — the version recruiters love.
--     Each cell = % of the original cohort still active in that month.
WITH first_purchase AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m-01') AS cohort_date
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
activity AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS activity_date
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
),
cohort_activity AS (
    SELECT fp.cohort_date,
           a.customer_unique_id,
           TIMESTAMPDIFF(MONTH, fp.cohort_date, a.activity_date) AS month_number
    FROM   first_purchase fp
    JOIN   activity       a ON a.customer_unique_id = fp.customer_unique_id
),
agg AS (
    SELECT
        cohort_date,
        COUNT(DISTINCT CASE WHEN month_number = 0 THEN customer_unique_id END) AS m0,
        COUNT(DISTINCT CASE WHEN month_number = 1 THEN customer_unique_id END) AS m1,
        COUNT(DISTINCT CASE WHEN month_number = 2 THEN customer_unique_id END) AS m2,
        COUNT(DISTINCT CASE WHEN month_number = 3 THEN customer_unique_id END) AS m3,
        COUNT(DISTINCT CASE WHEN month_number = 4 THEN customer_unique_id END) AS m4,
        COUNT(DISTINCT CASE WHEN month_number = 5 THEN customer_unique_id END) AS m5,
        COUNT(DISTINCT CASE WHEN month_number = 6 THEN customer_unique_id END) AS m6
    FROM cohort_activity
    GROUP BY cohort_date
)
SELECT
    DATE_FORMAT(cohort_date, '%Y-%m')              AS cohort,
    m0                                             AS cohort_size,
    ROUND(m1 * 100.0 / NULLIF(m0,0), 2)            AS m1_pct,
    ROUND(m2 * 100.0 / NULLIF(m0,0), 2)            AS m2_pct,
    ROUND(m3 * 100.0 / NULLIF(m0,0), 2)            AS m3_pct,
    ROUND(m4 * 100.0 / NULLIF(m0,0), 2)            AS m4_pct,
    ROUND(m5 * 100.0 / NULLIF(m0,0), 2)            AS m5_pct,
    ROUND(m6 * 100.0 / NULLIF(m0,0), 2)            AS m6_pct
FROM agg
ORDER BY cohort_date;


/* ############################################################################
 *  SECTION C : RFM SEGMENTATION  (Recency, Frequency, Monetary)
 * ############################################################################
 */

-- Q8. RFM raw values per customer — preview the underlying numbers.
--     Recency  = days since the customer's last delivered order.
--     Frequency = number of distinct delivered orders.
--     Monetary  = total spend (price + freight).
WITH ref_date AS (
    SELECT MAX(order_purchase_timestamp) AS snapshot_date
    FROM   orders
    WHERE  order_status = 'delivered'
)
SELECT
    c.customer_unique_id,
    DATEDIFF((SELECT snapshot_date FROM ref_date),
             MAX(o.order_purchase_timestamp))                AS recency_days,
    COUNT(DISTINCT o.order_id)                               AS frequency,
    ROUND(SUM(oi.price + oi.freight_value), 2)               AS monetary_brl
FROM   customers   c
JOIN   orders      o  ON o.customer_id  = c.customer_id
JOIN   order_items oi ON oi.order_id    = o.order_id
WHERE  o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY monetary_brl DESC
LIMIT 20;


-- Q9. RFM scoring with NTILE(5) — split each metric into 5 equal-size buckets.
--     Score 5 = best, Score 1 = worst (for all three dimensions).
--     R is sorted DESC because LOWER recency_days = MORE recent = better.
WITH ref_date AS (
    SELECT MAX(order_purchase_timestamp) AS snapshot_date
    FROM   orders
    WHERE  order_status = 'delivered'
),
rfm_raw AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF((SELECT snapshot_date FROM ref_date),
                 MAX(o.order_purchase_timestamp))            AS recency_days,
        COUNT(DISTINCT o.order_id)                           AS frequency,
        ROUND(SUM(oi.price + oi.freight_value), 2)           AS monetary_brl
    FROM   customers   c
    JOIN   orders      o  ON o.customer_id = c.customer_id
    JOIN   order_items oi ON oi.order_id   = o.order_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary_brl,
    NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,  -- 5 = most recent
    NTILE(5) OVER (ORDER BY frequency    ASC)   AS f_score,  -- 5 = most orders
    NTILE(5) OVER (ORDER BY monetary_brl ASC)   AS m_score   -- 5 = highest spend
FROM rfm_raw
LIMIT 20;


-- Q10. RFM segment classification — turn raw scores into business labels.
--      Champions, Loyal, At Risk, Lost, etc.
--      Includes customer count + revenue contribution per segment.
WITH ref_date AS (
    SELECT MAX(order_purchase_timestamp) AS snapshot_date
    FROM   orders
    WHERE  order_status = 'delivered'
),
rfm_raw AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF((SELECT snapshot_date FROM ref_date),
                 MAX(o.order_purchase_timestamp))     AS recency_days,
        COUNT(DISTINCT o.order_id)                    AS frequency,
        SUM(oi.price + oi.freight_value)              AS monetary_brl
    FROM   customers   c
    JOIN   orders      o  ON o.customer_id = c.customer_id
    JOIN   order_items oi ON oi.order_id   = o.order_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary_brl,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency    ASC)  AS f_score,
        NTILE(5) OVER (ORDER BY monetary_brl ASC)  AS m_score
    FROM rfm_raw
),
segmented AS (
    SELECT *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 4 AND f_score >= 3                  THEN 'Loyal Customers'
            WHEN r_score >= 4 AND f_score <= 2                  THEN 'New Customers'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 4 THEN 'Cant Lose Them'
            WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost'
            ELSE 'Needs Attention'
        END                                                     AS segment
    FROM rfm_scored
)
SELECT
    segment,
    COUNT(*)                                                    AS customers,
    ROUND(COUNT(*)            * 100.0 / SUM(COUNT(*))            OVER (), 2)
                                                                AS customer_pct,
    ROUND(SUM(monetary_brl), 2)                                 AS revenue_brl,
    ROUND(SUM(monetary_brl)  * 100.0 / SUM(SUM(monetary_brl))    OVER (), 2)
                                                                AS revenue_pct
FROM segmented
GROUP BY segment
ORDER BY revenue_brl DESC;


/* ############################################################################
 *  SECTION D : CHURN ANALYSIS
 *  Definition: a customer is "churned" if they have not placed a delivered
 *  order in the last 90 days from the snapshot date.
 *  Reasoning : average inter-order gap in this dataset is ~45 days.
 *              90 days = 2× the norm, a defensible churn threshold.
 * ############################################################################
 */

-- Q11. Overall churn rate — what % of customers are inactive 90+ days?
WITH ref_date AS (
    SELECT MAX(order_purchase_timestamp) AS snapshot_date
    FROM   orders
    WHERE  order_status = 'delivered'
),
last_purchase AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)                          AS last_order_date,
        DATEDIFF((SELECT snapshot_date FROM ref_date),
                 MAX(o.order_purchase_timestamp))                AS days_since_last
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                                     AS total_customers,
    SUM(CASE WHEN days_since_last <= 90 THEN 1 ELSE 0 END)       AS active,
    SUM(CASE WHEN days_since_last >  90 THEN 1 ELSE 0 END)       AS churned,
    ROUND(SUM(CASE WHEN days_since_last > 90 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                                 AS churn_rate_pct
FROM last_purchase;


-- Q12. Churn rate by cohort — which months produced the stickiest customers?
--      Old cohorts naturally show higher churn (more time to go silent),
--      so compare carefully — this is a survivorship-bias trap.
WITH ref_date AS (
    SELECT MAX(order_purchase_timestamp) AS snapshot_date
    FROM   orders
    WHERE  order_status = 'delivered'
),
customer_lifecycle AS (
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m')      AS cohort,
        DATEDIFF((SELECT snapshot_date FROM ref_date),
                 MAX(o.order_purchase_timestamp))                  AS days_since_last
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    cohort,
    COUNT(*)                                                       AS cohort_size,
    SUM(CASE WHEN days_since_last > 90 THEN 1 ELSE 0 END)          AS churned,
    ROUND(SUM(CASE WHEN days_since_last > 90 THEN 1 ELSE 0 END)
          * 100.0 / COUNT(*), 2)                                   AS churn_rate_pct
FROM customer_lifecycle
GROUP BY cohort
ORDER BY cohort;


/* ############################################################################
 *  SECTION E : COHORT LIFETIME VALUE
 * ############################################################################
 */

-- Q13. Lifetime revenue & average LTV per cohort.
--      Which acquisition month produced the most valuable customers overall?
WITH first_purchase AS (
    SELECT c.customer_unique_id,
           DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m') AS cohort
    FROM   customers c
    JOIN   orders    o ON o.customer_id = c.customer_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_revenue AS (
    SELECT c.customer_unique_id,
           SUM(oi.price + oi.freight_value) AS lifetime_revenue
    FROM   customers   c
    JOIN   orders      o  ON o.customer_id = c.customer_id
    JOIN   order_items oi ON oi.order_id   = o.order_id
    WHERE  o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    fp.cohort,
    COUNT(*)                                                     AS cohort_size,
    ROUND(SUM(cr.lifetime_revenue), 2)                           AS total_revenue_brl,
    ROUND(AVG(cr.lifetime_revenue), 2)                           AS avg_ltv_brl,
    ROUND(MAX(cr.lifetime_revenue), 2)                           AS max_ltv_brl
FROM   first_purchase  fp
JOIN   customer_revenue cr ON cr.customer_unique_id = fp.customer_unique_id
GROUP BY fp.cohort
ORDER BY fp.cohort;


/* ############################################################################
 *  SECTION F : ORDER FUNNEL  (Placed → Paid → Shipped → Delivered → Reviewed)
 * ############################################################################
 */

-- Q14. Funnel headcount at each step (absolute numbers).
SELECT
    COUNT(*)                                                              AS placed,
    SUM(CASE WHEN order_approved_at             IS NOT NULL THEN 1 ELSE 0 END) AS paid,
    SUM(CASE WHEN order_delivered_carrier_date  IS NOT NULL THEN 1 ELSE 0 END) AS shipped,
    SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS delivered,
    (SELECT COUNT(DISTINCT order_id) FROM reviews)                        AS reviewed
FROM orders;


-- Q15. Funnel as a clean step-by-step report with conversion %.
--      Shows both absolute count and % of original "Placed" — recruiters
--      love seeing both views in one table.
WITH funnel AS (
    SELECT
        COUNT(*)                                                                  AS placed,
        SUM(CASE WHEN order_approved_at             IS NOT NULL THEN 1 ELSE 0 END) AS paid,
        SUM(CASE WHEN order_delivered_carrier_date  IS NOT NULL THEN 1 ELSE 0 END) AS shipped,
        SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS delivered,
        (SELECT COUNT(DISTINCT order_id) FROM reviews)                             AS reviewed
    FROM orders
)
SELECT '1. Placed'    AS step, placed     AS orders, 100.00                            AS pct_of_placed FROM funnel
UNION ALL
SELECT '2. Paid',           paid,        ROUND(paid      * 100.0 / placed, 2)          FROM funnel
UNION ALL
SELECT '3. Shipped',        shipped,     ROUND(shipped   * 100.0 / placed, 2)          FROM funnel
UNION ALL
SELECT '4. Delivered',      delivered,   ROUND(delivered * 100.0 / placed, 2)          FROM funnel
UNION ALL
SELECT '5. Reviewed',       reviewed,    ROUND(reviewed  * 100.0 / placed, 2)          FROM funnel;


/* ============================================================================
 *  END OF analysis.sql
 * ============================================================================
 */
