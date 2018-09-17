use ::schema::mccraft::*;

#[derive(Serialize, Deserialize, DbEnum, Debug, Copy, Clone)]
pub enum ItemType {
    Item,
    Fluid,
}

#[derive(Serialize, Identifiable, Queryable, Debug)]
pub struct Item {
    pub id: i32,
    pub ty: ItemType,
    pub human_name: String,
    pub minecraft_id: String,
}

#[derive(Insertable, Debug)]
#[table_name = "items"]
pub struct NewItem<'a> {
    pub human_name: &'a str,
    pub minecraft_id: &'a str,
    pub ty: ItemType,
}

#[derive(Identifiable, Queryable, PartialEq, Eq, Debug)]
pub struct Machine {
    pub id: i32,
    pub human_name: String,
    pub minecraft_id: String,
}

#[derive(Insertable, Debug)]
#[table_name = "machines"]
pub struct NewMachine<'a> {
    pub human_name: &'a str,
    pub minecraft_id: &'a str,
}

#[derive(Identifiable, Queryable, Associations, PartialEq, Eq, Debug)]
#[belongs_to(Machine, foreign_key = "machine")]
pub struct Recipe {
    pub id: i32,
    pub machine: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "recipes"]
pub struct NewRecipe {
    pub machine: i32,
}

#[derive(Identifiable, Queryable, Associations, PartialEq, Eq, Debug)]
#[belongs_to(Recipe, foreign_key = "recipe")]
#[belongs_to(Item, foreign_key = "item")]
pub struct Output {
    pub id: i32,
    pub recipe: i32,
    pub quantity: i32,
    pub item: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "outputs"]
pub struct NewOutput {
    pub recipe: i32,
    pub quantity: i32,
    pub item: i32,
}

#[derive(Identifiable, Queryable, Associations, PartialEq, Eq, Debug)]
#[belongs_to(Recipe, foreign_key = "for_recipe")]
pub struct InputSlot {
    pub id: i32,
    pub for_recipe: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "input_slots"]
pub struct NewInputSlot {
    pub for_recipe: i32,
}

#[derive(Identifiable, Queryable, Associations, PartialEq, Eq, Debug)]
#[belongs_to(InputSlot, foreign_key = "crafting_slot")]
#[table_name = "crafting_components"]
pub struct CraftingComponent {
    pub id: i32,
    pub crafting_slot: i32,
    pub quantity: i32,
    pub item: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "crafting_components"]
pub struct NewCraftingComponent {
    pub crafting_slot: i32,
    pub quantity: i32,
    pub item: i32,
}
