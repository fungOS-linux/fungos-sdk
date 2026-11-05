//! Action intents and Unibus action envelopes.

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// A UI-emitted intent. This is not authority: the host stamps the caller and
/// routes it through the Spore/Unibus action router.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionIntent {
    pub action: String,
    #[serde(default)]
    pub payload: Value,
}

impl ActionIntent {
    pub fn new(action: impl Into<String>, payload: Value) -> Self {
        Self {
            action: action.into(),
            payload,
        }
    }

    /// The shape the UI is allowed to emit.
    pub fn validate(&self) -> Result<(), String> {
        if self.action.trim().is_empty() {
            return Err("action id must not be empty".into());
        }
        if !self.action.chars().all(|c| {
            c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_' | '/')
        }) {
            return Err(format!("invalid action id {:?}", self.action));
        }
        if !self.payload.is_object() && !self.payload.is_null() {
            return Err("action payload must be an object or null".into());
        }
        Ok(())
    }
}

pub const ACTION_INVOKE_KIND: &str = "unibus.action.invoke.v1";
pub const ACTION_RESULT_KIND: &str = "unibus.action.result.v1";

/// The host/Unibus envelope. The caller fields are stamped by the host, never
/// trusted from UI Lua.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionInvoke {
    pub kind: String,
    pub action: String,
    pub spore: String,
    #[serde(default)]
    pub input: Value,
    pub actor: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub idempotency_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_revision: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub approval: Option<Value>,
}

impl ActionInvoke {
    pub fn new(
        action: impl Into<String>,
        spore: impl Into<String>,
        actor: impl Into<String>,
    ) -> Self {
        Self {
            kind: ACTION_INVOKE_KIND.into(),
            action: action.into(),
            spore: spore.into(),
            input: Value::Null,
            actor: actor.into(),
            idempotency_key: None,
            expected_revision: None,
            approval: None,
        }
    }

    pub fn with_input(mut self, input: Value) -> Self {
        self.input = input;
        self
    }

    pub fn validate(&self) -> Result<(), String> {
        if self.kind != ACTION_INVOKE_KIND {
            return Err(format!("unexpected kind {:?}", self.kind));
        }
        if self.action.trim().is_empty() || self.spore.trim().is_empty() {
            return Err("action and spore must not be empty".into());
        }
        if self.actor.trim().is_empty() {
            return Err("actor must be stamped by the host".into());
        }
        if !self.input.is_object() && !self.input.is_null() {
            return Err("input must be an object or null".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionResult {
    pub kind: String,
    pub action: String,
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub change: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl ActionResult {
    pub fn ok(action: impl Into<String>, revision: Option<u64>) -> Self {
        Self {
            kind: ACTION_RESULT_KIND.into(),
            action: action.into(),
            status: "ok".into(),
            revision,
            change: None,
            error: None,
        }
    }

    pub fn error(action: impl Into<String>, error: impl Into<String>) -> Self {
        Self {
            kind: ACTION_RESULT_KIND.into(),
            action: action.into(),
            status: "error".into(),
            revision: None,
            change: None,
            error: Some(error.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn intent_serializes_with_the_lua_shape() {
        let intent = ActionIntent::new(
            "mail.archive",
            serde_json::json!({ "thread_id": "support/refund-441" }),
        );
        intent.validate().unwrap();
        assert_eq!(
            serde_json::to_value(&intent).unwrap(),
            serde_json::json!({
                "action": "mail.archive",
                "payload": { "thread_id": "support/refund-441" }
            })
        );
    }

    #[test]
    fn empty_action_is_rejected() {
        let intent = ActionIntent::new("", serde_json::json!({}));
        assert!(intent.validate().is_err());
    }

    #[test]
    fn invoke_requires_host_stamped_actor() {
        let invoke = ActionInvoke::new("mail.archive", "dev.fungos.unibus", "")
            .with_input(serde_json::json!({ "thread_id": "x" }));
        assert!(invoke.validate().is_err());

        let invoke = ActionInvoke::new("mail.archive", "dev.fungos.unibus", "human:avery")
            .with_input(serde_json::json!({ "thread_id": "x" }));
        invoke.validate().unwrap();
        assert_eq!(invoke.kind, ACTION_INVOKE_KIND);
    }
}
