-- sql/queries.sql
-- NYC Real Estate Analysis Queries
-- Core business intelligence queries for dashboard creation

-- =============================================================================
-- 1. MEDIAN SALE PRICE TRENDS BY MONTH AND BOROUGH
-- =============================================================================
-- Monthly median sale prices to identify trends and seasonality
SELECT 
    strftime('%Y-%m', sale_date) as month,
    borough,
    COUNT(*) as transactions,
    CAST(AVG(sale_price) AS INTEGER) as avg_price,
    CAST(MIN(sale_price) AS INTEGER) as min_price,
    CAST(MAX(sale_price) AS INTEGER) as max_price,
    -- Calculate median using percentile
    CAST(
        (SELECT sale_price FROM sales s2 
         WHERE s2.borough = s1.borough 
         AND strftime('%Y-%m', s2.sale_date) = strftime('%Y-%m', s1.sale_date)
         AND s2.sale_price IS NOT NULL
         ORDER BY s2.sale_price 
         LIMIT 1 OFFSET CAST((COUNT(*) - 1) / 2 AS INTEGER)
        ) AS INTEGER
    ) as median_price
FROM sales s1
WHERE sale_price > 0 
    AND sale_date >= date('2019-01-01')
    AND borough IS NOT NULL
GROUP BY strftime('%Y-%m', sale_date), borough
HAVING COUNT(*) >= 5  -- Ensure sufficient sample size
ORDER BY month, borough;

-- =============================================================================
-- 2. YEAR-OVER-YEAR PRICE GROWTH BY BOROUGH
-- =============================================================================
-- Calculate YoY growth rates to identify hot markets
WITH yearly_medians AS (
    SELECT 
        sale_year,
        borough,
        COUNT(*) as transactions,
        CAST(AVG(sale_price) AS INTEGER) as avg_price
    FROM sales
    WHERE sale_price > 0 AND borough IS NOT NULL
    GROUP BY sale_year, borough
    HAVING COUNT(*) >= 10
)
SELECT 
    current.borough,
    current.sale_year,
    current.avg_price as current_year_avg,
    prev.avg_price as previous_year_avg,
    current.transactions as current_transactions,
    ROUND(
        (CAST(current.avg_price AS REAL) - CAST(prev.avg_price AS REAL)) / 
        CAST(prev.avg_price AS REAL) * 100, 2
    ) as yoy_growth_percent,
    current.avg_price - prev.avg_price as price_change_dollars
FROM yearly_medians current
LEFT JOIN yearly_medians prev 
    ON current.borough = prev.borough 
    AND current.sale_year = prev.sale_year + 1
WHERE prev.avg_price IS NOT NULL
    AND current.sale_year >= 2020
ORDER BY current.sale_year DESC, yoy_growth_percent DESC;

-- =============================================================================
-- 3. TOP PERFORMING NEIGHBORHOODS BY PRICE APPRECIATION
-- =============================================================================
-- Identify neighborhoods with highest price growth (requires neighborhood data)
SELECT 
    borough,
    neighborhood,
    COUNT(*) as total_transactions,
    MIN(strftime('%Y', sale_date)) as first_year,
    MAX(strftime('%Y', sale_date)) as last_year,
    CAST(AVG(CASE WHEN sale_year = 2019 THEN sale_price END) AS INTEGER) as avg_price_2019,
    CAST(AVG(CASE WHEN sale_year >= 2023 THEN sale_price END) AS INTEGER) as avg_price_recent,
    ROUND(
        (AVG(CASE WHEN sale_year >= 2023 THEN sale_price END) - 
         AVG(CASE WHEN sale_year = 2019 THEN sale_price END)) /
        AVG(CASE WHEN sale_year = 2019 THEN sale_price END) * 100, 2
    ) as price_appreciation_percent
FROM sales
WHERE neighborhood IS NOT NULL 
    AND borough IS NOT NULL
    AND sale_price > 0
    AND sale_year BETWEEN 2019 AND 2024
GROUP BY borough, neighborhood
HAVING COUNT(*) >= 20  -- Minimum transactions for reliability
    AND AVG(CASE WHEN sale_year = 2019 THEN sale_price END) IS NOT NULL
    AND AVG(CASE WHEN sale_year >= 2023 THEN sale_price END) IS NOT NULL
ORDER BY price_appreciation_percent DESC
LIMIT 20;

-- =============================================================================
-- 4. TRANSACTION VOLUME TRENDS
-- =============================================================================
-- Monthly transaction volumes to understand market activity
SELECT 
    strftime('%Y-%m', sale_date) as month,
    borough,
    COUNT(*) as transactions,
    SUM(sale_price) as total_volume_dollars,
    CAST(AVG(sale_price) AS INTEGER) as avg_transaction_size
FROM sales
WHERE sale_price > 0 
    AND sale_date >= date('2019-01-01')
    AND borough IS NOT NULL
GROUP BY strftime('%Y-%m', sale_date), borough
ORDER BY month, borough;

-- =============================================================================
-- 5. PRICE DISTRIBUTION BY BUILDING CLASS
-- =============================================================================
-- Analyze price patterns across different property types
SELECT 
    building_class_category,
    borough,
    COUNT(*) as transactions,
    CAST(AVG(sale_price) AS INTEGER) as avg_price,
    CAST(MIN(sale_price) AS INTEGER) as min_price,
    CAST(MAX(sale_price) AS INTEGER) as max_price,
    ROUND(AVG(CAST(price_per_sqft AS REAL)), 2) as avg_price_per_sqft
