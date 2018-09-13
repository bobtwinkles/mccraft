use std::collections::HashMap;

#[derive(Deserialize)]
pub struct TooltipMap {
    /// Map from minecraft internal name to a human readable one.
    pub map: HashMap<String, String>,
}
