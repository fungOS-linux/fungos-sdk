//! Convert Grafana dashboard JSON into the portable dashboard contract.
//!
//! Usage:
//!   grafana-import <grafana.json> [--out normalized.json]
//!
//! Warnings go to stderr. Exit code is zero when the dashboard validates.

use fungos_sdk::grafana::import_dashboard;
use serde_json::Value;
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let path = args.next().ok_or("usage: grafana-import <grafana.json>")?;
    let mut out = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--out" => out = Some(args.next().ok_or("--out needs a path")?),
            other => return Err(format!("unknown argument {other}").into()),
        }
    }
    let bytes = std::fs::read(&path)?;
    let value: Value = serde_json::from_slice(&bytes)?;
    let imported = import_dashboard(&value)?;
    for warning in &imported.warnings {
        eprintln!("warning {}: {}", warning.path, warning.message);
    }
    let encoded = serde_json::to_vec_pretty(&imported.dashboard)?;
    match out {
        Some(path) => std::fs::write(&path, encoded)?,
        None => println!("{}", String::from_utf8(encoded)?),
    }
    Ok(())
}
