---------------------------------------------------
---------------------------------------------------
-- GENERATE CINEWAVE MOVIES (dbo.content 300 rows)
---------------------------------------------------
---------------------------------------------------

-- Clear existing rows safely (TRUNCATE not allowed because dbo.events references dbo.content)
DELETE FROM dbo.content;

DECLARE @MovieCount INT = 300;

;WITH
tally AS (
    SELECT TOP (@MovieCount)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
),

genre_pool AS (
    SELECT * FROM (VALUES
        ('Drama',        18),
        ('Comedy',       16),
        ('Action',       14),
        ('Thriller',     12),
        ('Sci-Fi',       10),
        ('Romance',       9),
        ('Horror',        7),
        ('Documentary',   6),
        ('Animation',     5),
        ('Crime',         3)
    ) g(genre, weight)
),
genre_weighted AS (
    SELECT
        genre,
        weight,
        SUM(weight) OVER () AS total_weight,
        SUM(weight) OVER (ORDER BY genre ROWS UNBOUNDED PRECEDING) AS running_weight
    FROM genre_pool
),

year_bands AS (
    SELECT * FROM (VALUES
        (2024, 2026, 28),
        (2020, 2023, 34),
        (2010, 2019, 26),
        (2000, 2009, 12)
    ) y(y_start, y_end, weight)
),
year_weighted AS (
    SELECT
        y_start,
        y_end,
        weight,
        SUM(weight) OVER () AS total_weight,
        SUM(weight) OVER (ORDER BY y_start ROWS UNBOUNDED PRECEDING) AS running_weight
    FROM year_bands
)

INSERT INTO dbo.content (content_id, title, genre, release_year, duration_minutes)
SELECT
    t.n AS content_id,
    CONCAT('CineWave Movie ', RIGHT(CONCAT('000', t.n), 3)) AS title,

    (SELECT TOP 1 gw.genre
     FROM genre_weighted gw
     WHERE gw.running_weight >= (ABS(CHECKSUM(NEWID())) % gw.total_weight) + 1
     ORDER BY gw.running_weight) AS genre,

    (SELECT TOP 1
         (yw.y_start + (ABS(CHECKSUM(NEWID())) % (yw.y_end - yw.y_start + 1)))
     FROM year_weighted yw
     WHERE yw.running_weight >= (ABS(CHECKSUM(NEWID())) % yw.total_weight) + 1
     ORDER BY yw.running_weight) AS release_year,

    CASE
        WHEN r.bucket <= 70 THEN  85 + (r.r2 % 46)   -- 70%: 85–130
        WHEN r.bucket <= 90 THEN  70 + (r.r2 % 16)   -- 20%: 70–85
        ELSE                 130 + (r.r2 % 51)       -- 10%: 130–180
    END AS duration_minutes
FROM tally t
CROSS APPLY (
    SELECT
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS bucket,
        ABS(CHECKSUM(NEWID()))             AS r2
) r;

-- Validation
SELECT
    COUNT(*) AS movie_count,
    MIN(duration_minutes) AS min_duration,
    MAX(duration_minutes) AS max_duration,
    MIN(release_year) AS min_year,
    MAX(release_year) AS max_year
FROM dbo.content;

SELECT TOP 10 *
FROM dbo.content
ORDER BY content_id;

