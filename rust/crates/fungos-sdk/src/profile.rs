//! User/app UI profile.
//!
//! Profiles are data, not authority. A host may load them from a dotfile, a
//! Settings Spore, or a rice package. Unknown keys are rejected so a typo does
//! not silently do nothing.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Profile {
    #[serde(default = "default_schema")]
    pub schema_version: u32,
    #[serde(default)]
    pub density: Option<String>,
    #[serde(default)]
    pub spacing: BTreeMap<String, f32>,
    #[serde(default)]
    pub theme: BTreeMap<String, Value>,
    #[serde(default)]
    pub radius: Option<f32>,
    #[serde(default)]
    pub surfaces: BTreeMap<String, f32>,
    #[serde(default)]
    pub apps: BTreeMap<String, Value>,
}

const fn default_schema() -> u32 {
    1
}

impl Default for Profile {
    fn default() -> Self {
        Self {
            schema_version: 1,
            density: Some("comfortable".into()),
            spacing: BTreeMap::new(),
            theme: BTreeMap::new(),
            radius: None,
            surfaces: BTreeMap::new(),
            apps: BTreeMap::new(),
        }
    }
}

impl Profile {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != 1 {
            return Err(format!(
                "unsupported profile schema_version {}",
                self.schema_version
            ));
        }
        if let Some(density) = &self.density {
            if !matches!(density.as_str(), "compact" | "comfortable" | "spacious") {
                return Err(format!("invalid density {density:?}"));
            }
        }
        for (name, value) in &self.spacing {
            if !value.is_finite() || *value < 0.0 {
                return Err(format!("spacing {name:?} must be finite and non-negative"));
            }
        }
        if let Some(radius) = self.radius {
            if !radius.is_finite() || radius < 0.0 {
                return Err("radius must be finite and non-negative".into());
            }
        }
        for (name, value) in &self.surfaces {
            if !value.is_finite() {
                return Err(format!("surface {name:?} must be finite"));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_profile_is_valid() {
        Profile::default().validate().unwrap();
    }

    #[test]
    fn unknown_keys_are_rejected() {
        let error = serde_json::from_value::<Profile>(serde_json::json!({
            "density": "compact",
            "colour": "mauve"
        }))
        .unwrap_err();
        assert!(error.to_string().contains("unknown field"));
    }

    #[test]
    fn bad_density_is_rejected() {
        let profile = Profile {
            density: Some("tiny".into()),
            ..Profile::default()
        };
        assert!(profile.validate().is_err());
    }
}
