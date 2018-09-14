use actix_web::actix::*;
use diesel::{Connection, ConnectionError, PgConnection};

pub mod searches;

type DbConn = PgConnection;

pub struct DbExecutor(DbConn);

impl DbExecutor {
    pub fn new(connection_string: &str) -> Result<Self, ConnectionError> {
        Ok(DbExecutor(
            PgConnection::establish(connection_string)?
        ))
    }
}

impl Actor for DbExecutor {
    type Context = SyncContext<Self>;
}
