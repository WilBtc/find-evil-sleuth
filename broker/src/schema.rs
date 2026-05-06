use anyhow::{anyhow, Result};
use serde_json::Value;

pub fn validate(schema: &Value, instance: &Value) -> Result<()> {
    let validator = jsonschema::validator_for(schema)
        .map_err(|e| anyhow!("invalid tool args_schema: {e}"))?;
    let errors: Vec<_> = validator.iter_errors(instance).collect();
    if errors.is_empty() {
        Ok(())
    } else {
        let msg = errors.iter().map(|e| e.to_string()).collect::<Vec<_>>().join("; ");
        Err(anyhow!("args validation failed: {msg}"))
    }
}
