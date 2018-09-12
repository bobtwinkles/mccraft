use serde::{Deserialize, Deserializer};
use std::marker::PhantomData;

#[derive(Serialize, Deserialize, Debug)]
pub struct BackgroundImage {
    #[serde(rename = "w")]
    pub width: i32,
    #[serde(rename = "h")]
    pub height: i32,
    pub tex: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct ItemStack {
    pub amount: i32,
    #[serde(rename = "type")]
    pub ty: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct Fluid {
    pub amount: i32,
    #[serde(rename = "type")]
    pub ty: String,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct IngredientItem {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub p: u32,
    #[serde(rename = "in")]
    pub is_input: bool,
    #[serde(deserialize_with = "deser_skip_nulls_list")]
    pub stacks: Vec<ItemStack>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct IngredientFluid {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub p: u32,
    #[serde(rename = "in")]
    pub is_input: bool,
    #[serde(deserialize_with = "deser_skip_nulls_list")]
    pub fluids: Vec<Fluid>,
}

#[derive(Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Recipe {
    pub ingredient_items: Vec<IngredientItem>,
    pub ingredient_fluids: Vec<IngredientFluid>,
}

#[derive(Serialize, Deserialize, Debug)]
pub struct CraftingInstance {
    pub category: String,
    pub bg: BackgroundImage,
    pub recipes: Vec<Recipe>,
}

fn deser_skip_nulls_list<'de, D, T>(deser: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    use serde::de::{SeqAccess, Visitor};
    use std::fmt;
    struct SeqVisit<T> {
        phantom: PhantomData<fn() -> T>,
    };

    impl<'de, T: Deserialize<'de>> Visitor<'de> for SeqVisit<T> {
        type Value = Vec<T>;

        fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
            write!(formatter, "a sequence of item stacks")
        }

        fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Vec<T>, A::Error> {
            let mut tr = Vec::new();
            while let Some(v) = seq.next_element::<Option<T>>()? {
                if v.is_some() {
                    tr.push(v.unwrap())
                }
            }

            Ok(tr)
        }
    }

    deser.deserialize_seq(SeqVisit {
        phantom: PhantomData,
    })
}
