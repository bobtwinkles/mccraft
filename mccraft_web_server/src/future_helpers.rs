use failure;
use futures::{Async, Future, Poll};

#[must_use = "futures do nothing unless polled"]
pub struct ErasedError<F>(F);

impl<E, F> Future for ErasedError<F>
where
    E: Into<failure::Error>,
    F: Future<Error = E>,
{
    type Item = F::Item;
    type Error = failure::Error;

    fn poll(&mut self) -> Poll<F::Item, failure::Error> {
        let e = match self.0.poll() {
            Ok(Async::NotReady) => return Ok(Async::NotReady),
            other => other,
        };
        e.map_err(Into::into)
    }
}

pub struct LiftResult<F>(F);

impl<E1, E2, I, F> Future for LiftResult<F>
where
    E1: Into<failure::Error>, //'static + std::error::Error + Send + Sync,
    E2: Into<failure::Error>, //'static + std::error::Error + Send + Sync,
    F: Future<Item = Result<I, E1>, Error = E2>,
{
    type Item = I;
    type Error = failure::Error;

    fn poll(&mut self) -> Poll<I, failure::Error> {
        match self.0.poll() {
            Ok(Async::NotReady) => Ok(Async::NotReady),
            Ok(Async::Ready(v)) => match v {
                Ok(v) => Ok(Async::Ready(v)),
                Err(e) => Err(e.into()),
            },
            Err(e) => Err(e.into()),
        }
    }
}

pub trait FutureExt<I, E> {
    /// Erases the error type (equivalent to `f.map_err(failure::Error::from)`)
    fn erase_error(self) -> ErasedError<Self>
    where
        Self: Sized;

    /// "Flattens" a future that returns a result. That is, given a future
    /// `Future<Item=Result<I, E1>, error=E2`, you get a future `future<Item=I,
    /// failure::Error>`
    fn lift_result(self) -> LiftResult<Self>
    where
        Self: Sized;
}

impl<I, E, T: Future<Item = I, Error = E>> FutureExt<I, E> for T {
    fn erase_error(self) -> ErasedError<Self> {
        ErasedError(self)
    }

    fn lift_result(self) -> LiftResult<Self> {
        LiftResult(self)
    }
}
