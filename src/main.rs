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

fn slot_from_fluids(
    interner: &mut StringInterner,
    ingredient: &mccraft_core::json::IngredientFluid,
) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.fluids.len());
    for ref fluid in &ingredient.fluids {
        slot.allowed_elements.push(RecipeComponent::Fluid {
            amount: fluid.amount as u32,
            name: interner.get_or_intern(fluid.ty.as_str()),
        })
    }

    slot
}

fn slot_from_items(
    interner: &mut StringInterner,
    ingredient: &mccraft_core::json::IngredientItem,
) -> CraftingSlot {
    let mut slot = CraftingSlot::new();
    slot.allowed_elements.reserve(ingredient.stacks.len());
    for stack in &ingredient.stacks {
        slot.allowed_elements.push(RecipeComponent::ItemStack {
            count: stack.amount as u32,
            name: interner.get_or_intern(stack.ty.as_str()),
        });
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
    let template = Recipe::new(machine);
    // TODO
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
                    handle_covariant_recipe(db, interner, machine, &jrecipe, item_slot.stacks.len());
                    discard_recipe = true;
                }
                recipe.outputs.push(RecipeComponent::ItemStack {
                    count: item_slot.stacks[0].amount as u32,
                    name: interner.get_or_intern(item_slot.stacks[0].ty.as_str()),
                })
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
                recipe.outputs.push(RecipeComponent::Fluid {
                    amount: fluid_slot.fluids[0].amount as u32,
                    name: interner.get_or_intern(fluid_slot.fluids[0].ty.as_str()),
                })
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
