-- Structure of the database:
--
--   |recipes           | <-1 to many- | input_slots   |
-- /-| machine          |              |  recipe       |
-- | | output_quanitity |              |  crafting_slot| <-------------------\
-- | | output_item      |--\                                                 |
-- |                       |                                                 |
-- \-many to 1-\           |                |crafting_component|--many to 1--/
--             |           |            /---| item             |
--             v           |            |   | quantity         |
--   | machine      |      v            v
--   |  human_name  |    | items         |
--   |  minecraft_id|    |  ty           |
--                       |  human_name   |
--                       |  minecraft_id |
-- That is, in English:
-- We care about recipes. We want to be able to compute the following from them:
--   - What machine can perform the recipe
--   - What it outputs, and how much
--   - What it takes as input.
-- The last item on that list turns out to be a complex problem, as for many recipes
-- the answer to "what does this take as input for this slot" is "many things".
-- We solve this by classifying items into "crafting slots". Each slot has a list of
-- items that it accepts, maintained by performing a many-to-one mapping of
-- "crafting cpomonent" to "crafting_slot"

CREATE TABLE machines (
  id SERIAL PRIMARY KEY,
  human_name TEXT NOT NULL,
  minecraft_id TEXT NOT NULL
);

CREATE TYPE item_type AS ENUM ('item', 'fluid');

CREATE TABLE items (
  id SERIAL PRIMARY KEY,
  ty item_type NOT NULL,
  human_name TEXT NOT NULL,
  minecraft_id TEXT NOT NULL
);

CREATE TABLE recipes (
  id SERIAL PRIMARY KEY,
  machine INTEGER REFERENCES machines(id) NOT NULL,
  output_quantity INTEGER NOT NULL,
  output_item INTEGER REFERENCES items(id) NOT NULL
);

-- A very frequent query is "given this item, what recipes can make it?"
CREATE INDEX recipe_outputs ON recipes USING hash (output_item);

CREATE TABLE input_slots (
  id SERIAL PRIMARY KEY,
  for_recipe INTEGER REFERENCES recipes(id) NOT NULL
  -- This is where we might add information about the slot itself, like its X/Y
  -- position in the interface.
);

-- We will be joining "input_slots" to "recipes" a lot
CREATE INDEX input_slot_recipe ON input_slots USING hash (for_recipe);

-- Each crafting component is an individual item that could be in a given slot.
-- For example, to get all the items that can be used in a recipe, along with
-- what slot those items corespond too, use the following query
--SELECT
--  recipes.id AS recipe_id,
--  input_slots.id AS input_slot,
--  crafting_components.item AS crafting_item,
--  crafting_components.quantity AS crafting_quantity
--FROM recipes
--  INNER JOIN input_slots ON input_slots.for_recipe = recipes.id
--  INNER JOIN crafting_components ON crafting_components.crafting_slot = input_slots.id;

CREATE TABLE crafting_components (
  id SERIAL PRIMARY KEY,
  crafting_slot INTEGER REFERENCES input_slots(id) NOT NULL,
  item INTEGER REFERENCES items(id) NOT NULL,
  quantity INTEGER NOT NULL
);

-- We will be joining crafting_components to the slot they index a lot
CREATE INDEX crafting_component_slot ON crafting_components USING hash (crafting_slot);
-- And we want to support queries like "what recipe uses this item"
CREATE INDEX crafting_component_item ON crafting_components USING hash (item);
