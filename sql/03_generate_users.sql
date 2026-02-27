---------------------------------------------------
---------------------------------------------------
-- GENERATE USERS (dbo.users 5,000 rows)
---------------------------------------------------
---------------------------------------------------
-- Clear existing users safely
-- (DELETE is safe with FKs; if you already inserted sessions/events later, you'd delete those first)
DELETE FROM dbo.users;

DECLARE @UserCount INT = 5000;

;WITH
tally AS (
    SELECT TOP (@UserCount)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.users (user_id, signup_datetime, age_group, region, current_plan, is_active)
SELECT
    t.n AS user_id,

    -- signup_datetime: within last 180 days (gives cohort variety)
    DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 180), CAST(GETDATE() AS DATETIME2(0))) AS signup_datetime,

    -- age_group: Gen Z heavy
    CASE
        WHEN x.age_bucket <= 40 THEN '18-24'
        WHEN x.age_bucket <= 70 THEN '25-34'
        WHEN x.age_bucket <= 85 THEN '35-44'
        WHEN x.age_bucket <= 95 THEN '45-54'
        ELSE                     '55+'
    END AS age_group,

    -- region: US-heavy with some international
    CASE
        WHEN x.region_bucket <= 28 THEN 'Midwest'
        WHEN x.region_bucket <= 52 THEN 'South'
        WHEN x.region_bucket <= 70 THEN 'Northeast'
        WHEN x.region_bucket <= 86 THEN 'West'
        ELSE                         'International'
    END AS region,

    -- current_plan: 80% Free / 20% Premium
    CASE
        WHEN x.plan_bucket <= 80 THEN 'Free'
        ELSE                      'Premium'
    END AS current_plan,

    -- is_active: 92% active, 8% inactive 
    CASE
        WHEN x.active_bucket <= 92 THEN 1
        ELSE                         0
    END AS is_active
FROM tally t
CROSS APPLY (
    SELECT
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS age_bucket,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS region_bucket,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS plan_bucket,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS active_bucket
) x;

-- Validation checks
SELECT COUNT(*) AS user_count FROM dbo.users;

SELECT age_group, COUNT(*) AS users
FROM dbo.users
GROUP BY age_group
ORDER BY users DESC;

SELECT region, COUNT(*) AS users
FROM dbo.users
GROUP BY region
ORDER BY users DESC;

SELECT current_plan, COUNT(*) AS users
FROM dbo.users
GROUP BY current_plan
ORDER BY users DESC;

SELECT TOP 10 *
FROM dbo.users
ORDER BY user_id;
