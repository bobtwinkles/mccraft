-- Your SQL goes here
CREATE INDEX item_mcid ON items USING hash (minecraft_id);
ALTER TABLE items ADD CONSTRAINT item_mcid_unique UNIQUE (minecraft_id);
