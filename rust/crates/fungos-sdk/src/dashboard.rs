//! Portable dashboard and data-frame contract.
//!
//! This is the shared shape between a dashboard importer, a data-source adapter,
//! Lua UI, and a renderer. It is intentionally independent of Grafana: Grafana
//! JSON is an adapter input, not the model the renderer consumes.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;

pub const DASHBOARD_SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Dashboard {
    #[serde(default = "schema_version")]
    pub schema_version: u32,
    pub uid: String,
    pub title: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub time: TimeRange,
    #[serde(default)]
    pub refresh: Option<Refresh>,
    #[serde(default)]
    pub timezone: Option<String>,
    #[serde(default)]
    pub variables: Vec<Variable>,
    #[serde(default)]
    pub panels: Vec<Panel>,
    #[serde(default)]
    pub annotations: Vec<AnnotationQuery>,
    #[serde(default)]
    pub links: Vec<DashboardLink>,
}

const fn schema_version() -> u32 {
    DASHBOARD_SCHEMA_VERSION
}

impl Dashboard {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != DASHBOARD_SCHEMA_VERSION {
            return Err(format!(
                "unsupported dashboard schema_version {}",
                self.schema_version
            ));
        }
        if self.uid.trim().is_empty() || self.title.trim().is_empty() {
            return Err("dashboard uid and title must not be empty".into());
        }
        self.time.validate()?;
        if let Some(refresh) = &self.refresh {
            refresh.validate()?;
        }

        let mut panel_ids = std::collections::BTreeSet::new();
        for panel in &self.panels {
            if !panel_ids.insert(panel.id.as_str()) {
                return Err(format!("duplicate panel id {:?}", panel.id));
            }
            panel.validate()?;
        }

        let mut variable_names = std::collections::BTreeSet::new();
        for variable in &self.variables {
            if !variable_names.insert(variable.name.as_str()) {
                return Err(format!("duplicate variable {:?}", variable.name));
            }
            variable.validate()?;
        }

