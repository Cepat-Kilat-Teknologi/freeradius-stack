-- =============================================================================
-- seed.sql — Synthetic RADIUS dev data
--
-- ALL data in this file is fictional. No real IP addresses, credentials,
-- subscriber names, or production values. Safe to commit.
--
-- Loaded by MariaDB initdb.d on first container start (after schema.sql
-- and post-schema.sql). Idempotent: uses INSERT IGNORE so re-runs skip
-- existing rows.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. NAS devices (routers that send RADIUS requests)
--
-- Three fake NAS entries representing a dev environment with:
--   - A MikroTik router (PPPoE concentrator)
--   - A Cisco router (hotspot)
--   - A localhost entry (for radtest from the FreeRADIUS container)
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO nas (nasname, shortname, type, ports, secret, server, community, description) VALUES
  ('10.99.0.1',  'mikrotik-dev-01', 'other',  0, 'testing123', NULL, NULL, 'Dev MikroTik PPPoE concentrator'),
  ('10.99.0.2',  'cisco-dev-01',    'cisco',  0, 'testing123', NULL, NULL, 'Dev Cisco hotspot gateway'),
  ('127.0.0.1',  'localhost',       'other',  0, 'testing123', NULL, NULL, 'Loopback for radtest');

-- ---------------------------------------------------------------------------
-- 2. Speed plan groups
--
-- Three tiers with RADIUS attributes for bandwidth control:
--   - plan-10m:  10 Mbps down / 5 Mbps up
--   - plan-25m:  25 Mbps down / 10 Mbps up
--   - plan-50m:  50 Mbps down / 25 Mbps up
--
-- MikroTik reads Mikrotik-Rate-Limit for PPPoE bandwidth shaping.
-- The format is: rx-rate/tx-rate (from the NAS perspective, so
-- rx = subscriber upload, tx = subscriber download).
-- ---------------------------------------------------------------------------

-- Auth type for all groups: PAP (Cleartext-Password check)
INSERT IGNORE INTO radgroupcheck (groupname, attribute, op, value) VALUES
  ('plan-10m', 'Auth-Type', ':=', 'PAP'),
  ('plan-25m', 'Auth-Type', ':=', 'PAP'),
  ('plan-50m', 'Auth-Type', ':=', 'PAP');

-- Bandwidth reply attributes per group
INSERT IGNORE INTO radgroupreply (groupname, attribute, op, value) VALUES
  ('plan-10m', 'Mikrotik-Rate-Limit', '=', '5M/10M'),
  ('plan-10m', 'Framed-Pool',         '=', 'pool-10m'),
  ('plan-25m', 'Mikrotik-Rate-Limit', '=', '10M/25M'),
  ('plan-25m', 'Framed-Pool',         '=', 'pool-25m'),
  ('plan-50m', 'Mikrotik-Rate-Limit', '=', '25M/50M'),
  ('plan-50m', 'Framed-Pool',         '=', 'pool-50m');

-- ---------------------------------------------------------------------------
-- 3. Subscriber accounts
--
-- Six fake PPPoE subscribers across the three speed plans.
-- Usernames follow the pattern: devuserN@example.test
-- Passwords are plaintext (Cleartext-Password) for dev convenience.
-- ---------------------------------------------------------------------------

INSERT IGNORE INTO radcheck (username, attribute, op, value) VALUES
  ('devuser1@example.test', 'Cleartext-Password', ':=', 'devpass001'),
  ('devuser2@example.test', 'Cleartext-Password', ':=', 'devpass002'),
  ('devuser3@example.test', 'Cleartext-Password', ':=', 'devpass003'),
  ('devuser4@example.test', 'Cleartext-Password', ':=', 'devpass004'),
  ('devuser5@example.test', 'Cleartext-Password', ':=', 'devpass005'),
  ('devuser6@example.test', 'Cleartext-Password', ':=', 'devpass006');

-- Per-user reply attributes (service type)
INSERT IGNORE INTO radreply (username, attribute, op, value) VALUES
  ('devuser1@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser1@example.test', 'Framed-Protocol', '=', 'PPP'),
  ('devuser2@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser2@example.test', 'Framed-Protocol', '=', 'PPP'),
  ('devuser3@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser3@example.test', 'Framed-Protocol', '=', 'PPP'),
  ('devuser4@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser4@example.test', 'Framed-Protocol', '=', 'PPP'),
  ('devuser5@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser5@example.test', 'Framed-Protocol', '=', 'PPP'),
  ('devuser6@example.test', 'Service-Type',    '=', 'Framed-User'),
  ('devuser6@example.test', 'Framed-Protocol', '=', 'PPP');

-- Assign subscribers to speed plan groups
INSERT IGNORE INTO radusergroup (username, groupname, priority) VALUES
  ('devuser1@example.test', 'plan-10m', 1),
  ('devuser2@example.test', 'plan-10m', 1),
  ('devuser3@example.test', 'plan-25m', 1),
  ('devuser4@example.test', 'plan-25m', 1),
  ('devuser5@example.test', 'plan-50m', 1),
  ('devuser6@example.test', 'plan-50m', 1);
