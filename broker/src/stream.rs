//! Streaming blake3 hasher + sharded blob writer + artifacts row.

use anyhow::{Context, Result};
use blake3::Hasher;
use sqlx::PgPool;
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::io::AsyncWriteExt;

pub struct BlobWriter {
    root: PathBuf,
}

impl BlobWriter {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// Hash, store sharded, upsert artifacts row, return 32-byte hash.
    pub async fn ingest(&self, pool: &PgPool, bytes: &[u8], mime: Option<&str>) -> Result<[u8; 32]> {
        let mut hasher = Hasher::new();
        hasher.update(bytes);
        let hash = *hasher.finalize().as_bytes();
        let hex = hex::encode(hash);

        let shard_dir = self.root.join(&hex[0..2]).join(&hex[2..4]);
        fs::create_dir_all(&shard_dir).await
            .with_context(|| format!("mkdir {}", shard_dir.display()))?;
        let blob_path = shard_dir.join(&hex);

        if !blob_path.exists() {
            let mut f = fs::File::create(&blob_path).await
                .with_context(|| format!("create {}", blob_path.display()))?;
            f.write_all(bytes).await?;
            f.flush().await?;
        }

        sqlx::query(
            r#"INSERT INTO artifacts (artifact_hash, size_bytes, mime, blob_path)
               VALUES ($1, $2, $3, $4)
               ON CONFLICT (artifact_hash) DO NOTHING"#,
        )
        .bind(hash.as_slice())
        .bind(bytes.len() as i64)
        .bind(mime)
        .bind(blob_path.display().to_string())
        .execute(pool)
        .await?;

        Ok(hash)
    }
}

pub fn default_root() -> PathBuf {
    std::env::var("SLEUTH_BLOB_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| Path::new("/var/sleuth/blobs").to_path_buf())
}
