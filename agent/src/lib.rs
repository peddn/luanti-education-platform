//! Agent of the Luanti Education Platform. It runs on the game server,
//! calls the backend and tells it how the game server is doing.
//!
//! The agent only ever calls the backend, never the other way round, and
//! it runs no command that comes from outside.

pub mod backend;
pub mod config;
pub mod jobs;
pub mod report;
pub mod service;
pub mod template;
pub mod units;
pub mod worlds;
