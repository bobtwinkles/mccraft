use super::DbExecutor;
use actix_web::actix::*;
use diesel::prelude::*;
use fxhash::FxHashMap;
use mccraft_core::schema::mccraft as schema;
use mccraft_core::sql;
use mccraft_core::web::{self, InputSlot, ItemSpec, PartialRecipe, Recipe};

/// Search the outputs of all recipes
pub enum SearchOutputs {
    ByName(String),
    ById(i32),
}

impl Message for SearchOutputs {
    type Result = QueryResult<Vec<PartialRecipe>>;
}

impl DbExecutor {
    fn handle_search_outputs_by_name(
        &self,
        mut query: String,
    ) -> <SearchOutputs as Message>::Result {
        use self::schema::{items, machines, outputs, recipes};
        query.push('%');

        Ok(machines::table
            .inner_join(recipes::table.on(recipes::machine.eq(machines::id)))
            .inner_join(outputs::table.on(outputs::recipe.eq(recipes::id)))
            .inner_join(items::table.on(outputs::item.eq(items::id)))
            .filter(items::human_name.ilike(query))
            .select((machines::id, machines::human_name, recipes::id))
            .load::<(i32, String, i32)>(&self.0)?
            .into_iter()
            .map(|(mid, mn, rid)| PartialRecipe {
                machine_id: mid,
                machine_name: mn,
                recipe_id: rid,
            }).collect())
    }

    fn handle_search_outputs_by_id(&self, id: i32) -> <SearchOutputs as Message>::Result {
        use self::schema::{machines, outputs, recipes};
        Ok(machines::table
            .inner_join(recipes::table.on(recipes::machine.eq(machines::id)))
            .inner_join(outputs::table.on(outputs::recipe.eq(recipes::id)))
            .filter(outputs::item.eq(id))
            .select((machines::id, machines::human_name, recipes::id))
            .load::<(i32, String, i32)>(&self.0)?
            .into_iter()
            .map(|(mid, mn, rid)| PartialRecipe {
                machine_id: mid,
                machine_name: mn,
                recipe_id: rid,
            }).collect())
    }
}

impl Handler<SearchOutputs> for DbExecutor {
    type Result = <SearchOutputs as Message>::Result;

    fn handle(&mut self, msg: SearchOutputs, _: &mut Self::Context) -> Self::Result {
        match msg {
            SearchOutputs::ByName(hn) => self.handle_search_outputs_by_name(hn),
            SearchOutputs::ById(id) => self.handle_search_outputs_by_id(id),
        }
    }
}

/// Retrieve the entire recipe.
pub struct RetrieveRecipe {
    pub partial: PartialRecipe,
}

impl Message for RetrieveRecipe {
    type Result = QueryResult<web::Recipe>;
}

impl Handler<RetrieveRecipe> for DbExecutor {
    type Result = <RetrieveRecipe as Message>::Result;

    fn handle(&mut self, msg: RetrieveRecipe, _: &mut Self::Context) -> Self::Result {
        use self::schema::{crafting_components, input_slots, items, outputs};

        // Get all the data we need about the outputs.
        let outputs: Vec<ItemSpec> = outputs::table
            .inner_join(items::table)
            .filter(outputs::recipe.eq(msg.partial.recipe_id))
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
            .filter(input_slots::for_recipe.eq(msg.partial.recipe_id))
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

        Ok(Recipe {
            id: msg.partial.recipe_id,
            machine_name: msg.partial.machine_name,
            machine_id: msg.partial.machine_id,
            input_slots: inputs,
            outputs,
        })
    }
}
