//! Shared scene, action, and profile types for fungOS Spores.
//!
//! This crate is intentionally small. It defines the contracts that Lua UI,
//! Canvas, Spores, and Unibus exchange. It does not own layout, policy, or
//! rendering.
//!
//! - [`scene`] mirrors the Canvas scene primitives.
//! - [`dashboard`] is the portable dashboard, frame, query and field contract.
//! - [`action`] mirrors UI action intents and the Unibus action envelope.
//! - [`profile`] mirrors the user/app UI profile.

pub mod action;
pub mod dashboard;
pub mod grafana;
pub mod profile;
pub mod prometheus;
pub mod scene;

pub use action::{
    ActionIntent, ActionInvoke, ActionResult, ACTION_INVOKE_KIND, ACTION_RESULT_KIND,
};
pub use dashboard::{
    AnnotationQuery, Dashboard, DataFrame, DatasourceRef, Field, FieldConfig, FieldOverride,
    FieldType, FieldValues, Panel, PanelKind, PanelRect, Query, TimeBound, TimeRange,
    TransformSpec, Variable,
};
pub use grafana::{import_dashboard, ImportWarning, ImportedDashboard};
pub use profile::Profile;
pub use prometheus::{QueryRequest, QueryResult, QUERY_REQUEST_KIND, QUERY_RESULT_KIND};
pub use scene::{Rect, Scene, Text};
