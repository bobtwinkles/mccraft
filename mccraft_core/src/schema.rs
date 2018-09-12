#[derive(DbEnum, Debug)]
pub enum ItemType {
    Item, Fluid,
}

table! {
    crafting_components (id) {
        id -> Int4,
        crafting_slot -> Int4,
        item -> Int4,
        quantity -> Int4,
    }
}

table! {
    input_slots (id) {
        id -> Int4,
        for_recipe -> Int4,
    }
}

table! {
    use diesel::sql_types::*;
    use super::ItemTypeMapping;

    items (id) {
        id -> Int4,
        ty -> ItemTypeMapping,
        human_name -> Text,
        minecraft_id -> Text,
    }
}

table! {
    machines (id) {
        id -> Int4,
        human_name -> Text,
        minecraft_id -> Text,
    }
}

table! {
    recipes (id) {
        id -> Int4,
        machine -> Int4,
        output_quantity -> Int4,
        output_item -> Int4,
    }
}

joinable!(crafting_components -> input_slots (crafting_slot));
joinable!(crafting_components -> items (item));
joinable!(input_slots -> recipes (for_recipe));
joinable!(recipes -> items (output_item));
joinable!(recipes -> machines (machine));

allow_tables_to_appear_in_same_query!(
    crafting_components,
    input_slots,
    items,
    machines,
    recipes,
);
