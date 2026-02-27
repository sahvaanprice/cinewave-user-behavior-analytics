------------------------------------------------------------
-- Build upgrade candidates into a temp table
------------------------------------------------------------
SELECT DISTINCT
    e.user_id,
    e.session_id,
    e.event_time AS anchor_time
INTO #upgrades
FROM dbo.events e
JOIN dbo.users u
    ON e.user_id = u.user_id
WHERE e.event_type = 'play_complete'
  AND u.current_plan = 'Free'
  AND (ABS(CHECKSUM(NEWID())) % 100) + 1 <= 5;  -- ~5% conversion

-- Quick check
SELECT COUNT(*) AS upgrade_candidates
FROM #upgrades;

------------------------------------------------------------
-- Insert subscription_upgrade events
------------------------------------------------------------
INSERT INTO dbo.events (
    event_id,
    user_id,
    session_id,
    event_time,
    event_type
)
SELECT
    @CurrentMaxEventID +
    ROW_NUMBER() OVER (ORDER BY user_id),

    user_id,
    session_id,

    DATEADD(SECOND,
        300 + (ABS(CHECKSUM(NEWID())) % 600),
        anchor_time
    ),

    'subscription_upgrade'
FROM #upgrades;

