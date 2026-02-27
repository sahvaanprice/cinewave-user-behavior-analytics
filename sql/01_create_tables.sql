-- Drop in dependency order
IF OBJECT_ID('dbo.events','U') IS NOT NULL DROP TABLE dbo.events;
IF OBJECT_ID('dbo.sessions','U') IS NOT NULL DROP TABLE dbo.sessions;
IF OBJECT_ID('dbo.plan_history','U') IS NOT NULL DROP TABLE dbo.plan_history;
IF OBJECT_ID('dbo.content','U') IS NOT NULL DROP TABLE dbo.content;
IF OBJECT_ID('dbo.users','U') IS NOT NULL DROP TABLE dbo.users;

-------------------------------------------
-- USERS Table
-------------------------------------------
CREATE TABLE dbo.users(
user_id INT NOT NULL PRIMARY KEY,
signup_datetime DATETIME2(0) NOT NULL,
age_group VARCHAR(20) NOT NULL,
region VARCHAR(50) NOT NULL,
current_plan VARCHAR(10) NOT NULL, --'Free' or 'Premium'
is_active BIT NOT NULL DEFAULT (1)
);

-------------------------------------------
-- CONTENT (Movies)
-------------------------------------------
CREATE TABLE dbo.content (
content_id INT NOT NULL PRIMARY KEY,
title VARCHAR(200) NOT NULL,
genre VARCHAR(50) NOT NULL,
release_year INT NOT NULL,
duration_minutes INT NOT NULL,
);

-------------------------------------------
-- SESSIONS
-------------------------------------------
CREATE TABLE dbo.sessions (
session_id BIGINT NOT NULL PRIMARY KEY,
user_id INT NOT NULL,
session_start DATETIME2(0) NOT NULL,
session_end DATETIME2(0) NOT NULL,
device_type VARCHAR(10) NOT NULL, -- 'Mobile', 'Web', 'TV'
session_duration_seconds INT NOT NULL,

CONSTRAINT FK_session_user_start
	FOREIGN KEY (user_id) REFERENCES dbo.users(user_id)
);

CREATE INDEX IX_sessions_user_start
ON dbo.sessions(user_id, session_start);

-------------------------------------------
-- PLAN HISTORY
-------------------------------------------
CREATE TABLE dbo.plan_history (
plan_change_id BIGINT NOT NULL PRIMARY KEY,
user_id INT NOT NULL,
change_time DATETIME2(0) NOT NULL,
from_plan VARCHAR(10) NOT NULL,
to_plan VARCHAR(10) NOT NULL,
change_reason VARCHAR(50) NULL,

CONSTRAINT FK_plan_history_user
	FOREIGN KEY (user_id) REFERENCES dbo.users(user_id)
);

CREATE INDEX IX_plan_history_user_time
ON dbo.plan_history (user_id, change_time);

-------------------------------------------
-- EVENTS
-------------------------------------------
CREATE TABLE dbo.events (
event_id BIGINT NOT NULL PRIMARY KEY,
user_id INT NOT NULL,
session_id BIGINT NOT NULL,
event_time DATETIME2(0) NOT NULL,
event_type VARCHAR(30) NOT NULL,

content_id INT NULL,
watch_time_seconds INT NULL,
percent_watched DECIMAL(5,2) NULL,
search_query VARCHAR(200) NULL,

CONSTRAINT FK_events_users
	FOREIGN KEY (user_id) REFERENCES dbo.users(user_id),

CONSTRAINT FK_events_session
	FOREIGN KEY (session_id) REFERENCES dbo.sessions(session_id),

CONSTRAINT FK_events_content
	FOREIGN KEY (content_id) REFERENCES dbo.content(content_id)
);

CREATE INDEX IX_events_user_time
ON dbo.events (user_id, event_time);

CREATE INDEX IX_events_session_time
ON dbo.events (session_id, event_time);

CREATE INDEX IX_events_type_time
ON dbo.events (event_type, event_time);
