extern crate fxhash;
extern crate mccraft_core;
extern crate serde;
extern crate serde_json;
#[macro_use]
extern crate log;
extern crate env_logger;
extern crate string_interner;

use std::ffi::OsStr;
use string_interner::Sym;

type StringInterner = string_interner::StringInterner<Sym, fxhash::FxBuildHasher>;

/// A crafting ingredient
#[derive(PartialEq, Eq, Debug, Clone)]
enum RecipeComponent {
    ItemStack { count: u32, name: Sym },
    Fluid { amount: u32, name: Sym },
}

impl RecipeComponent {
    pub fn from_fluid(interner: &mut StringInterner, fluid: &mccraft_core::json::Fluid) -> Self {
        RecipeComponent::Fluid {
            amount: fluid.amount as u32,
            name: interner.get_or_intern(fluid.ty.as_str()),
        }
    }

    pub fn from_item(interner: &mut StringInterner, item: &mccraft_core::json::ItemStack) -> Self {
        RecipeComponent::ItemStack {
            count: item.amount as u32,
            name: interner.get_or_intern(item.ty.as_str()),
        }
    }

    fn get_name(&self) -> Sym {
        match *self {
            RecipeComponent::ItemStack { name, .. } | RecipeComponent::Fluid { name, .. } => name,
        }
    }
}

/// A slot that holds crafting ingredients
#[derive(PartialEq, Eq, Debug, Clone)]
struct CraftingSlot {
    allowed_elements: Vec<RecipeComponent>,
}

impl CraftingSlot {
    pub fn new() -> CraftingSlot {
        CraftingSlot {
            allowed_elements: Vec::new(),
        }
    }
}

/// An individual recipe
#[derive(PartialEq, Eq, Debug, Clone)]
struct Recipe {
    machine: Sym,
    inputs: Vec<CraftingSlot>,
    outputs: Vec<RecipeComponent>,
}

impl Recipe {
    pub fn new(machine: Sym) -> Self {
        Recipe {
            machine,
            inputs: Vec::new(),
            outputs: Vec::new(),
        }
    }
}

/// Database of all recipes
struct RecipeDatabase {
    recipes: Vec<Recipe>,
}

impl RecipeDatabase {
    pub fn new() -> Self {
        RecipeDatabase {
            recipes: Vec::new(),
        }
    }

    pub fn add_recipe(&mut self, recipe: Recipe) {
        self.recipes.push(recipe);
    }
}

/// Generic error type for passing around inside
#[derive(Debug)]
enum MCCraftError {
    IOError(std::io::Error),
    DeserializeError(serde_json::error::Error),
}

impl From<std::io::Error> for MCCraftError {
    fn from(o: std::io::Error) -> Self {
        MCCraftError::IOError(o)
    }
}

impl From<serde_json::error::Error> for MCCraftError {
    fn from(o: serde_json::error::Error) -> Self {
        MCCraftError::DeserializeError(o)
    }
}

// Convert a list of fluids into a slot that accepts any of those fluids
fn slot_from_fluids(
    interner: &mut StringInterner,
    ingredient: &mccraft_core::json::IngredientFluid,
) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.fluids.len());
    for ref fluid in &ingredient.fluids {
        slot.allowed_elements.push(RecipeComponent::from_fluid(interner, fluid));
    }

    slot
}

fn slot_from_items(
    interner: &mut StringInterner,
    ingredient: &mccraft_core::json::IngredientItem,
) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.stacks.len());
    for ref stack in &ingredient.stacks {
        slot.allowed_elements.push(RecipeComponent::from_item(interner, stack));
    }

    slot
}

