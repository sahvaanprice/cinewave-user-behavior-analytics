---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 1.0 (1 per session)
---------------------------------------------------
---------------------------------------------------
DELETE FROM dbo.events;

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type
)
SELECT
    ROW_NUMBER() OVER (ORDER BY s.session_id) AS event_id,
    s.user_id,
    s.session_id,
    s.session_start,
    'app_open'
FROM dbo.sessions s;

SELECT COUNT(*) AS app_open_events
FROM dbo.events;


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 2.0 (dbo.events browse + search)
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH session_actions AS (
    SELECT
        s.session_id,
        s.user_id,
        s.session_start,

        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS behavior_roll
    FROM dbo.sessions s
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    search_query
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,

    DATEADD(SECOND,
        ABS(CHECKSUM(NEWID())) % 60,
        session_start
    ),

    CASE
        WHEN behavior_roll <= 65 THEN 'browse'
        WHEN behavior_roll <= 85 THEN 'search'
    END,

    CASE
        WHEN behavior_roll > 65 AND behavior_roll <= 85
            THEN CONCAT('Search ', ABS(CHECKSUM(NEWID())) % 20)
        ELSE NULL
    END
FROM session_actions
WHERE behavior_roll <= 85;   -- 85% engage


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 3.0 (content_view events)
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH engaged_sessions AS (
    SELECT DISTINCT
        e.session_id,
        e.user_id,
        MIN(e.event_time) AS first_action_time
    FROM dbo.events e
    WHERE e.event_type IN ('browse', 'search')
    GROUP BY e.session_id, e.user_id
),
content_clicks AS (
    SELECT
        es.session_id,
        es.user_id,
        DATEADD(SECOND,
            ABS(CHECKSUM(NEWID())) % 120,
            es.first_action_time
        ) AS event_time,
        (ABS(CHECKSUM(NEWID())) % 300) + 1 AS content_id,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS click_roll
    FROM engaged_sessions es
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    content_id
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,
    event_time,
    'content_view',
    content_id
FROM content_clicks
WHERE click_roll <= 65;   -- 65% click into content


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 4.0 (play_start events)
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH content_sessions AS (
    SELECT
        e.session_id,
        e.user_id,
        e.content_id,
        e.event_time
    FROM dbo.events e
    WHERE e.event_type = 'content_view'
),
play_candidates AS (
    SELECT
        cs.*,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS play_roll
    FROM content_sessions cs
),
watch_generation AS (
    SELECT
        pc.session_id,
        pc.user_id,
        pc.content_id,

        DATEADD(SECOND,
            ABS(CHECKSUM(NEWID())) % 180,
            pc.event_time
        ) AS event_time,

        c.duration_minutes,

        -- watch time realism
        CASE
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 50
                THEN 300 + (ABS(CHECKSUM(NEWID())) % 900)     -- short watch
            WHEN ABS(CHECKSUM(NEWID())) % 100 < 85
                THEN 900 + (ABS(CHECKSUM(NEWID())) % 1800)    -- medium watch
            ELSE 1800 + (ABS(CHECKSUM(NEWID())) % 3600)   -- long watch
        END AS watch_time_seconds,

        play_roll
    FROM play_candidates pc
    JOIN dbo.content c
        ON pc.content_id = c.content_id
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    content_id,
    watch_time_seconds,
    percent_watched
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,
    event_time,
    'play_start',
    content_id,
    watch_time_seconds,

    CAST(
        (watch_time_seconds /
        (duration_minutes * 60.0)) * 100
    AS DECIMAL(5,2))

FROM watch_generation
WHERE play_roll <= 70;   -- 70% start playback


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 5.0 (play_complete events)
-- (>= 80% watched)
-- Premium + TV complete more often
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH starts AS (
    SELECT
        e.session_id,
        e.user_id,
        e.content_id,
        e.event_time AS play_start_time,
        e.watch_time_seconds AS start_watch_seconds,
        e.percent_watched AS start_percent
    FROM dbo.events e
    WHERE e.event_type = 'play_start'
),
starts_with_context AS (
    SELECT
        s.*,
        u.current_plan,
        sess.device_type,
        c.duration_minutes,

        -- Base probability roll
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS roll
    FROM starts s
    JOIN dbo.users u
        ON s.user_id = u.user_id
    JOIN dbo.sessions sess
        ON s.session_id = sess.session_id
    JOIN dbo.content c
        ON s.content_id = c.content_id
),
completion_decision AS (
    SELECT
        swc.*,

        -- completion_threshold sets how easy it is to complete
        -- Lower threshold number = more likely to complete
        CASE
            WHEN swc.current_plan = 'Premium' AND swc.device_type = 'TV' THEN 55
            WHEN swc.current_plan = 'Premium' THEN 60
            WHEN swc.device_type = 'TV' THEN 65
            WHEN swc.device_type = 'Mobile' THEN 75
            ELSE 70
        END AS threshold
    FROM starts_with_context swc
),
complete_rows AS (
    SELECT
        cd.session_id,
        cd.user_id,
        cd.content_id,

        -- completion happens later in the session than play_start
        DATEADD(SECOND,
            600 + (ABS(CHECKSUM(NEWID())) % 3600),
            cd.play_start_time
        ) AS event_time,

        cd.duration_minutes,

        -- force percent_watched into 80–100 range if completed
        CAST(80 + (ABS(CHECKSUM(NEWID())) % 21) AS DECIMAL(5,2)) AS percent_watched
    FROM completion_decision cd
    WHERE cd.roll <= cd.threshold
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    content_id,
    watch_time_seconds,
    percent_watched
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,
    event_time,
    'play_complete',
    content_id,

    -- watch_time_seconds derived from percent watched and duration
    CAST((percent_watched / 100.0) * (duration_minutes * 60) AS INT) AS watch_time_seconds,
    percent_watched
FROM complete_rows;


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 6.0 (ad_start events)
-- Free users only
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH play_sessions AS (
    SELECT
        e.session_id,
        e.user_id,
        e.content_id,
        e.event_time
    FROM dbo.events e
    JOIN dbo.users u
        ON e.user_id = u.user_id
    WHERE e.event_type = 'play_start'
      AND u.current_plan = 'Free'
),
ad_candidates AS (
    SELECT *,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS ad_roll
    FROM play_sessions
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    content_id
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,

    DATEADD(SECOND,
        120 + (ABS(CHECKSUM(NEWID())) % 300),
        event_time
    ),

    'ad_start',
    content_id
FROM ad_candidates
WHERE ad_roll <= 60;


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 7.0 (add_watchlist events)
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;

;WITH view_events AS (
    SELECT
        e.session_id,
        e.user_id,
        e.content_id,
        e.event_time
    FROM dbo.events e
    WHERE e.event_type = 'content_view'
),
watchlist_candidates AS (
    SELECT *,
        (ABS(CHECKSUM(NEWID())) % 100) + 1 AS watchlist_roll
    FROM view_events
)

INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type,
    content_id
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY session_id),

    user_id,
    session_id,

    DATEADD(SECOND,
        60 + (ABS(CHECKSUM(NEWID())) % 240),
        event_time
    ),

    'add_watchlist',
    content_id
FROM watchlist_candidates
WHERE watchlist_roll <= 25;

SELECT event_type, COUNT(*)
FROM dbo.events
GROUP BY event_type
ORDER BY COUNT(*) DESC;


---------------------------------------------------
---------------------------------------------------
-- GENERATE EVENTS 8.0
-- Subscription Upgardes + Plan History
---------------------------------------------------
---------------------------------------------------
DECLARE @CurrentMaxEventID BIGINT;
DECLARE @CurrentPlanChangeID BIGINT;

SELECT @CurrentMaxEventID = ISNULL(MAX(event_id),0) FROM dbo.events;
SELECT @CurrentPlanChangeID = ISNULL(MAX(plan_change_id),0) FROM dbo.plan_history;

-- Clean temp table if it exists
IF OBJECT_ID('tempdb..#upgrades') IS NOT NULL DROP TABLE #upgrades;
