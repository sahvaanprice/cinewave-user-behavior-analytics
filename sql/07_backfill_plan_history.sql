------------------------------------------------------------
-- Insert plan_history records
------------------------------------------------------------
INSERT INTO dbo.plan_history (
    plan_change_id,
    user_id,
    change_time,
    from_plan,
    to_plan,
    change_reason
)
SELECT
    @CurrentPlanChangeID +
    ROW_NUMBER() OVER (ORDER BY user_id),

    user_id,
    GETDATE(),
    'Free',
    'Premium',
    'Engagement Upgrade'
FROM #upgrades;
