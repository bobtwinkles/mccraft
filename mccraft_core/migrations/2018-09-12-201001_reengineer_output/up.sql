-- Structure of the database after this migration:
--
--   |recipes  | <----------1 to many- | input_slots   |
-- /-| machine | <-1 to many-\         |  recipe       |
-- |                         |         |  crafting_slot| <-------------------\
-- |                | output_slots |                                         |
-- |                |  recipe      |                                         |
-- \-many to 1-\    |  quantity    |        |crafting_component|--many to 1--/
--             |    |  item        |    /---| item             |
--             v           |            |   | quantity         |
--   | machine      |      v            v
--   |  human_name  |    | items         |
--   |  minecraft_id|    |  ty           |
--                       |  human_name   |
--                       |  minecraft_id |

-- Drop the explicit recipe outputs
DROP INDEX recipe_outputs;

ALTER TABLE recipes DROP COLUMN output_quantity;
ALTER TABLE recipes DROP COLUMN output_item;

-- Create the outputs table
CREATE TABLE outputs (
  id SERIAL PRIMARY KEY,
  recipe INTEGER REFERENCES recipes(id),
  quantity INTEGER,
  item INTEGER REFERENCES items(id)
);

-- We want to be able to search on the outputs
CREATE INDEX output_item ON outputs USING hash (item);
