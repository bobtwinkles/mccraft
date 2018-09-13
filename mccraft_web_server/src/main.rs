extern crate diesel;
extern crate dotenv;
extern crate env_logger;
#[macro_use]
extern crate log;
extern crate mccraft_core;

use diesel::PgConnection;
use diesel::pg::Pg;
use diesel::prelude::*;
use mccraft_core::sql::{Machine, Recipe, Output, Item};
use mccraft_core::schema::mccraft as schema;

fn load_data(conn: &PgConnection, machine_id: i32) -> QueryResult<Vec<(Recipe, Vec<(Output, Item)>)>> {
    let machine = schema::machines::table
        .find(machine_id)
        .first::<Machine>(conn)?;
    info!("Loaded machine {:?}", machine);

    let recipes = Recipe::belonging_to(&machine).load::<Recipe>(conn)?;

    info!("It has {} recipes", recipes.len());


    let outputs = {
        let outputs = Output::belonging_to(&recipes)
            .inner_join(schema::items::table.on(schema::items::id.eq(schema::outputs::item)));

        info!("Executing query {}", diesel::debug_query::<Pg, _>(&outputs).to_string());

        outputs
    }.load::<(Output, Item)>(conn)?
        .grouped_by(&recipes);

    Ok(recipes.into_iter().zip(outputs).collect())
}

fn main() {
    dotenv::dotenv().ok();
    let env = env_logger::Env::default().filter_or(env_logger::DEFAULT_FILTER_ENV, "info");
    env_logger::Builder::from_env(env).init();

    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    info!("Connecting to database {}", database_url);

    let conn = PgConnection::establish(&database_url)
        .expect(&format!("error connecting to {}", database_url));

    let data = load_data(&conn, 2).expect("Failed to load data");

    for (recipe, outputs) in data {
        info!("Recipe {} has outputs: ", recipe.id());
        for output in outputs {
            info!("  {}x {}", output.0.quantity, output.1.human_name)
        }
    }
}
