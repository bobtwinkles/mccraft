-- This file should undo anything in `up.sql`
ALTER TABLE mccraft.machines DROP CONSTRAINT machine_mcid_unique;
DROP INDEX machine_mcids;
