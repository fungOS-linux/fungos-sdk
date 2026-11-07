//! Grafana dashboard JSON importer.
//!
//! This is an adapter, not a compatibility promise. It imports the operational
//! subset the Soil renderer can represent and returns a warning for everything
//! it had to drop.

use crate::dashboard::{
    AnnotationQuery, Dashboard, DashboardLink, DashboardLinkKind, DataLink, DatasourceRef,
    FieldColor, FieldColorMode, FieldConfig, FieldMatcher, FieldOverride, LegendMode,
    LegendOptions, LegendPlacement, LegendValue, Orientation, Panel, PanelKind, PanelOptions,
    PanelRect, Query, QueryType, Reduce, Rgb, ThresholdMode, ThresholdStep, Thresholds, TimeBound,
    TimeRange, TooltipMode, TransformMode, TransformSpec, ValueMapping, Variable, VariableKind,
    VariableOption, VariableRefresh, VariableSort, DASHBOARD_SCHEMA_VERSION,
};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImportWarning {
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImportedDashboard {
    pub dashboard: Dashboard,
    pub warnings: Vec<ImportWarning>,
}

pub fn import_dashboard(value: &Value) -> Result<ImportedDashboard, String> {
    let mut warnings = Vec::new();
    if value.get("schemaVersion").is_none() {
        warnings.push(ImportWarning {
            path: "/schemaVersion".into(),
            message: "missing Grafana schemaVersion; importing anyway".into(),
        });
    }
    let title = string(value, "title").unwrap_or_else(|| "Untitled dashboard".into());
    let uid = value
        .get("uid")
        .and_then(Value::as_str)
        .map(str::to_owned)
        .unwrap_or_else(|| slug(&title));
    let time = import_time(value.get("time"));
    let refresh = value
        .get("refresh")
        .and_then(Value::as_str)
        .and_then(parse_duration_ms)
        .map(|interval_ms| crate::dashboard::Refresh {
            interval_ms,
            pause_on_hover: false,
        });

    let mut drafts = Vec::new();
    if let Some(panels) = value.get("panels").and_then(Value::as_array) {
        collect_panels(panels, &mut drafts, &mut warnings, "panels");
    } else {
        warnings.push(ImportWarning {
            path: "/panels".into(),
            message: "dashboard has no panels array".into(),
        });
    }

    let max_y = drafts
        .iter()
        .map(|draft| draft.grid.1 + draft.grid.3)
        .fold(1.0f64, f64::max);
    let mut used_ids = std::collections::BTreeSet::new();
    let panels = drafts
        .into_iter()
        .map(|draft| {
            let (x, y, w, h) = draft.grid;
            let mut panel = draft.panel;
            if !used_ids.insert(panel.id.clone()) {
                let mut suffix = 2;
                loop {
                    let candidate = format!("{}-{suffix}", panel.id);
                    if used_ids.insert(candidate.clone()) {
                        panel.id = candidate;
                        break;
                    }
                    suffix += 1;
                }
            }
            panel.rect = PanelRect {
                x: (x / 24.0).clamp(0.0, 1.0) as f32,
                y: (y / max_y).clamp(0.0, 1.0) as f32,
                width: (w / 24.0).clamp(0.001, 1.0) as f32,
                height: (h / max_y).clamp(0.001, 1.0) as f32,
            };
            if panel.rect.x + panel.rect.width > 1.0 {
                panel.rect.width = (1.0 - panel.rect.x).max(0.001);
            }
            if panel.rect.y + panel.rect.height > 1.0 {
                panel.rect.height = (1.0 - panel.rect.y).max(0.001);
            }
            panel
        })
        .collect();

    let variables = import_variables(value, &mut warnings);
    let annotations = import_annotations(value, &mut warnings);
    let links = value
        .get("links")
        .and_then(Value::as_array)
        .map(|links| {
            links
                .iter()
                .filter_map(|link| {
                    Some(DashboardLink {
                        title: string(link, "title")?,
                        url: string(link, "url")?,
                        kind: if link.get("type").and_then(Value::as_str) == Some("dashboards") {
                            DashboardLinkKind::Dashboards
                        } else {
                            DashboardLinkKind::Link
                        },
                    })
                })
                .collect()
        })
        .unwrap_or_default();

    let dashboard = Dashboard {
        schema_version: DASHBOARD_SCHEMA_VERSION,
        uid,
        title,
        description: string(value, "description"),
        tags: strings(value.get("tags")),
        time,
        refresh,
        timezone: string(value, "timezone"),
        variables,
        panels,
        annotations,
        links,
    };
    dashboard.validate()?;
    Ok(ImportedDashboard {
        dashboard,
        warnings,
    })
}

struct PanelDraft {
    panel: Panel,
    grid: (f64, f64, f64, f64),
}

fn collect_panels(
    panels: &[Value],
    out: &mut Vec<PanelDraft>,
    warnings: &mut Vec<ImportWarning>,
    path: &str,
) {
    for (index, panel) in panels.iter().enumerate() {
        let child_path = format!("{path}/{index}");
        let kind = panel
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("unknown");
        if kind == "row" {
            if let Some(children) = panel.get("panels").and_then(Value::as_array) {
                collect_panels(children, out, warnings, &format!("{child_path}/panels"));
            }
            continue;
        }
        let grid = grid_pos(panel.get("gridPos"));
        let id = panel
            .get("id")
            .map(|id| id.to_string())
            .filter(|id| !id.is_empty() && id != "null")
            .or_else(|| string(panel, "title").map(|title| slug(&title)))
            .unwrap_or_else(|| format!("panel-{index}"));
        let title = string(panel, "title").unwrap_or_else(|| format!("Panel {id}"));
        let panel_kind = panel_kind(kind);
        if matches!(panel_kind, PanelKind::Custom { .. }) {
            warnings.push(ImportWarning {
                path: format!("{child_path}/type"),
                message: format!("unsupported panel type {kind:?}; preserving as custom"),
            });
        }
        let panel_datasource = datasource(panel.get("datasource"));
        let queries = import_targets(panel, panel_datasource.as_ref(), warnings, &child_path);
        let field = field_config(
            panel.pointer("/fieldConfig/defaults"),
            warnings,
            &child_path,
        );
        let overrides = import_overrides(panel, warnings, &child_path);
        let options = panel_options(panel, warnings, &child_path);
        let transforms = import_transforms(panel, warnings, &child_path);
        let links = data_links(panel.get("links"));
        let panel = Panel {
            id,
            title,
            kind: panel_kind,
            description: string(panel, "description"),
            rect: PanelRect::default(),
            queries,
            transforms,
            field,
            overrides,
            options,
            links,
            repeat: string(panel, "repeat"),
        };
        out.push(PanelDraft { panel, grid });
    }
}

fn grid_pos(value: Option<&Value>) -> (f64, f64, f64, f64) {
    let Some(value) = value else {
        return (0.0, 0.0, 24.0, 8.0);
    };
    (
        value.get("x").and_then(Value::as_f64).unwrap_or(0.0),
        value.get("y").and_then(Value::as_f64).unwrap_or(0.0),
        value.get("w").and_then(Value::as_f64).unwrap_or(24.0),
        value.get("h").and_then(Value::as_f64).unwrap_or(8.0),
    )
}

fn panel_kind(kind: &str) -> PanelKind {
    match kind {
        "timeseries" => PanelKind::TimeSeries,
        "stat" => PanelKind::Stat,
        "gauge" => PanelKind::Gauge,
        "bargauge" => PanelKind::BarGauge,
        "table" => PanelKind::Table,
        "heatmap" => PanelKind::Heatmap,
        "state-timeline" | "status-history" => PanelKind::StatusHistory,
        "logs" => PanelKind::Logs,
        "text" => PanelKind::Text,
        "histogram" => PanelKind::Histogram,
        "nodeGraph" => PanelKind::NodeGraph,
        "geomap" => PanelKind::Geomap,
        other => PanelKind::Custom {
            kind: other.to_owned(),
        },
    }
}

fn import_targets(
    panel: &Value,
    panel_datasource: Option<&DatasourceRef>,
    warnings: &mut Vec<ImportWarning>,
    path: &str,
) -> Vec<Query> {
    let Some(targets) = panel.get("targets").and_then(Value::as_array) else {
        return Vec::new();
    };
    targets
        .iter()
        .enumerate()
        .filter_map(|(index, target)| {
            let expression = target
                .get("expr")
                .and_then(Value::as_str)
                .or_else(|| target.get("query").and_then(Value::as_str))
                .unwrap_or("");
            if expression.trim().is_empty() {
                warnings.push(ImportWarning {
                    path: format!("{path}/targets/{index}"),
                    message: "target has no PromQL/SQL expression; skipped".into(),
                });
                return None;
            }
            let ref_id = string(target, "refId").unwrap_or_else(|| "A".into());
            let datasource =
                datasource(target.get("datasource")).or_else(|| panel_datasource.cloned());
            let query_type = if target.get("instant").and_then(Value::as_bool) == Some(true) {
                QueryType::Instant
            } else {
                QueryType::Range
            };
            let interval_ms = target
                .get("intervalMs")
                .and_then(Value::as_u64)
                .or_else(|| {
                    target
                        .get("interval")
                        .and_then(Value::as_str)
                        .and_then(parse_duration_ms)
                });
            Some(Query {
                ref_id,
                hidden: target.get("hide").and_then(Value::as_bool).unwrap_or(false),
                datasource,
                expression: expression.to_owned(),
                query_type,
                time: None,
                interval_ms,
                max_points: target
                    .get("maxDataPoints")
                    .and_then(Value::as_u64)
                    .map(|value| value.min(u32::MAX as u64) as u32),
                legend: string(target, "legendFormat"),
            })
        })
        .collect()
}

fn datasource(value: Option<&Value>) -> Option<DatasourceRef> {
    let value = value?;
    if let Some(value) = value.as_str() {
        if value.is_empty() || value == "-- Mixed --" {
            return None;
        }
        return Some(DatasourceRef {
            uid: value.to_owned(),
            kind: "unknown".into(),
        });
    }
    Some(DatasourceRef {
        uid: value
            .get("uid")
            .and_then(Value::as_str)
            .unwrap_or("default")
            .to_owned(),
        kind: value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_owned(),
    })
}

fn import_time(value: Option<&Value>) -> TimeRange {
    let bound = |name: &str, default: &str| {
        let text = value
            .and_then(|time| time.get(name))
            .and_then(Value::as_str)
            .unwrap_or(default);
        if let Ok(ms) = text.parse::<i64>() {
            TimeBound::Absolute { unix_ms: ms }
        } else {
            TimeBound::Relative {
                expression: text.to_owned(),
            }
        }
    };
    TimeRange {
        from: bound("from", "now-6h"),
        to: bound("to", "now"),
    }
}

fn field_config(
    value: Option<&Value>,
    warnings: &mut Vec<ImportWarning>,
    path: &str,
) -> FieldConfig {
    let mut config = FieldConfig::default();
    let Some(value) = value else {
        return config;
    };
    apply_field_config(&mut config, value);
    if value.get("thresholds").is_some() && config.thresholds.is_none() {
        warnings.push(ImportWarning {
            path: format!("{path}/fieldConfig/defaults/thresholds"),
            message: "thresholds were present but could not be imported".into(),
        });
    }
    config
}

fn apply_field_config(config: &mut FieldConfig, value: &Value) {
    if let Some(unit) = string(value, "unit") {
        config.unit = Some(unit);
    }
    if let Some(decimals) = value.get("decimals").and_then(Value::as_u64) {
        config.decimals = Some(decimals.min(10) as u8);
    }
    if let Some(min) = value.get("min").and_then(Value::as_f64) {
        config.min = Some(min);
    }
    if let Some(max) = value.get("max").and_then(Value::as_f64) {
        config.max = Some(max);
    }
    if let Some(display_name) = string(value, "displayName") {
        config.display_name = Some(display_name);
    }
    if let Some(no_value) = string(value, "noValue") {
        config.no_value = Some(no_value);
    }
    if let Some(thresholds) = value.get("thresholds") {
        config.thresholds = import_thresholds(thresholds);
    }
    if let Some(mappings) = value.get("mappings").and_then(Value::as_array) {
        config.mappings = mappings.iter().filter_map(import_mapping).collect();
    }
    if let Some(color) = value.get("color") {
        config.color = import_field_color(color);
    }
    if let Some(links) = value.get("links") {
        config.links = data_links(Some(links));
    }
}

fn import_thresholds(value: &Value) -> Option<Thresholds> {
    let steps = value
        .get("steps")
        .and_then(Value::as_array)?
        .iter()
        .map(|step| ThresholdStep {
            value: step.get("value").and_then(Value::as_f64),
            color: step
                .get("color")
                .and_then(Value::as_str)
                .and_then(parse_color)
                .unwrap_or(Rgb([128, 128, 128])),
        })
        .collect::<Vec<_>>();
    if steps.is_empty() {
        return None;
    }
    Some(Thresholds {
        mode: match value.get("mode").and_then(Value::as_str) {
            Some("percentage") => ThresholdMode::Percentage,
            _ => ThresholdMode::Absolute,
        },
        steps,
    })
}

fn import_mapping(value: &Value) -> Option<ValueMapping> {
    let kind = value.get("type").and_then(Value::as_str)?;
    let options = value.get("options").unwrap_or(&Value::Null);
    let text = string(options, "text");
    let color = string(options, "color").as_deref().and_then(parse_color);
    match kind {
        "value" => Some(ValueMapping::Value {
            value: options.get("value")?.to_string(),
            text,
            color,
        }),
        "range" => Some(ValueMapping::Range {
            from: options.get("from").and_then(Value::as_f64)?,
            to: options.get("to").and_then(Value::as_f64)?,
            text,
            color,
        }),
        "regex" => Some(ValueMapping::Regex {
            pattern: string(options, "pattern")?,
            text,
            color,
        }),
        "special" => Some(ValueMapping::Special {
            key: string(options, "match")?,
            text,
            color,
        }),
        _ => None,
    }
}

fn import_field_color(value: &Value) -> Option<FieldColor> {
    let mode = match value.get("mode").and_then(Value::as_str) {
        Some("continuous") | Some("continuous-GrYlRd") | Some("continuous-RdYlGr") => {
            FieldColorMode::Continuous
        }
        Some("thresholds") => FieldColorMode::Thresholds,
        Some("fixed") => FieldColorMode::Fixed,
        Some("palette-classic") | Some("palette-classic-by-name") => FieldColorMode::Series,
        _ => FieldColorMode::Series,
    };
    Some(FieldColor {
        mode,
        fixed: string(value, "fixedColor").as_deref().and_then(parse_color),
    })
}

fn import_overrides(
    panel: &Value,
    warnings: &mut Vec<ImportWarning>,
    path: &str,
) -> Vec<FieldOverride> {
    let Some(overrides) = panel
        .pointer("/fieldConfig/overrides")
        .and_then(Value::as_array)
    else {
        return Vec::new();
    };
    overrides
        .iter()
        .enumerate()
        .filter_map(|(index, override_)| {
            let matcher = override_.get("matcher")?;
            let matcher = match matcher.get("id").and_then(Value::as_str)? {
                "byName" => FieldMatcher::ByName {
                    name: string(matcher, "options")?,
                },
                "byRegexp" | "byRegexpOrNames" => FieldMatcher::ByRegex {
                    pattern: string(matcher, "options")?,
                },
                "byFrameRefID" => FieldMatcher::ByQuery {
                    ref_id: string(matcher, "options")?,
                },
                other => {
                    warnings.push(ImportWarning {
                        path: format!("{path}/fieldConfig/overrides/{index}/matcher"),
                        message: format!("unsupported override matcher {other:?}; skipped"),
                    });
                    return None;
                }
            };
            let mut properties = FieldConfig::default();
            if let Some(values) = override_.get("properties").and_then(Value::as_array) {
                for property in values {
                    let id = property.get("id").and_then(Value::as_str).unwrap_or("");
                    let value = property.get("value").unwrap_or(&Value::Null);
                    apply_property(&mut properties, id, value);
                }
            }
            Some(FieldOverride {
                matcher,
                properties,
            })
        })
        .collect()
}

fn apply_property(config: &mut FieldConfig, id: &str, value: &Value) {
    match id {
        "unit" => config.unit = value.as_str().map(str::to_owned),
        "decimals" => {
            config.decimals = value.as_u64().map(|value| value.min(10) as u8);
        }
        "min" => config.min = value.as_f64(),
        "max" => config.max = value.as_f64(),
        "displayName" => config.display_name = value.as_str().map(str::to_owned),
        "noValue" => config.no_value = value.as_str().map(str::to_owned),
        "thresholds" => config.thresholds = import_thresholds(value),
        "mappings" => {
            config.mappings = value
                .as_array()
                .map(|values| values.iter().filter_map(import_mapping).collect())
                .unwrap_or_default();
        }
        "color" => config.color = import_field_color(value),
        "links" => config.links = data_links(Some(value)),
        _ => {}
    }
}

fn panel_options(panel: &Value, warnings: &mut Vec<ImportWarning>, path: &str) -> PanelOptions {
    let mut options = PanelOptions::default();
    if let Some(legend) = panel.pointer("/options/legend") {
        options.legend = LegendOptions {
            show: legend.get("show").and_then(Value::as_bool).unwrap_or(true),
            mode: match legend.get("displayMode").and_then(Value::as_str) {
                Some("table") => LegendMode::Table,
                _ => LegendMode::List,
            },
            placement: match legend.get("placement").and_then(Value::as_str) {
                Some("right") => LegendPlacement::Right,
                _ => LegendPlacement::Bottom,
            },
            values: strings(legend.get("calcs"))
                .into_iter()
                .filter_map(|value| match value.as_str() {
                    "last" | "lastNotNull" => Some(LegendValue::Last),
                    "min" => Some(LegendValue::Min),
                    "max" => Some(LegendValue::Max),
                    "mean" => Some(LegendValue::Mean),
                    "sum" => Some(LegendValue::Sum),
                    "count" => Some(LegendValue::Count),
                    _ => None,
                })
                .collect(),
        };
    }
    if let Some(tooltip) = panel.pointer("/options/tooltip") {
        options.tooltip = match tooltip.get("mode").and_then(Value::as_str) {
            Some("multi") | Some("all") => TooltipMode::All,
            Some("none") | Some("hidden") => TooltipMode::Hidden,
            _ => TooltipMode::Single,
        };
    }
    if let Some(orientation) = panel
        .pointer("/options/orientation")
        .and_then(Value::as_str)
    {
        options.orientation = match orientation {
            "horizontal" => Orientation::Horizontal,
            "vertical" => Orientation::Vertical,
            _ => Orientation::Auto,
        };
    }
    if let Some(text) = panel
        .pointer("/options/content")
        .and_then(Value::as_str)
        .or_else(|| panel.pointer("/options/text").and_then(Value::as_str))
    {
        options.text = Some(text.to_owned());
    }
    if let Some(calcs) = panel
        .pointer("/options/reduceOptions/calcs")
        .and_then(Value::as_array)
    {
        options.reduce = calcs.first().and_then(|calc| match calc.as_str() {
            Some("first") | Some("firstNotNull") => Some(Reduce::First),
            Some("min") => Some(Reduce::Min),
            Some("max") => Some(Reduce::Max),
            Some("mean") | Some("average") => Some(Reduce::Mean),
            Some("sum") | Some("total") => Some(Reduce::Sum),
            Some("count") => Some(Reduce::Count),
            Some("last") | Some("lastNotNull") => Some(Reduce::Last),
            _ => None,
        });
    }
    if let Some(mode) = panel.pointer("/options/colorMode").and_then(Value::as_str) {
        options.color_mode = match mode {
            "value" => crate::dashboard::ColorMode::Value,
            "background" => crate::dashboard::ColorMode::Background,
            "thresholds" => crate::dashboard::ColorMode::Thresholds,
            "fixed" => crate::dashboard::ColorMode::Fixed,
            _ => crate::dashboard::ColorMode::Palette,
        };
    }
    options.show_values = panel
        .pointer("/options/showValue")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if options.text.is_none() && matches!(panel.get("type").and_then(Value::as_str), Some("text")) {
        warnings.push(ImportWarning {
            path: format!("{path}/options/content"),
            message: "text panel has no content".into(),
        });
    }
    options
}

fn import_transforms(
    panel: &Value,
    warnings: &mut Vec<ImportWarning>,
    path: &str,
) -> Vec<TransformSpec> {
    let Some(transforms) = panel.get("transformations").and_then(Value::as_array) else {
        return Vec::new();
    };
    transforms
        .iter()
        .enumerate()
        .filter_map(|(index, transform)| {
            let kind = transform.get("id").and_then(Value::as_str).unwrap_or("");
            let options = transform.get("options").cloned().unwrap_or(Value::Null);
            let out = match kind {
                "reduce" => Some(TransformSpec::Reduce {
                    input: string(&options, "include").filter(|value| !value.is_empty()),
                    reducer: options
                        .get("reducers")
                        .and_then(Value::as_array)
                        .and_then(|values| values.first())
                        .and_then(Value::as_str)
                        .and_then(reduce_kind)
                        .unwrap_or(Reduce::Last),
                    mode: TransformMode::ReduceFields,
                }),
                "filterByValue" => Some(TransformSpec::Filter {
                    field: string(&options, "field")
                        .or_else(|| {
                            options
                                .get("filters")
                                .and_then(Value::as_array)
                                .and_then(|f| f.first())
                                .and_then(|f| string(f, "fieldName"))
                        })
                        .unwrap_or_default(),
                    op: crate::dashboard::FilterOp::Eq,
                    value: options.clone(),
                }),
                "organize" => Some(TransformSpec::Organize {
                    exclude: strings(options.get("excludeByName")),
                    rename: options
                        .get("renameByName")
                        .and_then(Value::as_object)
                        .map(|map| {
                            map.iter()
                                .filter_map(|(key, value)| {
                                    Some((key.clone(), value.as_str()?.to_owned()))
                                })
                                .collect()
                        })
                        .unwrap_or_default(),
                    index: strings(options.get("indexByName")),
                }),
                "renameByRegex" => Some(TransformSpec::Rename {
                    from: string(&options, "regex").unwrap_or_default(),
                    to: string(&options, "replacement").unwrap_or_default(),
                }),
                "merge" => Some(TransformSpec::Merge {
                    fields: strings(options.get("fields")),
                }),
                "joinByField" => Some(TransformSpec::Join {
                    by: strings(options.get("byField")),
                    mode: crate::dashboard::JoinMode::Outer,
                }),
                "calculateField" => Some(TransformSpec::Calculate {
                    field: string(&options, "alias").unwrap_or_else(|| "result".into()),
                    expression: string(&options, "expression").unwrap_or_default(),
                }),
                "sortBy" => Some(TransformSpec::Sort {
                    field: string(&options, "field").unwrap_or_default(),
                    desc: options
                        .get("reverse")
                        .and_then(Value::as_bool)
                        .unwrap_or(false),
                }),
                "limit" => Some(TransformSpec::Limit {
                    limit: options.get("limit").and_then(Value::as_u64).unwrap_or(1) as u32,
                }),
                "labelsToFields" => Some(TransformSpec::LabelsToFields {
                    value_field: string(&options, "valueLabel"),
                }),
                "rowsToFields" => Some(TransformSpec::RowsToFields {
                    mappings: options
                        .get("mappings")
                        .and_then(Value::as_object)
                        .map(|map| {
                            map.iter()
                                .filter_map(|(key, value)| {
                                    Some((key.clone(), value.get("name")?.as_str()?.to_owned()))
                                })
                                .collect()
                        })
                        .unwrap_or_default(),
                }),
                "seriesToRows" => Some(TransformSpec::SeriesToRows),
                other => {
                    warnings.push(ImportWarning {
                        path: format!("{path}/transformations/{index}"),
                        message: format!("unsupported transform {other:?}; preserved as custom"),
                    });
                    Some(TransformSpec::Custom {
                        kind: other.to_owned(),
                        options,
                    })
                }
            };
            out.filter(|transform| transform_is_valid(transform))
        })
        .collect()
}

fn transform_is_valid(transform: &TransformSpec) -> bool {
    match transform {
        TransformSpec::Filter { field, .. } => !field.is_empty(),
        TransformSpec::Rename { from, to } => !from.is_empty() && !to.is_empty(),
        TransformSpec::Calculate { field, expression } => {
            !field.is_empty() && !expression.is_empty()
        }
        TransformSpec::Sort { field, .. } => !field.is_empty(),
        TransformSpec::Limit { limit } => *limit > 0,
        _ => true,
    }
}

fn reduce_kind(value: &str) -> Option<Reduce> {
    Some(match value {
        "lastNotNull" | "last" => Reduce::Last,
        "firstNotNull" | "first" => Reduce::First,
        "min" => Reduce::Min,
        "max" => Reduce::Max,
        "mean" | "average" => Reduce::Mean,
        "sum" | "total" => Reduce::Sum,
        "count" => Reduce::Count,
        _ => return None,
    })
}

fn import_variables(value: &Value, warnings: &mut Vec<ImportWarning>) -> Vec<Variable> {
    let Some(variables) = value.pointer("/templating/list").and_then(Value::as_array) else {
        return Vec::new();
    };
    variables
        .iter()
        .enumerate()
        .filter_map(|(index, variable)| {
            let name = string(variable, "name")?;
            let kind = match variable.get("type").and_then(Value::as_str).unwrap_or("") {
                "query" => VariableKind::Query,
                "custom" => VariableKind::Custom,
                "constant" => VariableKind::Constant,
                "datasource" => VariableKind::Datasource,
                "interval" => VariableKind::Interval,
                "textbox" => VariableKind::Textbox,
                "adhoc" => VariableKind::Adhoc,
                other => {
                    warnings.push(ImportWarning {
                        path: format!("/templating/list/{index}/type"),
                        message: format!("unsupported variable type {other:?}; skipped"),
                    });
                    return None;
                }
            };
            let datasource = datasource(variable.get("datasource"));
            let query = variable.get("query").and_then(|query| {
                query
                    .as_str()
                    .map(str::to_owned)
                    .or_else(|| string(query, "query"))
            });
            let options = variable
                .get("options")
                .and_then(Value::as_array)
                .map(|options| {
                    options
                        .iter()
                        .filter_map(|option| {
                            Some(VariableOption {
                                text: string(option, "text")?,
                                value: option
                                    .get("value")
                                    .map(|value| value.to_string().trim_matches('"').to_owned())
                                    .unwrap_or_default(),
                            })
                        })
                        .collect()
                })
                .unwrap_or_default();
            let current = match variable.get("current") {
                Some(Value::Object(current)) => {
                    if let Some(values) = current.get("value").and_then(Value::as_array) {
                        values
                            .iter()
                            .map(|value| value.to_string().trim_matches('"').to_owned())
                            .collect()
                    } else {
                        current
                            .get("value")
                            .map(|value| vec![value.to_string().trim_matches('"').to_owned()])
                            .unwrap_or_default()
                    }
                }
                _ => Vec::new(),
            };
            Some(Variable {
                name,
                label: string(variable, "label"),
                kind,
                query,
                datasource,
                options,
                current,
                multi: variable
                    .get("multi")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                include_all: variable
                    .get("includeAll")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                regex: string(variable, "regex"),
                sort: match variable.get("sort").and_then(Value::as_u64).unwrap_or(0) {
                    1 => VariableSort::AlphabeticalAsc,
                    2 => VariableSort::AlphabeticalDesc,
                    3 => VariableSort::NumericalAsc,
                    4 => VariableSort::NumericalDesc,
                    _ => VariableSort::Disabled,
                },
                refresh: match variable.get("refresh").and_then(Value::as_u64).unwrap_or(0) {
                    1 => VariableRefresh::OnLoad,
                    2 => VariableRefresh::OnTimeRange,
                    _ => VariableRefresh::Never,
                },
            })
        })
        .filter(|variable| {
            if variable.name.is_empty() {
                return false;
            }
            true
        })
        .collect()
}

fn import_annotations(value: &Value, warnings: &mut Vec<ImportWarning>) -> Vec<AnnotationQuery> {
    let Some(annotations) = value.pointer("/annotations/list").and_then(Value::as_array) else {
        return Vec::new();
    };
    annotations
        .iter()
        .enumerate()
        .filter_map(|(index, annotation)| {
            let Some(datasource) = datasource(annotation.get("datasource")) else {
                warnings.push(ImportWarning {
                    path: format!("/annotations/list/{index}/datasource"),
                    message: "annotation has no datasource; skipped".into(),
                });
                return None;
            };
            let query = string(annotation, "query")
                .or_else(|| string(annotation, "expr"))
                .unwrap_or_default();
            if query.is_empty() {
                return None;
            }
            Some(AnnotationQuery {
                name: string(annotation, "name").unwrap_or_else(|| format!("annotation-{index}")),
                datasource,
                query,
                enable: annotation
                    .get("enable")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                icon_color: string(annotation, "iconColor")
                    .as_deref()
                    .and_then(parse_color),
                hide: annotation
                    .get("hide")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            })
        })
        .collect()
}

fn data_links(value: Option<&Value>) -> Vec<DataLink> {
    value
        .and_then(Value::as_array)
        .map(|links| {
            links
                .iter()
                .filter_map(|link| {
                    Some(DataLink {
                        title: string(link, "title")?,
                        url: string(link, "url")?,
                        target_blank: link
                            .get("targetBlank")
                            .and_then(Value::as_bool)
                            .unwrap_or(false),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

fn parse_duration_ms(value: &str) -> Option<u64> {
    let value = value.trim();
    if value.is_empty() || value == "false" {
        return None;
    }
    let (number, unit) = value.split_at(value.find(|c: char| !c.is_ascii_digit())?);
    let number = number.parse::<u64>().ok()?;
    Some(match unit {
        "ms" => number,
        "s" => number * 1_000,
        "m" => number * 60_000,
        "h" => number * 3_600_000,
        "d" => number * 86_400_000,
        _ => return None,
    })
}

fn parse_color(value: &str) -> Option<Rgb> {
    let value = value.trim();
    if let Some(hex) = value.strip_prefix('#') {
        if hex.len() == 6 {
            return Some(Rgb([
                u8::from_str_radix(&hex[0..2], 16).ok()?,
                u8::from_str_radix(&hex[2..4], 16).ok()?,
                u8::from_str_radix(&hex[4..6], 16).ok()?,
            ]));
        }
    }
    Some(match value {
        "green" => Rgb([34, 197, 94]),
        "yellow" => Rgb([245, 190, 80]),
        "orange" => Rgb([249, 115, 22]),
        "red" => Rgb([239, 68, 68]),
        "blue" => Rgb([96, 165, 250]),
        "purple" => Rgb([168, 85, 247]),
        _ => return None,
    })
}

fn string(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(str::to_owned)
}

fn strings(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn slug(value: &str) -> String {
    let mut out = String::new();
    let mut last_dash = false;
    for ch in value.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_alphanumeric() {
            out.push(ch);
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    if out.is_empty() {
        "dashboard".into()
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_a_realistic_grafana_dashboard() {
        let value: Value =
            serde_json::from_str(include_str!("../tests/fixtures/grafana-fleet.json")).unwrap();
        let imported = import_dashboard(&value).unwrap();
        imported.dashboard.validate().unwrap();

        assert_eq!(imported.dashboard.uid, "fleet-health");
        assert_eq!(
            imported.dashboard.refresh.as_ref().unwrap().interval_ms,
            30_000
        );
        assert_eq!(imported.dashboard.variables.len(), 2);
        assert_eq!(imported.dashboard.annotations.len(), 1);
        assert_eq!(imported.dashboard.panels.len(), 6);

        let latency = &imported.dashboard.panels[0];
        assert_eq!(latency.kind, PanelKind::TimeSeries);
        assert_eq!(latency.queries.len(), 2);
        assert_eq!(latency.queries[0].ref_id, "A");
        assert_eq!(latency.queries[0].max_points, Some(2000));
        assert_eq!(latency.field.unit.as_deref(), Some("ms"));
        assert_eq!(latency.field.thresholds.as_ref().unwrap().steps.len(), 3);
        assert_eq!(latency.overrides.len(), 1);
        assert_eq!(latency.transforms.len(), 3);
        assert!(matches!(
            latency.transforms[2],
            TransformSpec::Custom { .. }
        ));

        assert!(imported
            .warnings
            .iter()
            .any(|warning| warning.message.contains("unsupported panel type")));
        assert!(imported
            .warnings
            .iter()
            .any(|warning| warning.message.contains("unsupported transform")));
    }
}
