//! Shared scene, action, and profile types for fungOS Spores.
//!
//! This crate is intentionally small. It defines the contracts that Lua UI,
//! Canvas, Spores, and Unibus exchange. It does not own layout, policy, or
//! rendering.
//!
//! - [`scene`] mirrors the Canvas scene primitives.
//! - [`action`] mirrors UI action intents and the Unibus action envelope.
//! - [`profile`] mirrors the user/app UI profile.

pub mod action;
pub mod profile;
pub mod scene;

pub use action::{ActionIntent, ActionInvoke, ActionResult, ACTION_INVOKE_KIND, ACTION_RESULT_KIND};
pub use profile::Profile;
pub use scene::{Rect, Scene, Text};
