use super::DbExecutor;
use actix_web::actix::*;
use diesel::prelude::*;
use mccraft_core::schema::mccraft as schema;
use mccraft_core::sql;
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

pub struct SearchItems {
    pub name: String,
    pub limit: i64,
    pub offset: i64,
}

impl Message for SearchItems {
    type Result = QueryResult<Vec<sql::Item>>;
}

impl Handler<SearchItems> for DbExecutor {
    type Result = <SearchItems as Message>::Result;

    fn handle(&mut self, mut msg: SearchItems, _: &mut Self::Context) -> Self::Result {
        use self::schema::{items, outputs};
        msg.name.push('%');
        Ok(items::table
            .inner_join(outputs::table)
            .filter(items::human_name.ilike(msg.name))
            .limit(msg.limit)
            .offset(msg.offset)
            .order_by((items::human_name, items::id))
            .distinct_on((items::human_name, items::id))
            .select((items::id, items::ty, items::human_name, items::minecraft_id))
            .load::<sql::Item>(&self.0)?)
    }
}
