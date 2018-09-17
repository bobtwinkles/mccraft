use super::DbExecutor;
use actix_web::actix::*;
use diesel::prelude::*;
use mccraft_core::schema::mccraft as schema;
use mccraft_core::web::PartialRecipe;

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
