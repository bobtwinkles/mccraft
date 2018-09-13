/// Structures for loading the lookupMap
pub mod lookup;
/// Structures for loading the recipe types
pub mod recipe;
/// Structures for loading the tooltipMap
pub mod tooltip;

use serde::{Deserialize, Deserializer};

/// A custom Serde deserializer that can read a JSON list with nulls in it
fn deser_skip_nulls_list<'de, D, T>(deser: D) -> Result<Vec<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    use serde::de::{SeqAccess, Visitor};
    use std::fmt;
    use std::marker::PhantomData;

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
