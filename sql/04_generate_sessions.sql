---------------------------------------------------
---------------------------------------------------
-- GENERATE SESSIONS (dbo.sessions 40,000 rows)
---------------------------------------------------
---------------------------------------------------
DELETE FROM dbo.sessions;

DECLARE @SessionCount INT = 40000;

;WITH tally AS (
    SELECT TOP (@SessionCount)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.sessions (
    session_id,
    user_id,
    session_start,
    session_end,
    device_type,
    session_duration_seconds
)
SELECT
    t.n AS session_id,

    -- Random user assignment
    (ABS(CHECKSUM(NEWID())) % 5000) + 1 AS user_id,

    s.session_start,

    DATEADD(SECOND, d.duration_seconds, s.session_start) AS session_end,

    -- Device distribution
    CASE
        WHEN d.device_bucket <= 55 THEN 'Mobile'
        WHEN d.device_bucket <= 80 THEN 'Web'
        ELSE                          'TV'
    END AS device_type,

    d.duration_seconds
FROM tally t
CROSS APPLY (
    -- Random start time within last 90 days
    SELECT DATEADD(
        MINUTE,
        -1 * (ABS(CHECKSUM(NEWID())) % (90 * 24 * 60)),
        GETDATE()
    ) AS session_start
) s
CROSS APPLY (
    SELECT
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS device_bucket,

        -- Session duration
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 40
                THEN 60 + (ABS(CHECKSUM(NEWID())) % 240)       -- 1–5 min
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 80
                THEN 300 + (ABS(CHECKSUM(NEWID())) % 1500)     -- 5–30 min
            ELSE
                1500 + (ABS(CHECKSUM(NEWID())) % 5400)         -- 25–120 min
        END AS duration_seconds
) d;

-- Validation
SELECT COUNT(*) AS session_count FROM dbo.sessions;

SELECT device_type, COUNT(*) AS sessions
FROM dbo.sessions
GROUP BY device_type
ORDER BY sessions DESC;

SELECT TOP 10 *
FROM dbo.sessions
ORDER BY session_id;
