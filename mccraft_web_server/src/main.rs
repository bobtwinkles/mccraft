extern crate actix;
extern crate actix_web;
extern crate diesel;
extern crate dotenv;
extern crate env_logger;
extern crate failure;
extern crate futures;
extern crate fxhash;
#[macro_use]
extern crate log;
extern crate mccraft_core;

use actix::prelude::*;
use actix_web::{server, App, AsyncResponder, FutureResponse, HttpRequest, HttpResponse};
use failure::Error;
use futures::{future, Future};

pub mod db;

struct AppState {
    db: Addr<db::DbExecutor>,
}

fn index(req: &HttpRequest<AppState>) -> FutureResponse<HttpResponse> {
    let dbref = req.state().db.clone();
    dbref.send(db::searches::SearchOutputs::ByName("Diamond".to_owned()))
        .map_err(Error::from)
        .and_then(future::result)
        .map_err(Error::from)
        .and_then(move |recipes| {
            dbref.send(db::searches::RetrieveRecipe {
                partial: recipes[0].clone(),
            }).and_then(future::result).map_err(Error::from)
        })
        .and_then(|r| match r {
            Ok(o) => future::ok(o),
            Err(e) => future::err(Error::from(e))
        })
        .from_err()
        .and_then(|res| {
            Ok(HttpResponse::Ok().json(res))
        }).responder()
}

fn main() {
    dotenv::dotenv().ok();
    let env = env_logger::Env::default().filter_or(env_logger::DEFAULT_FILTER_ENV, "info");
    env_logger::Builder::from_env(env).init();

    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    info!("Connecting to database {}", database_url);

    let sys = actix::System::new("mccraft-web-server");

    let db_addr = actix::SyncArbiter::start(3, move || {
        db::DbExecutor::new(&database_url).expect(&format!("error connecting to {}", database_url))
    });

    server::new(move || {
        let app_state = AppState {
            db: db_addr.clone(),
        };
        App::with_state(app_state).resource("/", |r| r.f(index))
    }).bind("127.0.0.1:8080")
    .expect("Failed to create HTTP server")
    .start();

    sys.run();
}