fn handle_covariant_recipe(
    db: &mut RecipeDatabase,
    interner: &mut StringInterner,
    machine: Sym,
    jrecipe: &mccraft_core::json::Recipe,
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
            template.inputs.push(slot_from_items(interner, &item_slot));
        } else {
            // We can only deal with one kind of covariance at a time
            assert!(item_slot.stacks.len() == 1);
            template.outputs.push(RecipeComponent::from_item(interner, &item_slot.stacks[0]));
        }
    }

    // Blindly push all of the fluids onto the template
    for ref fluid_slot in &jrecipe.ingredient_fluids {
        if fluid_slot.fluids.len() == 0 {
            continue;
        }

        if fluid_slot.is_input {
            let slot = slot_from_fluids(interner, &fluid_slot);
            template.inputs.push(slot);
        } else {
            // we don't handle covariance for fluids, so there better only be one output
            assert!(fluid_slot.fluids.len() == 1);
            template.outputs.push(RecipeComponent::from_fluid(interner, &fluid_slot.fluids[0]))
        }
    }

    // Using the template, push out recipe variants for all the covariants.
    for i in 0..covariant_count {
        let mut recipe = template.clone();

        for ref input in &covariant_inputs {
            let mut slot = CraftingSlot::new();
            slot.allowed_elements.push(RecipeComponent::from_item(interner, &input.stacks[i]));
            recipe.inputs.push(slot);
        }

        for ref output in &covariant_outputs {
            recipe.outputs.push(RecipeComponent::from_item(interner, &output.stacks[i]));
        }

        db.add_recipe(recipe);
    }
}

fn import_recipes(
    db: &mut RecipeDatabase,
    interner: &mut StringInterner,
    json_path: impl AsRef<std::path::Path>,
) -> Result<(), MCCraftError> {
    let instance_file = std::fs::File::open(json_path.as_ref())?;
    let instance: mccraft_core::json::CraftingInstance = serde_json::from_reader(instance_file)?;
    let machine = interner.get_or_intern(instance.category);
    let mut discard_recipe = false;
    for jrecipe in instance.recipes {
        let mut recipe = Recipe::new(machine);
        for item_slot in &jrecipe.ingredient_items {
            if item_slot.stacks.len() == 0 {
                continue;
            }

            let slot = slot_from_items(interner, &item_slot);
            if item_slot.is_input {
                recipe.inputs.push(slot);
            } else {
                if item_slot.stacks.len() != 1 {
                    handle_covariant_recipe(
                        db,
                        interner,
                        machine,
                        &jrecipe,
                        item_slot.stacks.len(),
                    );
                    discard_recipe = true;
                }
                recipe.outputs.push(RecipeComponent::from_item(interner, &item_slot.stacks[0]));
            }
        }
        for fluid_slot in jrecipe.ingredient_fluids {
            if fluid_slot.fluids.len() == 0 {
                continue;
            }

            if fluid_slot.is_input {
                let slot = slot_from_fluids(interner, &fluid_slot);
                recipe.inputs.push(slot);
            } else {
                assert!(fluid_slot.fluids.len() == 1);
                recipe.outputs.push(RecipeComponent::from_fluid(interner, &fluid_slot.fluids[0]));
            }
        }
        if !discard_recipe {
            db.add_recipe(recipe);
        }
        discard_recipe = false;
    }

    Ok(())
}

fn main() {
    let env = env_logger::Env::default().filter_or(env_logger::DEFAULT_FILTER_ENV, "info");
    env_logger::Builder::from_env(env).init();

    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() != 2 {
        error!("Need path to jeiexporter folder");
        return;
    }

    let base_folder = std::path::PathBuf::from(arguments[1].to_owned());
    let exports_folder = base_folder.join("exports");

    let mut db = RecipeDatabase::new();
    let mut interner = StringInterner::with_hasher(Default::default());

    for file in exports_folder
        .read_dir()
        .expect("iterator over exports folder")
    {
        info!("Processing file {:?}", file);
        if !file.is_ok() {
            warn!("skipping file {:?}", file);
            continue;
        }
        let file = file.unwrap();
        let file = file.path();
        let file_name = file.file_name();
        if file_name == Some(OsStr::new("tooltipMap.json")) {
            warn!("Reading tooltipMap not implemented yet");
        } else if file_name == Some(OsStr::new("lookupMap.json")) {
            warn!("Reading lookupMap not implemented yet");
        } else {
            let start_len = db.recipes.len();
            match import_recipes(&mut db, &mut interner, &file) {
                Ok(()) => info!(
                    "Processing completed successfully. {} recipes added",
                    db.recipes.len() - start_len
                ),
                Err(e) => warn!("Processing failed {:?}", e),
            }
        }
    }

    println!("Processed {:?} recipes", db.recipes.len());
}
