use super::DbExecutor;
use actix::prelude::*;
use diesel::prelude::*;
use fxhash::FxHashMap;
use mccraft_core::schema::mccraft as schema;
use mccraft_core::sql;
use mccraft_core::web::{self, InputSlot, ItemSpec, PartialRecipe};

/// Retrieve the entire recipe.
pub struct Recipe(pub PartialRecipe);

impl Message for Recipe {
    type Result = QueryResult<web::Recipe>;
}

impl Handler<Recipe> for DbExecutor {
    type Result = <Recipe as Message>::Result;

    fn handle(&mut self, msg: Recipe, _: &mut Self::Context) -> Self::Result {
        use self::schema::{crafting_components, input_slots, items, outputs};

        // Get all the data we need about the outputs.
        let outputs: Vec<ItemSpec> = outputs::table
            .inner_join(items::table)
            .filter(outputs::recipe.eq(msg.0.recipe_id))
            .select((
                items::id,
                items::human_name,
                items::minecraft_id,
                items::ty,
                outputs::quantity,
            )).load::<ItemSpec>(&self.0)?;

        // Get all the data about all of the inputs
        let inputs: Vec<_> = crafting_components::table
            .inner_join(items::table)
            .inner_join(input_slots::table)
            .filter(input_slots::for_recipe.eq(msg.0.recipe_id))
            .select((
                input_slots::id,
                items::id,
                items::human_name,
                items::minecraft_id,
                items::ty,
                crafting_components::quantity,
            )).load::<(i32, i32, String, String, sql::ItemType, i32)>(&self.0)?
            .into_iter()
            .map(|v| (v.0, (v.1, v.2, v.3, v.4, v.5)))
            .collect();

        let mut inputs_flattened: FxHashMap<i32, _> = Default::default();
        for (k, v) in inputs.into_iter() {
            inputs_flattened
                .entry(k)
                .or_insert_with(Vec::new)
                .push(ItemSpec {
                    item_id: v.0,
                    item_name: v.1,
                    minecraft_id: v.2,
                    ty: v.3,
                    quantity: v.4,
                });
        }

        let inputs: Vec<InputSlot> = inputs_flattened
            .into_iter()
            .map(|(_, v)| InputSlot { items: v })
            .collect();

        Ok(web::Recipe {
            id: msg.0.recipe_id,
            machine_name: msg.0.machine_name,
            machine_id: msg.0.machine_id,
            input_slots: inputs,
            outputs,
        })
    }
}

/// Get information about a specific item.
pub struct Item(pub i32);

impl Message for Item {
    type Result = QueryResult<sql::Item>;
}

impl Handler<Item> for DbExecutor {
    type Result = <Item as Message>::Result;

    fn handle(&mut self, msg: Item, _: &mut Self::Context) -> Self::Result {
        use self::schema::items::dsl::*;

        items.find(msg.0).first::<sql::Item>(&self.0)
    }
}
