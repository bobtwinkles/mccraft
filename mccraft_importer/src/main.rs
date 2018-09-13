extern crate fxhash;
extern crate mccraft_core;
extern crate serde;
extern crate serde_json;
#[macro_use]
extern crate log;
extern crate diesel;
extern crate dotenv;
extern crate env_logger;
extern crate string_interner;

mod recipe_db;
mod types;

use diesel::{Connection, PgConnection};
use mccraft_core::json::recipe;
use std::collections::HashMap;
use std::ffi::OsStr;
use string_interner::Sym;

use recipe_db::RecipeDatabase;
use types::*;

// Convert a list of fluids into a slot that accepts any of those fluids
fn slot_from_fluids(db: &mut RecipeDatabase, ingredient: &recipe::IngredientFluid) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.fluids.len());
    for ref fluid in &ingredient.fluids {
        slot.allowed_elements
            .push(RecipeComponent::from_fluid(db, fluid));
    }

    slot
}

fn slot_from_items(db: &mut RecipeDatabase, ingredient: &recipe::IngredientItem) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.stacks.len());
    for ref stack in &ingredient.stacks {
        slot.allowed_elements
            .push(RecipeComponent::from_item(db, stack));
    }

    slot
}

fn handle_covariant_recipe(
    db: &mut RecipeDatabase,
    machine: Sym,
    jrecipe: &recipe::Recipe,
    covariant_count: usize,
) {
    let mut template = Recipe::new(machine);
    let mut covariant_inputs = Vec::new();
    let mut covariant_outputs = Vec::new();

    // Push all the item slots that aren't covariant in to the template
    for item_slot in &jrecipe.ingredient_items {
        if item_slot.stacks.len() == 0 {
            // We don't care about slots with nothing in them
            continue;
        }

        if item_slot.stacks.len() == covariant_count {
            // This is one of the stacks that is covariant. Stuff a reference to it into the right list
            if item_slot.is_input {
                covariant_inputs.push(item_slot);
            } else {
                covariant_outputs.push(item_slot);
            }
            continue;
        }

        // Otherwise, add it to the template
        if item_slot.is_input {
            template.inputs.push(slot_from_items(db, &item_slot));
        } else {
            // We can only deal with one kind of covariance at a time
            assert!(item_slot.stacks.len() == 1);
            template
                .outputs
                .push(RecipeComponent::from_item(db, &item_slot.stacks[0]));
        }
    }

    // Blindly push all of the fluids onto the template
    for ref fluid_slot in &jrecipe.ingredient_fluids {
        if fluid_slot.fluids.len() == 0 {
            continue;
        }

        if fluid_slot.is_input {
            let slot = slot_from_fluids(db, &fluid_slot);
            template.inputs.push(slot);
        } else {
            // we don't handle covariance for fluids, so there better only be one output
            assert!(fluid_slot.fluids.len() == 1);
            template
                .outputs
                .push(RecipeComponent::from_fluid(db, &fluid_slot.fluids[0]))
        }
    }

    // Using the template, push out recipe variants for all the covariants.
    for i in 0..covariant_count {
        let mut recipe = template.clone();

        for ref input in &covariant_inputs {
            let mut slot = CraftingSlot::new();
            slot.allowed_elements
                .push(RecipeComponent::from_item(db, &input.stacks[i]));
            recipe.inputs.push(slot);
        }

        for ref output in &covariant_outputs {
            recipe
                .outputs
                .push(RecipeComponent::from_item(db, &output.stacks[i]));
        }

        db.add_recipe(recipe);
    }
}

/// The primary recipe import procedure
fn import_recipes(
    db: &mut RecipeDatabase,
    json_path: impl AsRef<std::path::Path>,
) -> Result<(), MCCraftError> {
    let instance_file = std::fs::File::open(json_path.as_ref())?;
    let instance: recipe::CraftingInstance = serde_json::from_reader(instance_file)?;
    let machine = db.get_or_intern(instance.bg.tex);
    db.add_machine(machine, instance.category);

    let mut discard_recipe = false;
    for jrecipe in instance.recipes {
        let mut recipe = Recipe::new(machine);
        for item_slot in &jrecipe.ingredient_items {
            if item_slot.stacks.len() == 0 {
                continue;
            }

            let slot = slot_from_items(db, &item_slot);
            if item_slot.is_input {
                recipe.inputs.push(slot);
            } else {
                if item_slot.stacks.len() != 1 {
                    handle_covariant_recipe(db, machine, &jrecipe, item_slot.stacks.len());
                    discard_recipe = true;
                }
                recipe
                    .outputs
                    .push(RecipeComponent::from_item(db, &item_slot.stacks[0]));
            }
        }
        for fluid_slot in jrecipe.ingredient_fluids {
            if fluid_slot.fluids.len() == 0 {
                continue;
            }

            if fluid_slot.is_input {
                let slot = slot_from_fluids(db, &fluid_slot);
                recipe.inputs.push(slot);
            } else {
                assert!(fluid_slot.fluids.len() == 1);
                recipe
                    .outputs
                    .push(RecipeComponent::from_fluid(db, &fluid_slot.fluids[0]));
            }
        }
        if !discard_recipe {
            db.add_recipe(recipe);
        }
        discard_recipe = false;
    }

    Ok(())
}

/// Parses the tooltips, returning a map from MC ID to human-readable name.
fn import_tooltips(
    db: &mut RecipeDatabase,
    json_path: impl AsRef<std::path::Path>,
) -> Result<(), MCCraftError> {
    let instance_file = std::fs::File::open(json_path.as_ref())?;
    let tooltips: HashMap<String, String> = serde_json::from_reader(instance_file)?;

    for (mc_name, human_name) in tooltips.into_iter() {
        let mc_name = db.get_or_intern(mc_name);
        db.associate_name(mc_name, human_name);
    }

    Ok(())
}

fn ingest(path: &std::path::PathBuf) -> RecipeDatabase {
    let mut db = RecipeDatabase::new();

    for file in path.read_dir().expect("iterator over exports folder") {
        info!("Processing file {:?}", file);
        if !file.is_ok() {
            warn!("skipping file {:?}", file);
            continue;
        }
        let file = file.unwrap();
        let file = file.path();
        let file_name = file.file_name();
        if file_name == Some(OsStr::new("tooltipMap.json")) {
            import_tooltips(&mut db, &file).expect("Failed to import tooltip map");
        } else if file_name == Some(OsStr::new("lookupMap.json")) {
            info!("Skipping lookup map since it's just an inverse tooltip map");
        } else {
            let start_len = db.num_recipes();
            match import_recipes(&mut db, &file) {
                Ok(()) => info!(
                    "Processing completed successfully. {} recipes added",
                    db.num_recipes() - start_len
                ),
                Err(e) => warn!("Processing failed {:?}", e),
            }
        }
    }

    println!("Ingested {:?} recipes", db.num_recipes());

    db
}

fn main() {
    dotenv::dotenv().ok();
    let env = env_logger::Env::default().filter_or(env_logger::DEFAULT_FILTER_ENV, "info");
    env_logger::Builder::from_env(env).init();

    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() != 2 {
        error!("Need path to jeiexporter folder");
        return;
    }

    let base_folder = std::path::PathBuf::from(arguments[1].to_owned());
    let exports_folder = base_folder.join("exports");

    let recipe_db = ingest(&exports_folder);

    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    info!("Connecting to database {}", database_url);

    let conn = PgConnection::establish(&database_url)
        .expect(&format!("error connecting to {}", database_url));

    recipe_db.insert_items(&conn);
    recipe_db.insert_recipes(&conn);
}
