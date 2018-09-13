-- Your SQL goes here
ALTER TABLE mccraft.outputs ALTER COLUMN recipe SET NOT NULL;
ALTER TABLE mccraft.outputs ALTER COLUMN quantity SET NOT NULL;
ALTER TABLE mccraft.outputs ALTER COLUMN item SET NOT NULL;
