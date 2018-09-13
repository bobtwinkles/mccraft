-- This file should undo anything in `up.sql`
DROP INDEX output_item;
DROP TABLE outputs;

-- Recreate the old columns and indexes
ALTER TABLE recipes ADD COLUMN output_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE recipes ADD COLUMN output_item INTEGER REFERENCES items(id) NOT NULL DEFAULT 0;
CREATE INDEX recipe_outputs ON recipes USING hash (output_item);
