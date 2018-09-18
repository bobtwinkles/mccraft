//! Types for use when communicating between the web server and frontend

use sql::ItemType;

/// Specifies an input or output item
#[derive(Serialize, Deserialize, Queryable, Debug, Clone)]
pub struct ItemSpec {
    /// Internal ID # for the item.
    pub item_id: i32,
    /// Human-readable name
    pub item_name: String,
    /// Minecraft string ID for the item
    pub minecraft_id: String,
    /// What kind of item is it (item stack, fluid, etc.)
    pub ty: ItemType,
    /// The amount of the item
    pub quantity: i32,
}

/// An input item slot
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct InputSlot {
    pub items: Vec<ItemSpec>,
}

/// The data required to complete a PartialRecipe
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Recipe {
    /// The inputs to the recipe
    pub input_slots: Vec<InputSlot>,
    /// The things produced by this recipe
    pub outputs: Vec<ItemSpec>,
}

/// A partial recipe. For when we only care about the fact that a particular
/// machine can make a given thing.
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PartialRecipe {
    pub machine_name: String,
    pub machine_id: i32,
    pub recipe_id: i32,
}
