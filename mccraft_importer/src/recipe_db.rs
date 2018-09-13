use diesel;
use diesel::pg::PgConnection;
use diesel::prelude::*;
use diesel::result::{DatabaseErrorKind, Error::DatabaseError, QueryResult};
use fxhash::{FxHashMap, FxHashSet};
use mccraft_core::schema::mccraft as schema;
use mccraft_core::sql::{self, Item, ItemType};
use string_interner::Sym;
use types::{Recipe, StringInterner};

/// Database of all recipes
pub struct RecipeDatabase {
    recipes: Vec<Recipe>,
    /// Interner for all the strings
    interner: StringInterner,
    /// Map from the MinecraftID for an item to its type
    types_map: FxHashMap<Sym, ItemType>,
    /// Map from the MinecraftID for an item to its human-readable name
    names_map: FxHashMap<Sym, String>,
    /// Map from Minecraft ID (BG texture) for a machine to its human-readable name
    machines: FxHashMap<Sym, String>,
}

impl RecipeDatabase {
    pub fn new() -> Self {
        RecipeDatabase {
            recipes: Vec::new(),
            interner: StringInterner::with_hasher(Default::default()),
            types_map: Default::default(),
            names_map: Default::default(),
            machines: Default::default(),
        }
    }

    pub fn add_machine(&mut self, machine: Sym, name: String) {
        self.machines.entry(machine).or_insert(name);
    }

    pub fn add_recipe(&mut self, recipe: Recipe) {
        assert!(self.machines.contains_key(&recipe.machine));
        self.recipes.push(recipe);
    }

    pub fn get_or_intern(&mut self, t: impl AsRef<str>) -> Sym {
        self.interner.get_or_intern(t.as_ref())
    }

    pub fn associate_name(&mut self, item_id: Sym, human_name: String) {
        self.names_map.entry(item_id).or_insert(human_name);
    }

    pub fn associate_type(&mut self, item_id: Sym, ty: ItemType) {
        self.types_map.entry(item_id).or_insert(ty);
    }

    pub fn num_recipes(&self) -> usize {
        return self.recipes.len();
    }

    pub fn insert_items(&self, conn: &PgConnection) {
        use self::schema::items;

        let mut total_inserted = 0;
        let mut new_items = Vec::new();
        info!("Begin item list build");
        for (item, ty) in self.types_map.iter() {
            let minecraft_id = self
                .interner
                .resolve(*item)
                .expect("String interner desynced");
            let human_name = &self.names_map[item];
            let ins = sql::NewItem {
                human_name,
                minecraft_id,
                ty: *ty,
            };
            new_items.push(ins);
            if new_items.len() == 5000 {
                // Batch in units of 5000
                info!("Ending batch.");
                let inserted = diesel::insert_into(items::table)
                    .values(&new_items)
                    .on_conflict_do_nothing()
                    .execute(conn)
                    .expect("Failed to submit batch to database");
                info!("Inserted {} new items", inserted);
                total_inserted += inserted;
                new_items.clear();
            }
        }
        info!("Item list build complete, beginning insert");
        total_inserted += diesel::insert_into(items::table)
            .values(&new_items)
            .on_conflict_do_nothing()
            .execute(conn)
            .expect("Failed to insert into database");
        info!(
            "Insertion complete. Inserted {} new items of {} known",
            total_inserted,
            self.types_map.len()
        );
    }

    pub fn insert_recipes(&self, conn: &PgConnection) {
        let machines = self.insert_machines(conn);

        let recipe_ids = self.do_primary_recipe_insert(conn, &machines);

        let mut item_cache = Default::default();

        // Temporarily drop foreign keys.
        self.disable_recipe_fks(conn).expect("Failed to disable foreign keys");

        info!("Inserting individual recipes");

        let mut counter = 0;
        for (i, (recipe, id)) in self.recipes.iter().zip(recipe_ids.iter()).enumerate() {
            counter += self
                .insert_recipe_inputs(conn, &mut item_cache, *id, recipe)
                .expect(&format!("Failed to insert inputs for recipe {:?}", recipe));
            counter += self
                .insert_recipe_outputs(conn, &mut item_cache, *id, recipe)
                .expect(&format!("Failed to insert outputs for recipe {:?}", recipe));
            if i % (self.recipes.len() / 100) == 0 {
                info!(
                    "Inserted {} / {} recipes ({} items)",
                    i,
                    self.recipes.len(),
                    counter
                );
            }
        }

        self.enable_recipe_fks(conn).expect("Failed to reenable foreign keys");
    }

