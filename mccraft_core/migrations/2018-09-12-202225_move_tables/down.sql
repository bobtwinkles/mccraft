-- This file should undo anything in `up.sql`
ALTER TABLE crafting_components SET SCHEMA public;
ALTER TABLE input_slots SET SCHEMA public;
ALTER TABLE items SET SCHEMA public;
ALTER TABLE machines SET SCHEMA public;
ALTER TABLE outputs SET SCHEMA public;
ALTER TABLE recipes SET SCHEMA public;
