#![allow(proc_macro_derive_resolution_fallback)]

#[macro_use] extern crate serde_derive;
extern crate serde;
#[macro_use] extern crate diesel;
#[macro_use] extern crate diesel_derive_enum;

/// The JSON schema for representing recipes
pub mod json;
/// The SQL schema for representing recipes
#[allow(unused_imports)]
pub mod schema;

/// The SQL model.
pub mod sql;

pub mod web;