FROM sales
WHERE sale_price > 0 
    AND building_class_category IS NOT NULL
    AND borough IS NOT NULL
    AND sale_date >= date('2020-01-01')
GROUP BY building_class_category, borough
HAVING COUNT(*) >= 10
ORDER BY avg_price DESC;

-- =============================================================================
-- 6. SEASONAL PATTERNS
-- =============================================================================
-- Identify seasonal trends in NYC real estate market
SELECT 
    CASE sale_month
        WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
        WHEN 4 THEN 'April' WHEN 5 THEN 'May' WHEN 6 THEN 'June'
        WHEN 7 THEN 'July' WHEN 8 THEN 'August' WHEN 9 THEN 'September'
        WHEN 10 THEN 'October' WHEN 11 THEN 'November' WHEN 12 THEN 'December'
    END as month_name,
    sale_month,
    COUNT(*) as total_transactions,
    CAST(AVG(sale_price) AS INTEGER) as avg_price,
    borough
FROM sales
WHERE sale_price > 0 
    AND borough IS NOT NULL
    AND sale_date >= date('2020-01-01')
GROUP BY sale_month, borough
ORDER BY sale_month, borough;

-- =============================================================================
-- 7. PRICE RANGES DISTRIBUTION
-- =============================================================================
-- Understand market segments by price ranges
SELECT 
    borough,
    CASE 
        WHEN sale_price < 500000 THEN 'Under $500K'
        WHEN sale_price < 1000000 THEN '$500K - $1M'
        WHEN sale_price < 2000000 THEN '$1M - $2M'
        WHEN sale_price < 5000000 THEN '$2M - $5M'
        ELSE 'Over $5M'
    END as price_range,
    COUNT(*) as transactions,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY borough), 2) as percent_of_borough
FROM sales
WHERE sale_price > 0 
    AND borough IS NOT NULL
    AND sale_date >= date('2020-01-01')
GROUP BY borough, 
    CASE 
        WHEN sale_price < 500000 THEN 'Under $500K'
        WHEN sale_price < 1000000 THEN '$500K - $1M'
        WHEN sale_price < 2000000 THEN '$1M - $2M'
        WHEN sale_price < 5000000 THEN '$2M - $5M'
        ELSE 'Over $5M'
    END
ORDER BY borough, 
    CASE price_range
        WHEN 'Under $500K' THEN 1
        WHEN '$500K - $1M' THEN 2
        WHEN '$1M - $2M' THEN 3
        WHEN '$2M - $5M' THEN 4
        ELSE 5
    END;

-- =============================================================================
-- 8. MARKET SUMMARY STATISTICS
-- =============================================================================
-- Overall market health indicators for dashboard KPIs
SELECT 
    'Overall Market' as metric,
    COUNT(*) as total_transactions,
    CAST(AVG(sale_price) AS INTEGER) as avg_price,
    CAST(SUM(sale_price) AS INTEGER) as total_volume,
    COUNT(DISTINCT borough) as boroughs_active,
    MIN(sale_date) as earliest_transaction,
    MAX(sale_date) as latest_transaction
FROM sales
WHERE sale_price > 0 
    AND sale_date >= date('2019-01-01')

UNION ALL

SELECT 
    borough as metric,
    COUNT(*) as total_transactions,
    CAST(AVG(sale_price) AS INTEGER) as avg_price,
    CAST(SUM(sale_price) AS INTEGER) as total_volume,
    COUNT(DISTINCT neighborhood) as boroughs_active,
    MIN(sale_date) as earliest_transaction,
    MAX(sale_date) as latest_transaction
FROM sales
WHERE sale_price > 0 
    AND sale_date >= date('2019-01-01')
    AND borough IS NOT NULL
GROUP BY borough
ORDER BY total_volume DESC;

-- =============================================================================
-- 9. RECENT MARKET ACTIVITY (Last 12 Months)
-- =============================================================================
-- Focus on recent trends for current market insights
SELECT 
    borough,
    COUNT(*) as recent_transactions,
    CAST(AVG(sale_price) AS INTEGER) as recent_avg_price,
    strftime('%Y-%m', MAX(sale_date)) as latest_transaction_month,
    strftime('%Y-%m', MIN(sale_date)) as earliest_transaction_month
FROM sales
WHERE sale_price > 0 
    AND borough IS NOT NULL
    AND sale_date >= date('2023-01-01')  -- Adjust this date as needed
GROUP BY borough
ORDER BY recent_avg_price DESC;

-- =============================================================================
-- 10. QUERY FOR DASHBOARD FILTERS
-- =============================================================================
-- Get unique values for dashboard filter dropdowns
SELECT 'borough' as filter_type, borough as filter_value, COUNT(*) as count
FROM sales 
WHERE borough IS NOT NULL AND sale_date >= date('2019-01-01')
GROUP BY borough

UNION ALL

SELECT 'year' as filter_type, CAST(sale_year AS TEXT) as filter_value, COUNT(*) as count
FROM sales 
WHERE sale_year IS NOT NULL AND sale_date >= date('2019-01-01')
GROUP BY sale_year

UNION ALL

SELECT 'building_class' as filter_type, building_class_category as filter_value, COUNT(*) as count
FROM sales 
WHERE building_class_category IS NOT NULL AND sale_date >= date('2019-01-01')
GROUP BY building_class_category
HAVING COUNT(*) >= 50  -- Only include classes with significant volume

ORDER BY filter_type, count DESC;