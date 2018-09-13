use crate::schema::mccraft::*;

#[derive(DbEnum, Debug, Copy, Clone)]
pub enum ItemType {
    Item,
    Fluid,
}

#[derive(Identifiable, Queryable, Debug)]
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

#[derive(Insertable, Debug)]
#[table_name = "machines"]
pub struct NewMachine<'a> {
    pub human_name: &'a str,
    pub minecraft_id: &'a str,
}

#[derive(Insertable, Debug)]
#[table_name = "recipes"]
pub struct NewRecipe {
    pub machine: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "outputs"]
pub struct NewOutput {
    pub recipe: i32,
    pub quantity: i32,
    pub item: i32,
}

#[derive(Identifiable, Queryable, Debug)]
pub struct InputSlot {
    pub id: i32,
    pub for_recipe: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "input_slots"]
pub struct NewInputSlot {
    pub for_recipe: i32,
}

#[derive(Insertable, Debug)]
#[table_name = "crafting_components"]
pub struct NewCraftingComponent {
    pub crafting_slot: i32,
    pub quantity: i32,
    pub item: i32,
}
