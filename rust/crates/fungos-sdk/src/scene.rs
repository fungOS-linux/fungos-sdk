//! Canvas scene primitives shared by hosts and tests.
//!
//! Coordinates are Canvas-normalized (`-4..4`), not logical pixels. A UI view
//! works in pixels and the host/scene adapter converts. This crate only models
//! the wire shape.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rect {
    pub id: String,
    pub ink: String,
    pub opacity: f32,
    pub radius: f32,
    pub translation: [f32; 3],
    pub scale: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Text {
    pub id: String,
    pub text: String,
    pub ink: String,
    pub translation: [f32; 3],
    pub scale: [f32; 3],
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Scene {
    #[serde(default)]
    pub rects: Vec<Rect>,
    #[serde(default)]
    pub texts: Vec<Text>,
}

impl Scene {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push_rect(&mut self, rect: Rect) {
        self.rects.push(rect);
    }

    pub fn push_text(&mut self, text: Text) {
        self.texts.push(text);
    }

    pub fn validate(&self) -> Result<(), String> {
        for rect in &self.rects {
            if rect.id.trim().is_empty() {
                return Err("rect id must not be empty".into());
            }
            if !rect.opacity.is_finite()
                || !rect.radius.is_finite()
                || rect.translation.iter().any(|v| !v.is_finite())
                || rect.scale.iter().any(|v| !v.is_finite())
            {
                return Err(format!("rect {:?} has a non-finite value", rect.id));
            }
        }
        for text in &self.texts {
            if text.id.trim().is_empty() {
                return Err("text id must not be empty".into());
            }
            if text.translation.iter().any(|v| !v.is_finite())
                || text.scale.iter().any(|v| !v.is_finite())
            {
                return Err(format!("text {:?} has a non-finite value", text.id));
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scene_round_trips() {
        let mut scene = Scene::new();
        scene.push_rect(Rect {
            id: "bg".into(),
            ink: "background".into(),
            opacity: 1.0,
            radius: 0.0,
            translation: [-4.0, 4.0, -1.0],
            scale: [8.0, 8.0, 1.0],
        });
        scene.push_text(Text {
            id: "t1".into(),
            text: "hello".into(),
            ink: "text".into(),
            translation: [0.0, 0.0, 0.1],
            scale: [1.0, 1.0, 1.0],
        });
        scene.validate().unwrap();
        let json = serde_json::to_string(&scene).unwrap();
        let back: Scene = serde_json::from_str(&json).unwrap();
        assert_eq!(scene, back);
    }

    #[test]
    fn non_finite_geometry_is_rejected() {
        let mut scene = Scene::new();
        scene.push_rect(Rect {
            id: "bad".into(),
            ink: "surface".into(),
            opacity: f32::NAN,
            radius: 0.0,
            translation: [0.0, 0.0, 0.0],
            scale: [1.0, 1.0, 1.0],
        });
        assert!(scene.validate().is_err());
    }
}
