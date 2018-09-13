-- Your SQL goes here
CREATE INDEX machine_mcids ON mccraft.machines USING hash (minecraft_id);
ALTER TABLE mccraft.machines ADD CONSTRAINT machine_mcid_unique UNIQUE (minecraft_id);
