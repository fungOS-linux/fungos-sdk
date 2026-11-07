//! Prometheus-over-Unibus query contract.
//!
//! A Spore does not hold a Prometheus URL or token. It publishes a query request
//! on the bus, addressed to a configured Prometheus adapter, and observes the
//! matching result frames. The adapter owns HTTP, TLS, credentials and the
//! datasource mapping.

use serde::{Deserialize, Serialize};

use crate::dashboard::{DataFrame, DatasourceRef};

pub const QUERY_REQUEST_KIND: &str = "prometheus.query.request.v1";
pub const QUERY_RESULT_KIND: &str = "prometheus.query.result.v1";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct QueryRequest {
    /// Caller-generated, unique for the lifetime of the request.
    pub request_id: String,
    /// Adapter-local datasource identity, never a URL or token.
    pub datasource: DatasourceRef,
    /// Stable panel identity in the caller's dashboard.
    pub panel_id: String,
    /// Grafana-style query reference (`A`, `B`, ...).
    pub ref_id: String,
    pub expression: String,
    pub start_ms: i64,
    pub end_ms: i64,
    pub step_ms: u64,
    #[serde(default = "default_max_points")]
    pub max_points: u32,
    /// Ask for an instant query instead of a range query.
    #[serde(default)]
    pub instant: bool,
}

const fn default_max_points() -> u32 {
    2_000
}

impl QueryRequest {
    pub fn validate(&self) -> Result<(), String> {
        if self.request_id.trim().is_empty()
            || self.panel_id.trim().is_empty()
            || self.ref_id.trim().is_empty()
            || self.expression.trim().is_empty()
        {
            return Err("request id, panel, ref and expression must not be empty".into());
        }
        if self.datasource.uid.trim().is_empty() || self.datasource.kind.trim().is_empty() {
            return Err("datasource uid and kind must not be empty".into());
        }
        if self.start_ms >= self.end_ms {
            return Err("query start must be before end".into());
        }
        if self.step_ms == 0 {
            return Err("query step must be positive".into());
        }
        if self.max_points == 0 {
            return Err("query max_points must be positive".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct QueryResult {
    pub request_id: String,
    #[serde(default)]
    pub frames: Vec<DataFrame>,
    /// A non-empty error means no frames are trustworthy. The caller must show
    /// the failure rather than an empty success.
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub elapsed_ms: Option<u64>,
}

impl QueryResult {
    pub fn validate(&self) -> Result<(), String> {
        if self.request_id.trim().is_empty() {
            return Err("result request_id must not be empty".into());
        }
        if let Some(error) = &self.error {
            if error.trim().is_empty() {
                return Err("result error must not be empty when present".into());
            }
            if !self.frames.is_empty() {
                return Err("an error result must not carry frames".into());
            }
            return Ok(());
        }
        if self.frames.is_empty() {
            return Err("a successful result must carry at least one frame".into());
        }
        for frame in &self.frames {
            frame.validate()?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::dashboard::{Field, FieldType, FieldValues, FrameMeta};
    use std::collections::BTreeMap;

    fn request() -> QueryRequest {
        QueryRequest {
            request_id: "req-1".into(),
            datasource: DatasourceRef {
                uid: "prom".into(),
                kind: "prometheus".into(),
            },
            panel_id: "latency".into(),
            ref_id: "A".into(),
            expression: "up{job=\"fleet\"}".into(),
            start_ms: 1_700_000_000_000,
            end_ms: 1_700_000_360_000,
            step_ms: 15_000,
            max_points: 2_000,
            instant: false,
        }
    }

    #[test]
    fn request_round_trips_and_validates() {
        let request = request();
        request.validate().unwrap();
        let json = serde_json::to_string(&request).unwrap();
        assert_eq!(
            serde_json::from_str::<QueryRequest>(&json).unwrap(),
            request
        );

        let mut bad = request;
        bad.end_ms = bad.start_ms;
        assert!(bad.validate().is_err());
    }

    #[test]
    fn result_round_trips_and_requires_frames_or_error() {
        let result = QueryResult {
            request_id: "req-1".into(),
            frames: vec![DataFrame {
                name: "up".into(),
                ref_id: "A".into(),
                fields: vec![Field {
                    name: "value".into(),
                    field_type: FieldType::Number,
                    labels: BTreeMap::new(),
                    unit: None,
                    values: FieldValues::Number(vec![Some(1.0)]),
                }],
                meta: FrameMeta::default(),
            }],
            error: None,
            elapsed_ms: Some(12),
        };
        result.validate().unwrap();
        let json = serde_json::to_string(&result).unwrap();
        assert_eq!(serde_json::from_str::<QueryResult>(&json).unwrap(), result);

        let mut bad = result;
        bad.frames.clear();
        assert!(bad.validate().is_err());

        let error = QueryResult {
            request_id: "req-1".into(),
            frames: Vec::new(),
            error: Some("adapter unavailable".into()),
            elapsed_ms: None,
        };
        error.validate().unwrap();
    }
}