        for annotation in &self.annotations {
            annotation.validate()?;
        }
        for link in &self.links {
            link.validate()?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Refresh {
    pub interval_ms: u64,
    #[serde(default)]
    pub pause_on_hover: bool,
}

impl Refresh {
    fn validate(&self) -> Result<(), String> {
        if self.interval_ms == 0 {
            return Err("refresh interval must be positive".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TimeRange {
    pub from: TimeBound,
    pub to: TimeBound,
}

impl TimeRange {
    fn validate(&self) -> Result<(), String> {
        self.from.validate()?;
        self.to.validate()?;
        if let TimeBound::Absolute { unix_ms: from } = &self.from {
            if let TimeBound::Absolute { unix_ms: to } = &self.to {
                if from > to {
                    return Err("time range starts after it ends".into());
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum TimeBound {
    /// A dashboard expression such as `now-6h` or `now`.
    Relative { expression: String },
    /// Unix epoch milliseconds.
    Absolute { unix_ms: i64 },
}

impl TimeBound {
    fn validate(&self) -> Result<(), String> {
        if let Self::Relative { expression } = self {
            if expression.trim().is_empty() {
                return Err("relative time expression must not be empty".into());
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Panel {
    pub id: String,
    pub title: String,
    pub kind: PanelKind,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub rect: PanelRect,
    #[serde(default)]
    pub queries: Vec<Query>,
    #[serde(default)]
    pub transforms: Vec<TransformSpec>,
    #[serde(default)]
    pub field: FieldConfig,
    #[serde(default)]
    pub overrides: Vec<FieldOverride>,
    #[serde(default)]
    pub options: PanelOptions,
    #[serde(default)]
    pub links: Vec<DataLink>,
    /// Variable name that repeats this panel.
    #[serde(default)]
    pub repeat: Option<String>,
}

impl Panel {
    fn validate(&self) -> Result<(), String> {
        if self.id.trim().is_empty() || self.title.trim().is_empty() {
            return Err("panel id and title must not be empty".into());
        }
        self.kind.validate()?;
        self.rect.validate()?;
        let mut ref_ids = std::collections::BTreeSet::new();
        for query in &self.queries {
            if !ref_ids.insert(query.ref_id.as_str()) {
                return Err(format!(
                    "panel {:?} has duplicate query ref_id {:?}",
                    self.id, query.ref_id
                ));
            }
            query.validate()?;
        }
        for transform in &self.transforms {
            transform.validate()?;
        }
        self.field.validate()?;
        for override_ in &self.overrides {
            override_.validate()?;
        }
        self.options.validate()?;
        for link in &self.links {
            link.validate()?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PanelKind {
    #[default]
    TimeSeries,
    Stat,
    Gauge,
    BarGauge,
    Table,
    Heatmap,
    StatusHistory,
    Logs,
    Text,
    Histogram,
    NodeGraph,
    Geomap,
    Custom {
        kind: String,
    },
}

impl PanelKind {
    fn validate(&self) -> Result<(), String> {
        if let Self::Custom { kind } = self {
            if kind.trim().is_empty() {
                return Err("custom panel kind must not be empty".into());
            }
        }
        Ok(())
    }
}

/// Normalized placement on the dashboard surface.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PanelRect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Default for PanelRect {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 1.0,
            height: 1.0,
        }
    }
}

impl PanelRect {
    fn validate(&self) -> Result<(), String> {
        for value in [self.x, self.y, self.width, self.height] {
            if !value.is_finite() {
                return Err("panel rect must be finite".into());
            }
        }
        if self.x < 0.0
            || self.y < 0.0
            || self.width <= 0.0
            || self.height <= 0.0
            || self.x + self.width > 1.0001
            || self.y + self.height > 1.0001
        {
            return Err("panel rect must fit inside the normalized surface".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Query {
    pub ref_id: String,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub datasource: Option<DatasourceRef>,
    pub expression: String,
    #[serde(default)]
    pub query_type: QueryType,
    #[serde(default)]
    pub time: Option<TimeRange>,
    #[serde(default)]
    pub interval_ms: Option<u64>,
    #[serde(default)]
    pub max_points: Option<u32>,
    #[serde(default)]
    pub legend: Option<String>,
}

impl Query {
    fn validate(&self) -> Result<(), String> {
        if self.ref_id.trim().is_empty() || self.expression.trim().is_empty() {
            return Err("query ref_id and expression must not be empty".into());
        }
        if let Some(datasource) = &self.datasource {
            datasource.validate()?;
        }
        if let Some(time) = &self.time {
            time.validate()?;
        }
        if self.interval_ms == Some(0) {
            return Err("query interval must be positive".into());
        }
        if self.max_points == Some(0) {
            return Err("query max_points must be positive".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QueryType {
    #[default]
    Range,
    Instant,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DatasourceRef {
    pub uid: String,
    pub kind: String,
}

impl DatasourceRef {
    fn validate(&self) -> Result<(), String> {
        if self.uid.trim().is_empty() || self.kind.trim().is_empty() {
            return Err("datasource uid and kind must not be empty".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FieldConfig {
    #[serde(default)]
    pub unit: Option<String>,
    #[serde(default)]
    pub decimals: Option<u8>,
    #[serde(default)]
    pub min: Option<f64>,
    #[serde(default)]
    pub max: Option<f64>,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub no_value: Option<String>,
    #[serde(default)]
    pub thresholds: Option<Thresholds>,
    #[serde(default)]
    pub mappings: Vec<ValueMapping>,
    #[serde(default)]
    pub color: Option<FieldColor>,
    #[serde(default)]
    pub links: Vec<DataLink>,
}

impl Default for FieldConfig {
    fn default() -> Self {
        Self {
            unit: None,
            decimals: None,
            min: None,
            max: None,
            display_name: None,
            no_value: None,
            thresholds: None,
            mappings: Vec::new(),
            color: None,
            links: Vec::new(),
        }
    }
}

impl FieldConfig {
    fn validate(&self) -> Result<(), String> {
        if let (Some(min), Some(max)) = (self.min, self.max) {
            if !min.is_finite() || !max.is_finite() {
                return Err("field min/max must be finite".into());
            }
            if min > max {
                return Err("field min is above max".into());
            }
        }
        if let Some(decimals) = self.decimals {
            if decimals > 10 {
                return Err("field decimals must be 0..=10".into());
            }
        }
        if let Some(thresholds) = &self.thresholds {
            thresholds.validate()?;
        }
        for mapping in &self.mappings {
            mapping.validate()?;
        }
        if let Some(color) = &self.color {
            color.validate()?;
        }
        for link in &self.links {
            link.validate()?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Thresholds {
    #[serde(default)]
    pub mode: ThresholdMode,
    pub steps: Vec<ThresholdStep>,
}

impl Thresholds {
    fn validate(&self) -> Result<(), String> {
        if self.steps.is_empty() {
            return Err("thresholds need at least one step".into());
        }
        let mut last = f64::NEG_INFINITY;
        for step in &self.steps {
            if let Some(value) = step.value {
                if !value.is_finite() {
                    return Err("threshold value must be finite".into());
                }
                if value < last {
                    return Err("threshold steps must be ascending".into());
                }
                last = value;
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ThresholdMode {
    #[default]
    Absolute,
    Percentage,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ThresholdStep {
    /// `None` is the base step.
    #[serde(default)]
    pub value: Option<f64>,
    pub color: Rgb,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Rgb(pub [u8; 3]);

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum ValueMapping {
    Value {
        value: String,
        #[serde(default)]
        text: Option<String>,
        #[serde(default)]
        color: Option<Rgb>,
    },
    Range {
        from: f64,
        to: f64,
        #[serde(default)]
        text: Option<String>,
        #[serde(default)]
        color: Option<Rgb>,
    },
    Regex {
        pattern: String,
        #[serde(default)]
        text: Option<String>,
        #[serde(default)]
        color: Option<Rgb>,
    },
    Special {
        key: String,
        #[serde(default)]
        text: Option<String>,
        #[serde(default)]
        color: Option<Rgb>,
    },
}

impl ValueMapping {
    fn validate(&self) -> Result<(), String> {
        match self {
            Self::Range { from, to, .. } => {
                if !from.is_finite() || !to.is_finite() || from > to {
                    return Err("mapping range must be finite and ascending".into());
                }
            }
            Self::Regex { pattern, .. } if pattern.trim().is_empty() => {
                return Err("mapping regex must not be empty".into());
            }
            Self::Special { key, .. } if key.trim().is_empty() => {
                return Err("mapping special key must not be empty".into());
            }
            _ => {}
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FieldColor {
    #[serde(default)]
    pub mode: FieldColorMode,
    #[serde(default)]
    pub fixed: Option<Rgb>,
}

impl FieldColor {
    fn validate(&self) -> Result<(), String> {
        if self.mode == FieldColorMode::Fixed && self.fixed.is_none() {
            return Err("fixed field color needs a colour".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FieldColorMode {
    #[default]
    Series,
    Continuous,
    Thresholds,
    Fixed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FieldOverride {
    pub matcher: FieldMatcher,
    pub properties: FieldConfig,
}

impl FieldOverride {
    fn validate(&self) -> Result<(), String> {
        self.matcher.validate()?;
        self.properties.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum FieldMatcher {
    ByName { name: String },
    ByRegex { pattern: String },
    ByQuery { ref_id: String },
}

impl FieldMatcher {
    fn validate(&self) -> Result<(), String> {
        let value = match self {
            Self::ByName { name } => name,
            Self::ByRegex { pattern } => pattern,
            Self::ByQuery { ref_id } => ref_id,
        };
        if value.trim().is_empty() {
            return Err("field matcher value must not be empty".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PanelOptions {
    #[serde(default)]
    pub legend: LegendOptions,
    #[serde(default)]
    pub tooltip: TooltipMode,
    #[serde(default)]
    pub orientation: Orientation,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub reduce: Option<Reduce>,
    #[serde(default)]
    pub color_mode: ColorMode,
    #[serde(default)]
    pub show_values: bool,
}

impl Default for PanelOptions {
    fn default() -> Self {
        Self {
            legend: LegendOptions::default(),
            tooltip: TooltipMode::default(),
            orientation: Orientation::default(),
            text: None,
            reduce: None,
            color_mode: ColorMode::default(),
            show_values: false,
        }
    }
}

impl PanelOptions {
    fn validate(&self) -> Result<(), String> {
        self.legend.validate()?;
        if let Some(text) = &self.text {
            if text.len() > 16 * 1024 {
                return Err("panel text is too large".into());
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LegendOptions {
    #[serde(default = "yes")]
    pub show: bool,
    #[serde(default)]
    pub mode: LegendMode,
    #[serde(default)]
    pub placement: LegendPlacement,
    #[serde(default)]
    pub values: Vec<LegendValue>,
}

impl Default for LegendOptions {
    fn default() -> Self {
        Self {
            show: true,
            mode: LegendMode::default(),
            placement: LegendPlacement::default(),
            values: Vec::new(),
        }
    }
}

impl LegendOptions {
    fn validate(&self) -> Result<(), String> {
        if self.values.len() > 8 {
            return Err("legend has too many value fields".into());
        }
        Ok(())
    }
}

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LegendMode {
    #[default]
    List,
    Table,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LegendPlacement {
    #[default]
    Bottom,
    Right,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LegendValue {
    Last,
    Min,
    Max,
    Mean,
    Sum,
    Count,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TooltipMode {
    #[default]
    Single,
    All,
    Hidden,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Orientation {
    #[default]
    Auto,
    Horizontal,
    Vertical,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Reduce {
    #[default]
    Last,
    First,
    Min,
    Max,
    Mean,
    Sum,
    Count,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ColorMode {
    #[default]
    Palette,
    Value,
    Background,
    Thresholds,
    Fixed,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum TransformSpec {
    Reduce {
        #[serde(default)]
        input: Option<String>,
        reducer: Reduce,
        #[serde(default)]
        mode: TransformMode,
    },
    Filter {
        field: String,
        op: FilterOp,
        value: Value,
    },
    Organize {
        #[serde(default)]
        exclude: Vec<String>,
        #[serde(default)]
        rename: BTreeMap<String, String>,
        #[serde(default)]
        index: Vec<String>,
    },
    Rename {
        from: String,
        to: String,
    },
    Merge {
        #[serde(default)]
        fields: Vec<String>,
    },
    Join {
        by: Vec<String>,
        #[serde(default)]
        mode: JoinMode,
    },
    Calculate {
        field: String,
        expression: String,
    },
    Sort {
        field: String,
        #[serde(default)]
        desc: bool,
    },
    Limit {
        limit: u32,
    },
    LabelsToFields {
        #[serde(default)]
        value_field: Option<String>,
    },
    RowsToFields {
        #[serde(default)]
        mappings: BTreeMap<String, String>,
    },
    SeriesToRows,
}

impl TransformSpec {
    fn validate(&self) -> Result<(), String> {
        match self {
            Self::Reduce { input, .. } => {
                if input.as_deref() == Some("") {
                    return Err("reduce input must not be empty".into());
                }
            }
            Self::Filter { field, .. } if field.trim().is_empty() => {
                return Err("filter field must not be empty".into());
            }
            Self::Rename { from, to } if from.trim().is_empty() || to.trim().is_empty() => {
                return Err("rename fields must not be empty".into());
            }
            Self::Join { by, .. } if by.is_empty() => {
                return Err("join needs at least one field".into());
            }
            Self::Calculate { field, expression }
                if field.trim().is_empty() || expression.trim().is_empty() =>
            {
                return Err("calculate field and expression must not be empty".into());
            }
            Self::Sort { field, .. } if field.trim().is_empty() => {
                return Err("sort field must not be empty".into());
            }
            Self::Limit { limit } if *limit == 0 => {
                return Err("transform limit must be positive".into());
            }
            _ => {}
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransformMode {
    #[default]
    SeriesToRows,
    ReduceFields,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FilterOp {
    Eq,
    Neq,
    Gt,
    Gte,
    Lt,
    Lte,
    Regex,
    Contains,
    In,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum JoinMode {
    #[default]
    Outer,
    Inner,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Variable {
    pub name: String,
    #[serde(default)]
    pub label: Option<String>,
    pub kind: VariableKind,
    #[serde(default)]
    pub query: Option<String>,
    #[serde(default)]
    pub datasource: Option<DatasourceRef>,
    #[serde(default)]
    pub options: Vec<VariableOption>,
    #[serde(default)]
    pub current: Vec<String>,
    #[serde(default)]
    pub multi: bool,
    #[serde(default)]
    pub include_all: bool,
    #[serde(default)]
    pub regex: Option<String>,
    #[serde(default)]
    pub sort: VariableSort,
    #[serde(default)]
    pub refresh: VariableRefresh,
}

impl Variable {
    fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty() {
            return Err("variable name must not be empty".into());
        }
        match self.kind {
            VariableKind::Query => {
                if self.query.as_deref().unwrap_or("").trim().is_empty() {
                    return Err(format!("query variable {:?} needs a query", self.name));
                }
                if self.datasource.is_none() {
                    return Err(format!("query variable {:?} needs a datasource", self.name));
                }
            }
            VariableKind::Custom => {
                if self.options.is_empty() {
                    return Err(format!("custom variable {:?} needs options", self.name));
                }
            }
            VariableKind::Constant => {
                if self.current.len() != 1 || self.current[0].is_empty() {
                    return Err(format!(
                        "constant variable {:?} needs one current value",
                        self.name
                    ));
                }
            }
            _ => {}
        }
        if let Some(datasource) = &self.datasource {
            datasource.validate()?;
        }
        for option in &self.options {
            if option.text.is_empty() {
                return Err(format!("variable {:?} has an empty option", self.name));
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VariableKind {
    Query,
    Custom,
    Constant,
    Datasource,
    Interval,
    Textbox,
    Adhoc,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct VariableOption {
    pub text: String,
    pub value: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VariableSort {
    #[default]
    Disabled,
    AlphabeticalAsc,
    AlphabeticalDesc,
    NumericalAsc,
    NumericalDesc,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VariableRefresh {
    #[default]
    Never,
    OnLoad,
    OnTimeRange,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnnotationQuery {
    pub name: String,
    pub datasource: DatasourceRef,
    pub query: String,
    #[serde(default)]
    pub enable: bool,
    #[serde(default)]
    pub icon_color: Option<Rgb>,
    #[serde(default)]
    pub hide: bool,
}

impl AnnotationQuery {
    fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty() || self.query.trim().is_empty() {
            return Err("annotation name and query must not be empty".into());
        }
        self.datasource.validate()
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DataLink {
    pub title: String,
    pub url: String,
    #[serde(default)]
    pub target_blank: bool,
}

impl DataLink {
    fn validate(&self) -> Result<(), String> {
        if self.title.trim().is_empty() || self.url.trim().is_empty() {
            return Err("link title and url must not be empty".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DashboardLink {
    pub title: String,
    pub url: String,
    #[serde(default)]
    pub kind: DashboardLinkKind,
}

impl DashboardLink {
    fn validate(&self) -> Result<(), String> {
        if self.title.trim().is_empty() || self.url.trim().is_empty() {
            return Err("dashboard link title and url must not be empty".into());
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DashboardLinkKind {
    #[default]
    Link,
    Dashboards,
}

/// One returned data table. Fields share a length; time is Unix milliseconds.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DataFrame {
    pub name: String,
    pub ref_id: String,
    pub fields: Vec<Field>,
    #[serde(default)]
    pub meta: FrameMeta,
}

impl DataFrame {
    pub fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty() || self.ref_id.trim().is_empty() {
            return Err("frame name and ref_id must not be empty".into());
        }
        let Some(first) = self.fields.first() else {
            return Ok(());
        };
        let len = first.values.len();
        let mut names = std::collections::BTreeSet::new();
        for field in &self.fields {
            if !names.insert(field.name.as_str()) {
                return Err(format!("duplicate field {:?}", field.name));
            }
            if field.values.len() != len {
                return Err(format!(
                    "field {:?} has {} values, expected {}",
                    field.name,
                    field.values.len(),
                    len
                ));
            }
            field.validate()?;
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Field {
    pub name: String,
    #[serde(rename = "type")]
    pub field_type: FieldType,
    #[serde(default)]
    pub labels: BTreeMap<String, String>,
    #[serde(default)]
    pub unit: Option<String>,
    pub values: FieldValues,
}

impl Field {
    fn validate(&self) -> Result<(), String> {
        if self.name.trim().is_empty() {
            return Err("field name must not be empty".into());
        }
        let actual = self.values.field_type();
        if actual != self.field_type {
            return Err(format!(
                "field {:?} declares {:?} but carries {:?} values",
                self.name, self.field_type, actual
            ));
        }
        self.values.validate()?;
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FieldType {
    Time,
    Number,
    String,
    Boolean,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "values", rename_all = "snake_case")]
pub enum FieldValues {
    Time(Vec<Option<i64>>),
    Number(Vec<Option<f64>>),
    String(Vec<Option<String>>),
    Boolean(Vec<Option<bool>>),
}

impl FieldValues {
    pub fn len(&self) -> usize {
        match self {
            Self::Time(values) => values.len(),
            Self::Number(values) => values.len(),
            Self::String(values) => values.len(),
            Self::Boolean(values) => values.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    fn field_type(&self) -> FieldType {
        match self {
            Self::Time(_) => FieldType::Time,
            Self::Number(_) => FieldType::Number,
            Self::String(_) => FieldType::String,
            Self::Boolean(_) => FieldType::Boolean,
        }
    }

    fn validate(&self) -> Result<(), String> {
        if let Self::Number(values) = self {
            for value in values.iter().flatten() {
                if !value.is_finite() {
                    return Err("number field contains a non-finite value".into());
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FrameMeta {
    #[serde(default)]
    pub preferred_visualization: Option<PanelKind>,
    #[serde(default)]
    pub executed_query: Option<String>,
    #[serde(default)]
    pub custom: BTreeMap<String, Value>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dashboard() -> Dashboard {
        Dashboard {
            schema_version: DASHBOARD_SCHEMA_VERSION,
            uid: "fleet".into(),
            title: "Fleet".into(),
            description: Some("Fleet health".into()),
            tags: vec!["ops".into()],
            time: TimeRange {
                from: TimeBound::Relative {
                    expression: "now-6h".into(),
                },
                to: TimeBound::Relative {
                    expression: "now".into(),
                },
            },
            refresh: Some(Refresh {
                interval_ms: 5_000,
                pause_on_hover: true,
            }),
            timezone: Some("UTC".into()),
            variables: vec![Variable {
                name: "env".into(),
                label: Some("Environment".into()),
                kind: VariableKind::Custom,
                query: None,
                datasource: None,
                options: vec![
                    VariableOption {
                        text: "prod".into(),
                        value: "prod".into(),
                    },
                    VariableOption {
                        text: "dev".into(),
                        value: "dev".into(),
                    },
                ],
                current: vec!["prod".into()],
                multi: false,
                include_all: false,
                regex: None,
                sort: VariableSort::AlphabeticalAsc,
                refresh: VariableRefresh::Never,
            }],
            panels: vec![Panel {
                id: "latency".into(),
                title: "Latency".into(),
                kind: PanelKind::TimeSeries,
                description: None,
                rect: PanelRect {
                    x: 0.0,
                    y: 0.0,
                    width: 0.5,
                    height: 0.5,
                },
                queries: vec![Query {
                    ref_id: "A".into(),
                    hidden: false,
                    datasource: Some(DatasourceRef {
                        uid: "prom".into(),
                        kind: "prometheus".into(),
                    }),
                    expression: "histogram_quantile(0.95, rate(latency_bucket[$__rate_interval]))"
                        .into(),
                    query_type: QueryType::Range,
                    time: None,
                    interval_ms: Some(15_000),
                    max_points: Some(2_000),
                    legend: Some("p95".into()),
                }],
                transforms: vec![TransformSpec::Reduce {
                    input: Some("A".into()),
                    reducer: Reduce::Mean,
                    mode: TransformMode::ReduceFields,
                }],
                field: FieldConfig {
                    unit: Some("ms".into()),
                    decimals: Some(2),
                    min: Some(0.0),
                    max: None,
                    display_name: Some("p95".into()),
                    no_value: Some("—".into()),
                    thresholds: Some(Thresholds {
                        mode: ThresholdMode::Absolute,
                        steps: vec![
                            ThresholdStep {
                                value: None,
                                color: Rgb([34, 197, 94]),
                            },
                            ThresholdStep {
                                value: Some(250.0),
                                color: Rgb([245, 190, 80]),
                            },
                            ThresholdStep {
                                value: Some(500.0),
                                color: Rgb([239, 68, 68]),
                            },
                        ],
                    }),
                    mappings: vec![ValueMapping::Value {
                        value: "0".into(),
                        text: Some("none".into()),
                        color: None,
                    }],
                    color: Some(FieldColor {
                        mode: FieldColorMode::Thresholds,
                        fixed: None,
                    }),
                    links: vec![DataLink {
                        title: "Trace".into(),
                        url: "/traces?time=$__from".into(),
                        target_blank: true,
                    }],
                },
                overrides: vec![FieldOverride {
                    matcher: FieldMatcher::ByRegex {
                        pattern: "^p99".into(),
                    },
                    properties: FieldConfig {
                        color: Some(FieldColor {
                            mode: FieldColorMode::Fixed,
                            fixed: Some(Rgb([239, 68, 68])),
                        }),
                        ..FieldConfig::default()
                    },
                }],
                options: PanelOptions {
                    legend: LegendOptions {
                        show: true,
                        mode: LegendMode::List,
                        placement: LegendPlacement::Bottom,
                        values: vec![LegendValue::Last, LegendValue::Mean],
                    },
                    tooltip: TooltipMode::All,
                    orientation: Orientation::Auto,
                    text: None,
                    reduce: Some(Reduce::Last),
                    color_mode: ColorMode::Thresholds,
                    show_values: false,
                },
                links: Vec::new(),
                repeat: None,
            }],
            annotations: vec![AnnotationQuery {
                name: "deploys".into(),
                datasource: DatasourceRef {
                    uid: "loki".into(),
                    kind: "loki".into(),
                },
                query: "{job=\"deploy\"}".into(),
                enable: true,
                icon_color: Some(Rgb([96, 165, 250])),
                hide: false,
            }],
            links: vec![DashboardLink {
                title: "Runbooks".into(),
                url: "/d/runbooks".into(),
                kind: DashboardLinkKind::Dashboards,
            }],
        }
    }

    #[test]
    fn dashboard_round_trips() {
        let dashboard = dashboard();
        dashboard.validate().unwrap();
        let json = serde_json::to_string_pretty(&dashboard).unwrap();
        let back: Dashboard = serde_json::from_str(&json).unwrap();
        assert_eq!(dashboard, back);
    }

    #[test]
    fn duplicate_panel_ids_are_rejected() {
        let mut dashboard = dashboard();
        let mut panel = dashboard.panels[0].clone();
        panel.id = "latency".into();
        dashboard.panels.push(panel);
        assert!(dashboard.validate().is_err());
    }

    #[test]
    fn descending_thresholds_are_rejected() {
        let mut dashboard = dashboard();
        dashboard.panels[0].field.thresholds.as_mut().unwrap().steps[2].value = Some(100.0);
        assert!(dashboard.validate().is_err());
    }

    #[test]
    fn frame_round_trips_and_checks_lengths() {
        let frame = DataFrame {
            name: "latency".into(),
            ref_id: "A".into(),
            fields: vec![
                Field {
                    name: "time".into(),
                    field_type: FieldType::Time,
                    labels: BTreeMap::new(),
                    unit: Some("ms".into()),
                    values: FieldValues::Time(vec![Some(1_700_000_000_000), None]),
                },
                Field {
                    name: "p95".into(),
                    field_type: FieldType::Number,
                    labels: BTreeMap::from([("env".into(), "prod".into())]),
                    unit: Some("ms".into()),
                    values: FieldValues::Number(vec![Some(42.0), None]),
                },
            ],
            meta: FrameMeta {
                preferred_visualization: Some(PanelKind::TimeSeries),
                executed_query: Some("A".into()),
                custom: BTreeMap::new(),
            },
        };
        frame.validate().unwrap();
        let json = serde_json::to_string(&frame).unwrap();
        let back: DataFrame = serde_json::from_str(&json).unwrap();
        assert_eq!(frame, back);

        let mut bad = frame;
        bad.fields[1].values = FieldValues::Number(vec![Some(1.0)]);
        assert!(bad.validate().is_err());
    }

    #[test]
    fn field_type_must_match_values() {
        let frame = DataFrame {
            name: "bad".into(),
            ref_id: "A".into(),
            fields: vec![Field {
                name: "x".into(),
                field_type: FieldType::Number,
                labels: BTreeMap::new(),
                unit: None,
                values: FieldValues::String(vec![Some("nope".into())]),
            }],
            meta: FrameMeta::default(),
        };
        assert!(frame.validate().is_err());
    }
}
