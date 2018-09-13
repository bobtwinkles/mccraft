-- This file should undo anything in `up.sql`
ALTER TABLE items DROP CONSTRAINT item_mcid_unique;
DROP INDEX item_mcid;