    fn disable_recipe_fks(&self, conn: &PgConnection) -> QueryResult<()> {
        warn!("Disabling a bunch of constraints. If the import dies at this point, you'll probably have to restart from scratch.");
        // Drop foreign key constraints
        diesel::sql_query("ALTER TABLE mccraft.input_slots DROP CONSTRAINT input_slots_for_recipe_fkey").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.crafting_components DROP CONSTRAINT crafting_components_crafting_slot_fkey").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.crafting_components DROP CONSTRAINT crafting_components_item_fkey").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.outputs DROP CONSTRAINT outputs_item_fkey").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.outputs DROP CONSTRAINT outputs_recipe_fkey").execute(conn)?;

        // Drop indexes
        diesel::sql_query("DROP INDEX crafting_component_item").execute(conn)?;
        diesel::sql_query("DROP INDEX crafting_component_slot").execute(conn)?;
        diesel::sql_query("DROP INDEX output_item").execute(conn)?;

        Ok(())
    }

    fn enable_recipe_fks(&self, conn: &PgConnection) -> QueryResult<()> {
        // Re-add foreign key constraints
        diesel::sql_query("ALTER TABLE mccraft.input_slots ADD CONSTRAINT input_slots_for_recipe_fkey FOREIGN KEY (for_recipe) REFERENCES mccraft.recipes(id)
").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.crafting_components ADD CONSTRAINT crafting_components_crafting_slot_fkey FOREIGN KEY (crafting_slot) REFERENCES mccraft.input_slots(id)").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.crafting_components ADD CONSTRAINT crafting_components_item_fkey FOREIGN KEY (item) REFERENCES mccraft.items(id)").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.outputs ADD CONSTRAINT outputs_item_fkey FOREIGN KEY (item) REFERENCES mccraft.items(id)").execute(conn)?;
        diesel::sql_query("ALTER TABLE mccraft.outputs ADD CONSTRAINT outputs_recipe_fkey FOREIGN KEY (recipe) REFERENCES mccraft.recipes(id)").execute(conn)?;

        // Re-add indexes
        diesel::sql_query("CREATE INDEX crafting_component_item ON crafting_components USING hash (item)").execute(conn)?;
        diesel::sql_query("CREATE INDEX crafting_component_slot ON crafting_components USING hash (crafting_slot)").execute(conn)?;
        diesel::sql_query("CREATE INDEX output_item ON outputs USING hash (item)").execute(conn)?;

        warn!("Constraints readded. The database should now be in a consistent state");

        Ok(())
    }

    // Insert machines, returning a mapping from machine name symbol to ID in the DB
    fn insert_machines(&self, conn: &PgConnection) -> FxHashMap<Sym, i32> {
        use self::schema::machines::dsl::*;
        // There are relatively few machines so we don't bother with batching
        info!("Preparing to insert machines");
        let inserted = {
            let to_insert: Vec<_> = self
                .machines
                .iter()
                .map(|(mcid, name)| sql::NewMachine {
                    human_name: name,
                    minecraft_id: self.interner.resolve(*mcid).unwrap(),
                })
                .collect();
            diesel::insert_into(machines)
                .values(&to_insert)
                .on_conflict_do_nothing()
                .execute(conn)
                .expect("Failed to insert machines")
        };
        info!(
            "Machine insert completed. {} new of {} known",
            inserted,
            self.machines.len()
        );
        info!("Retrieving all machine IDs");
        let mut machine_ids: FxHashMap<Sym, i32> = Default::default();
        machine_ids.reserve(self.machines.len());

        // Go one at a time because finding a clever way to do this seems hard
        for mcid in self.machines.keys() {
            let machine_id = self.interner.resolve(*mcid).unwrap();
            let machine_id: Vec<i32> = machines
                .select(id)
                .filter(minecraft_id.eq(machine_id))
                .load::<i32>(conn)
                .expect(&format!("Failed to load ID for machine {:?}", minecraft_id));
            assert!(machine_id.len() == 1);
            machine_ids.entry(*mcid).or_insert(machine_id[0]);
        }
        info!("Machines retrieved");

        machine_ids
    }

    /// Returns a vector of recipe IDs in the database, in the same order as the
    /// recipes appear in our internal list.
    fn do_primary_recipe_insert(
        &self,
        conn: &PgConnection,
        machines: &FxHashMap<Sym, i32>,
    ) -> Vec<i32> {
        info!("Performing primary recipe insert");
        use self::schema::recipes::dsl::*;
        let ins: Vec<_> = self
            .recipes
            .iter()
            .map(|r| sql::NewRecipe {
                machine: machines[&r.machine],
            })
            .collect();

        ins.chunks(8192)
            .flat_map(|ins_chunk| {
                diesel::insert_into(recipes)
                    .values(ins_chunk)
                    .returning(id)
                    .get_results(conn)
                    .expect("Failed to create recipe IDs")
            })
            .collect()
    }

    fn insert_recipe_inputs(
        &self,
        conn: &PgConnection,
        item_cache: &mut FxHashMap<Sym, i32>,
        rid: i32,
        recipe: &Recipe,
    ) -> QueryResult<(usize)> {
        use self::schema::{crafting_components, input_slots};

        let mut inserted_items = 0;
        let slots: Vec<sql::InputSlot> = {
            let slots: Vec<_> = recipe.inputs.iter().map(|_| sql::NewInputSlot { for_recipe: rid } ).collect();
            diesel::insert_into(input_slots::table)
                .values(slots)
                .get_results(conn)
                .expect("Failed to create input slots")
        };
        let slots: Vec<i32> = slots.into_iter().map(|x| *x.id()).collect();

        for (i, slot) in recipe.inputs.iter().enumerate() {
            let slot_id = slots[i];

            let ins: Vec<_> = slot
                .allowed_elements
                .iter()
                .map(|elem| sql::NewCraftingComponent {
                    crafting_slot: slot_id,
                    quantity: elem.get_quantity(),
                    item: self.get_item_id(conn, item_cache, elem.get_name()),
                })
                .collect();

            inserted_items += diesel::insert_into(crafting_components::table)
                .values(ins)
                .execute(conn)?;
        }

        Ok(inserted_items)
    }

    fn insert_recipe_outputs(
        &self,
        conn: &PgConnection,
        item_cache: &mut FxHashMap<Sym, i32>,
        rid: i32,
        target: &Recipe,
    ) -> QueryResult<(usize)> {
        use self::schema::outputs::dsl::*;

        let ins: Vec<_> = target
            .outputs
            .iter()
            .map(|output| sql::NewOutput {
                recipe: rid,
                quantity: output.get_quantity(),
                item: self.get_item_id(conn, item_cache, output.get_name()),
            })
            .collect();

        diesel::insert_into(outputs).values(&ins).execute(conn)
    }

    fn get_item_id(&self, conn: &PgConnection, cache: &mut FxHashMap<Sym, i32>, mcid: Sym) -> i32 {
        use self::schema::items::dsl::*;

        *cache.entry(mcid).or_insert_with(|| {
            let mcid = self.interner.resolve(mcid).unwrap();
            *items
                .select(id)
                .filter(minecraft_id.eq(mcid))
                .load::<i32>(conn)
                .expect(&format!("Failed to retrieve item ID for {:?}", mcid))
                .get(0)
                .expect(&format!("No results for mcid {:?}", mcid))
        })
    }
}
