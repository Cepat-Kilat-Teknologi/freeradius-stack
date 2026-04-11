-- =============================================================================
-- post-schema.sql
-- Run AFTER the default FreeRADIUS schema import (schema.sql).
-- Idempotent: safe to run multiple times. Use `mysql --force` so duplicate
-- index errors are silently skipped. No DROP statements -- only additive.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Convert MyISAM tables to InnoDB
--
-- The default FreeRADIUS schema creates these 5 tables as MyISAM.
-- InnoDB provides:
--   - Transaction support (ACID compliance)
--   - Row-level locking instead of table-level (better concurrency)
--   - Crash recovery via redo log
--   - Foreign key support
--
-- Note: radacct, radpostauth, and nas are already InnoDB in the default schema.
-- ALTER TABLE ... ENGINE=InnoDB is a no-op if the table is already InnoDB.
-- ---------------------------------------------------------------------------

ALTER TABLE radcheck ENGINE=InnoDB;
ALTER TABLE radreply ENGINE=InnoDB;
ALTER TABLE radusergroup ENGINE=InnoDB;
ALTER TABLE radgroupcheck ENGINE=InnoDB;
ALTER TABLE radgroupreply ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 2. Add composite and covering indexes for freeradius-api query patterns
--
-- These indexes do NOT exist in the default FreeRADIUS schema.
-- They target the most common query patterns used by the REST API:
--   - User group lookups (radusergroup)
--   - Group attribute lookups (radgroupcheck, radgroupreply)
--   - Active session queries (radacct)
--   - Authentication log queries (radpostauth)
--
-- Composite indexes speed up multi-column lookups used by the REST API.
-- If an index already exists, mysql --force will skip the error and continue.
-- ---------------------------------------------------------------------------

-- Composite index for user-group lookups; speeds up GROUP BY username queries
CREATE INDEX idx_radusergroup_user_group ON radusergroup(username, groupname);

-- Composite index for group-attribute lookups; speeds up authorization lookups
CREATE INDEX idx_radgroupcheck_group_attr ON radgroupcheck(groupname, attribute);

-- Composite index for group-reply lookups; speeds up reply attribute lookups
CREATE INDEX idx_radgroupreply_group_attr ON radgroupreply(groupname, attribute);

-- Speeds up "find active sessions for user" queries (WHERE acctstoptime IS NULL)
CREATE INDEX idx_radacct_active ON radacct(username, acctstoptime);

-- Speeds up authentication log queries ordered/filtered by date
CREATE INDEX idx_radpostauth_authdate ON radpostauth(authdate);
