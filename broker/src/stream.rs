//! Streaming blake3 hasher + blob-dir writer. Phase 1.5.

#![allow(dead_code)]

use anyhow::Result;
use std::path::Path;

pub struct BlobWriter;

impl BlobWriter {
    pub async fn write_to_blob_dir(_root: &Path, _bytes: &[u8]) -> Result<[u8; 32]> {
        todo!("Phase 1.5 — sharded blob writer (aa/bb/<hex>)")
    }
}
