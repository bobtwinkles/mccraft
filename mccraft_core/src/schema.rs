pub mod mccraft {
    table! {
        mccraft.crafting_components (id) {
            id -> Int4,
            crafting_slot -> Int4,
            item -> Int4,
            quantity -> Int4,
        }
    }

    table! {
        mccraft.input_slots (id) {
            id -> Int4,
            for_recipe -> Int4,
        }
    }

    table! {
        use diesel::sql_types::*;
        use sql::ItemTypeMapping;

        mccraft.items (id) {
            id -> Int4,
            ty -> ItemTypeMapping,
            human_name -> Text,
            minecraft_id -> Text,
        }
    }

    table! {
        mccraft.machines (id) {
            id -> Int4,
            human_name -> Text,
            minecraft_id -> Text,
        }
    }

    table! {
        mccraft.outputs (id) {
            id -> Int4,
            recipe -> Int4,
            quantity -> Int4,
            item -> Int4,
        }
    }

    table! {
        mccraft.recipes (id) {
            id -> Int4,
            machine -> Int4,
        }
    }

    joinable!(crafting_components -> input_slots (crafting_slot));
    joinable!(crafting_components -> items (item));
    joinable!(input_slots -> recipes (for_recipe));
    joinable!(outputs -> items (item));
    joinable!(outputs -> recipes (recipe));
    joinable!(recipes -> machines (machine));

    allow_tables_to_appear_in_same_query!(
        crafting_components,
        input_slots,
        items,
        machines,
        outputs,
        recipes,
    );
}
