-- This file should undo anything in `up.sql`
ALTER TABLE mccraft.outputs ALTER COLUMN recipe DROP NOT NULL;
ALTER TABLE mccraft.outputs ALTER COLUMN quantity DROP NOT NULL;
ALTER TABLE mccraft.outputs ALTER COLUMN item DROP NOT NULL;
