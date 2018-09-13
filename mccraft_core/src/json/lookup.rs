use std::collections::HashMap;

#[derive(Deserialize)]
pub struct LookupMap {
    /// Map from human readable name to a minecraft internal name.
    pub map: HashMap<String, String>,
}
