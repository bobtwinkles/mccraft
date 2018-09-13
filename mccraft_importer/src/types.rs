use fxhash::FxBuildHasher;
use mccraft_core::json::recipe;
use mccraft_core::sql::ItemType;
use serde_json::error::Error as JSONError;
use std::io;
use string_interner::{self, Sym};
use ::recipe_db::RecipeDatabase;

pub type StringInterner = string_interner::StringInterner<Sym, FxBuildHasher>;

/// A crafting ingredient
#[derive(PartialEq, Eq, Debug, Clone)]
pub enum RecipeComponent {
    ItemStack { count: u32, name: Sym },
    Fluid { amount: u32, name: Sym },
}

impl RecipeComponent {
    /// Create a RecipeComponent from a JSON Fluid
    pub fn from_fluid(db: &mut RecipeDatabase, fluid: &recipe::Fluid) -> Self {
        let name = db.get_or_intern(fluid.ty.as_str());
        db.associate_type(name, ItemType::Fluid);
        RecipeComponent::Fluid {
            amount: fluid.amount as u32,
            name: name,
        }
    }

    /// Create a RecipeComponent from a JSON ItemStack
    pub fn from_item(db: &mut RecipeDatabase, item: &recipe::ItemStack) -> Self {
        let name = db.get_or_intern(item.ty.as_str());
        db.associate_type(name, ItemType::Item);

        RecipeComponent::ItemStack {
            count: item.amount as u32,
            name: name,
        }
    }

    pub fn get_name(&self) -> Sym {
        match *self {
            RecipeComponent::ItemStack { name, .. } | RecipeComponent::Fluid { name, .. } => name,
        }
    }

    pub fn get_quantity(&self) -> i32 {
        match *self {
            RecipeComponent::ItemStack { count, .. } => count as i32,
            RecipeComponent::Fluid { amount, .. } => amount as i32,
        }
    }
}

/// A slot that holds crafting ingredients
#[derive(PartialEq, Eq, Debug, Clone)]
pub struct CraftingSlot {
    pub allowed_elements: Vec<RecipeComponent>,
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
pub struct Recipe {
    pub machine: Sym,
    pub inputs: Vec<CraftingSlot>,
    pub outputs: Vec<RecipeComponent>,
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

/// Generic error type for passing around inside
#[derive(Debug)]
pub enum MCCraftError {
    IOError(io::Error),
    DeserializeError(JSONError),
}

impl From<io::Error> for MCCraftError {
    fn from(o: io::Error) -> Self {
        MCCraftError::IOError(o)
    }
}

impl From<JSONError> for MCCraftError {
    fn from(o: JSONError) -> Self {
        MCCraftError::DeserializeError(o)
    }
}
