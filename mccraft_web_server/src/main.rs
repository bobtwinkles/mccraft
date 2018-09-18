extern crate actix;
extern crate actix_web;
extern crate clap;
extern crate diesel;
extern crate dotenv;
extern crate env_logger;
extern crate failure;
extern crate futures;
extern crate fxhash;
#[macro_use]
extern crate log;
extern crate mccraft_core;
extern crate serde;
#[macro_use]
extern crate serde_derive;

pub mod db;
// pub mod future_helpers;

use actix::prelude::*;
use actix_web::{
    http, server, App, AsyncResponder, FromRequest, HttpRequest, HttpResponse, Path, Query,
    Responder,
};
use futures::Future;
use std::fmt;
use std::path::PathBuf;

struct AppState {
    db: Addr<db::DbExecutor>,
}

fn json_response<T: serde::Serialize, E: fmt::Debug>(
    v: Result<T, E>,
) -> Result<HttpResponse, actix_web::Error> {
    match v {
        Ok(v) => Ok(HttpResponse::Ok().json(v)),
        Err(e) => {
            Ok(HttpResponse::InternalServerError().body(format!("Internal server error: {:?}", e)))
        }
    }
}

fn index(_req: &HttpRequest<AppState>) -> impl Responder {
    return HttpResponse::Ok().body(include_str!("../html/index.html"));
}

fn recipes_for_item(req: &HttpRequest<AppState>) -> impl Responder {
    let dbref = req.state().db.clone();
    futures::future::result(Path::<i32>::extract(req))
        .and_then(move |path| {
            dbref
                .send(db::searches::SearchOutputs::ById(path.into_inner()))
                .from_err()
        }).and_then(json_response)
        .responder()
}

fn item_info(req: &HttpRequest<AppState>) -> impl Responder {
    let dbref = req.state().db.clone();
    futures::future::result(Path::<i32>::extract(req))
        .and_then(move |path| dbref.send(db::about::Item(path.into_inner())).from_err())
        .and_then(json_response)
        .responder()
}

fn complete_recipe(req: &HttpRequest<AppState>) -> impl Responder {
    let dbref = req.state().db.clone();
    futures::future::result(Path::<i32>::extract(req))
        .and_then(move |path| dbref.send(db::about::Recipe(path.into_inner())).from_err())
        .and_then(json_response)
        .responder()
}

#[derive(Deserialize)]
pub struct SearchRequest {
    q: String,
    offset: Option<i64>,
    limit: Option<i64>,
}

fn search_for_item(req: &HttpRequest<AppState>) -> impl Responder {
    let dbref = req.state().db.clone();
    futures::future::result(Query::<SearchRequest>::extract(req))
        .and_then(move |query| {
            let query = query.into_inner();
            dbref
                .send(db::searches::SearchItems {
                    name: query.q,
                    offset: query.offset.unwrap_or(0),
                    limit: query.limit.unwrap_or(10),
                }).from_err()
        }).and_then(json_response)
        .responder()
}

fn setup_env() {
    dotenv::dotenv().ok();
    let env = env_logger::Env::default().filter_or(env_logger::DEFAULT_FILTER_ENV, "info");
    env_logger::Builder::from_env(env).init();
}

fn create_db_connection() -> actix::Addr<db::DbExecutor> {
    let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
    info!("Connecting to database {}", database_url);

    actix::SyncArbiter::start(3, move || {
        db::DbExecutor::new(&database_url).expect(&format!("error connecting to {}", database_url))
    })
}

struct ServerConfiguration {
    db_addr: actix::Addr<db::DbExecutor>,
    static_path: Option<PathBuf>,
    images_path: Option<PathBuf>,
}

fn start_server(listen_addr: &str, server_configuration: ServerConfiguration) {
    server::new(move || {
        let app_state = AppState {
            db: server_configuration.db_addr.clone(),
        };

        let mut app = App::with_state(app_state)
            .middleware(actix_web::middleware::Logger::default())
            .resource("/", |r| r.f(index))
            .resource("/producers/{id}.json", |r| {
                r.method(http::Method::GET).f(recipes_for_item)
            }).resource("/items/{id}.json", |r| {
                r.method(http::Method::GET).f(item_info)
            }).resource("/recipe/{id}.json", |r| {
                r.method(http::Method::GET).f(complete_recipe)
            }).resource("/search.json", |r| {
                r.method(http::Method::GET).f(search_for_item)
            });

        if let Some(ref static_path) = server_configuration.static_path {
            info!("Will serve static resources from {:?}", &static_path);
            app = app.handler(
                "/static",
                actix_web::fs::StaticFiles::new(static_path)
                    .expect(&format!(
                        "Expected to find static files to serve at {:?}",
                        &static_path
                    )).show_files_listing(),
            );
        }

        if let Some(ref images_path) = server_configuration.images_path {
            info!("Will serve images from {:?}", &images_path);
            app = app.handler(
                "/images",
                actix_web::fs::StaticFiles::new(images_path).expect(&format!(
                    "Expected to find image files to serve at {:?}",
                    &images_path
                )),
            );
        }

        app
    }).bind(&listen_addr)
    .expect(&format!(
        "Failed to bind HTTP server to address {}",
        &listen_addr
    )).run()
}

struct ArgsOutput {
    bind_address: String,
    static_path: Option<PathBuf>,
    images_path: Option<PathBuf>,
}

fn app_args() -> ArgsOutput {
    use clap::{App, Arg};

    let matches = App::new("mccraft_web_server")
        .author("Reed Koser")
        .about("Backend web server for the mccraft project")
        .arg(
            Arg::with_name("bind-address")
                .long("bind-address")
                .value_name("BIND_ADDR")
                .default_value("127.0.0.1:8080"),
        ).arg(
            Arg::with_name("static-path")
                .long("static-path")
                .takes_value(true)
                .help("Path to mccraft_frontend/dist"),
        ).arg(
            Arg::with_name("image-path")
                .long("image-path")
                .takes_value(true)
                .help("Path to jeiexporter output path"),
        ).get_matches();

    let static_path = matches
        .value_of("static-path")
        .map(|x| PathBuf::from(x.to_string()));
    let images_path = matches
        .value_of("image-path")
        .map(|x| PathBuf::from(x.to_string()));

    ArgsOutput {
        bind_address: matches.value_of("bind-address").unwrap().to_string(),
        static_path: static_path,
        images_path: images_path,
    }
}

fn main() {
    setup_env();

    let args = app_args();

    // the Actix system needs to be started before we run any of the actors.
    let sys = actix::System::new("mccraft-web-server");

    let db_addr = create_db_connection();

    start_server(
        &args.bind_address,
        ServerConfiguration {
            db_addr,
            static_path: args.static_path,
            images_path: args.images_path,
        },
    );

    sys.run();
}
