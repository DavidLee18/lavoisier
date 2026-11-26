//! Crash-safe file replacement for session and job files.
//!
//! [`LocalFs`] writes a unique temp file, `sync_all`s it, renames it over the target, then
//! `sync_all`s the parent directory. [`ObjectFs`] writes the final path and `sync_all`s: on a
//! GCS FUSE mount the upload happens at fsync/close and an object replace is atomic, so a
//! reader sees the old object or the new one.
//!
//! Job snapshots are handed to a [`PersistQueue`]. The queue thread does the I/O. Callers do
//! not hold the job-table mutex across that write.

use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;

static TMP_SEQ: AtomicU64 = AtomicU64::new(0);

/// Why a durable write failed. The path is logged by the caller, not stored here.
#[derive(Debug, thiserror::Error)]
pub enum DurableError {
    /// The filesystem refused the operation.
    #[error("durable io ({kind})")]
    Io {
        /// Error kind only. Not a path and not a body.
        kind: std::io::ErrorKind,
    },
}

impl From<std::io::Error> for DurableError {
    fn from(err: std::io::Error) -> Self {
        Self::Io { kind: err.kind() }
    }
}

/// Synchronous durable file operations. Called from a blocking thread, never under an async lock
/// that is held across `.await` — these methods do not await.
pub trait DurableFs: Send + Sync {
    /// Replace `path` with `bytes` so a crash cannot leave a torn file.
    ///
    /// # Errors
    ///
    /// [`DurableError::Io`] when the write, sync, or rename fails.
    fn write_atomic(&self, path: &Path, bytes: &[u8]) -> Result<(), DurableError>;

    /// Remove `path`. A missing file is success.
    ///
    /// # Errors
    ///
    /// [`DurableError::Io`] when the directory entry cannot be removed.
    fn remove(&self, path: &Path) -> Result<(), DurableError>;

    /// Names in `dir`. A missing directory is an empty list.
    ///
    /// # Errors
    ///
    /// [`DurableError::Io`] when the directory cannot be read.
    fn list(&self, dir: &Path) -> Result<Vec<PathBuf>, DurableError>;
}

/// Temp file, fsync, rename, fsync the directory. The default for local disks.
#[derive(Debug, Default, Clone, Copy)]
pub struct LocalFs;

/// Write the final object in place and fsync. For GCS FUSE mounts.
#[derive(Debug, Default, Clone, Copy)]
pub struct ObjectFs;

impl LocalFs {
    fn tmp_path(path: &Path) -> PathBuf {
        let dir = path.parent().unwrap_or_else(|| Path::new("."));
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("object");
        let n = TMP_SEQ.fetch_add(1, Ordering::Relaxed);
        dir.join(format!(".{name}.{}.{n}.tmp", std::process::id()))
    }
}

impl DurableFs for LocalFs {
    fn write_atomic(&self, path: &Path, bytes: &[u8]) -> Result<(), DurableError> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = Self::tmp_path(path);
        let write_tmp = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .open(&tmp)?;
            file.write_all(bytes)?;
            file.sync_all()?;
            Ok::<(), std::io::Error>(())
        })();
        if let Err(err) = write_tmp {
            let _ = std::fs::remove_file(&tmp);
            return Err(err.into());
        }
        if let Err(err) = std::fs::rename(&tmp, path) {
            let _ = std::fs::remove_file(&tmp);
            return Err(err.into());
        }
        if let Some(dir) = path.parent() {
            if let Ok(dir_file) = std::fs::File::open(dir) {
                let _ = dir_file.sync_all();
            }
        }
        Ok(())
    }

    fn remove(&self, path: &Path) -> Result<(), DurableError> {
        match std::fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(err) => Err(err.into()),
        }
    }

    fn list(&self, dir: &Path) -> Result<Vec<PathBuf>, DurableError> {
        list_dir(dir)
    }
}

impl DurableFs for ObjectFs {
    fn write_atomic(&self, path: &Path, bytes: &[u8]) -> Result<(), DurableError> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(path)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        Ok(())
    }

    fn remove(&self, path: &Path) -> Result<(), DurableError> {
        LocalFs.remove(path)
    }

    fn list(&self, dir: &Path) -> Result<Vec<PathBuf>, DurableError> {
        list_dir(dir)
    }
}

fn list_dir(dir: &Path) -> Result<Vec<PathBuf>, DurableError> {
    let entries = match std::fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(err) => return Err(err.into()),
    };
    let mut out = Vec::new();
    for entry in entries {
        let entry = entry?;
        out.push(entry.path());
    }
    Ok(out)
}

/// Delete leftover temp files from the old pid-based writer and from [`LocalFs`].
///
/// Returns how many files were removed. The caller logs that count.
pub fn sweep_stray_tmp(dir: &Path) -> Result<usize, DurableError> {
    let mut removed = 0;
    for path in list_dir(dir)? {
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let stray = name.contains(".tmp.") || (name.starts_with('.') && name.ends_with(".tmp"));
        if !stray {
            continue;
        }
        match std::fs::remove_file(&path) {
            Ok(()) => removed += 1,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => return Err(err.into()),
        }
    }
    Ok(removed)
}

enum Msg {
    Write {
        seq: u64,
        path: PathBuf,
        bytes: Option<Vec<u8>>,
    },
    Stop,
}

struct WaitState {
    applied: Mutex<u64>,
    cv: Condvar,
}

struct PersistInner {
    tx: std::sync::mpsc::Sender<Msg>,
    wait: Arc<WaitState>,
    seq: AtomicU64,
    thread: Mutex<Option<JoinHandle<()>>>,
}

impl Drop for PersistInner {
    fn drop(&mut self) {
        let _ = self.tx.send(Msg::Stop);
        if let Some(handle) = self
            .thread
            .lock()
            .unwrap_or_else(|err| err.into_inner())
            .take()
        {
            let _ = handle.join();
        }
    }
}

/// One background writer. Snapshots carry a sequence; an older snapshot is not applied after
/// a newer one for the same path.
#[derive(Clone)]
pub struct PersistQueue {
    inner: Arc<PersistInner>,
}

impl PersistQueue {
    /// Start the writer thread. `fs` is used for every later snapshot.
    pub fn start(fs: Arc<dyn DurableFs>) -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        let wait = Arc::new(WaitState {
            applied: Mutex::new(0),
            cv: Condvar::new(),
        });
        let wait_thread = Arc::clone(&wait);
        let thread = std::thread::Builder::new()
            .name("lvz-persist".into())
            .spawn(move || persist_loop(rx, fs, wait_thread))
            .ok();
        Self {
            inner: Arc::new(PersistInner {
                tx,
                wait,
                seq: AtomicU64::new(0),
                thread: Mutex::new(thread),
            }),
        }
    }

    /// Queue `bytes` (`None` removes) and block until this snapshot, or a newer one, is durable.
    pub fn write_and_wait(&self, path: PathBuf, bytes: Option<Vec<u8>>) {
        let seq = self.inner.seq.fetch_add(1, Ordering::Relaxed) + 1;
        if self.inner.tx.send(Msg::Write { seq, path, bytes }).is_err() {
            return;
        }
        let mut applied = self
            .inner
            .wait
            .applied
            .lock()
            .unwrap_or_else(|err| err.into_inner());
        while *applied < seq {
            applied = self
                .inner
                .wait
                .cv
                .wait(applied)
                .unwrap_or_else(|err| err.into_inner());
        }
    }
}

fn persist_loop(rx: std::sync::mpsc::Receiver<Msg>, fs: Arc<dyn DurableFs>, wait: Arc<WaitState>) {
    loop {
        let first = match rx.recv() {
            Ok(msg) => msg,
            Err(_) => return,
        };
        let mut batch = vec![first];
        while let Ok(msg) = rx.try_recv() {
            batch.push(msg);
        }
        let mut stop = false;
        let mut last: Vec<(u64, PathBuf, Option<Vec<u8>>)> = Vec::new();
        for msg in batch {
            match msg {
                Msg::Stop => stop = true,
                Msg::Write { seq, path, bytes } => {
                    if let Some(prev) = last.iter_mut().find(|(_, p, _)| p == &path) {
                        if seq >= prev.0 {
                            *prev = (seq, path, bytes);
                        }
                    } else {
                        last.push((seq, path, bytes));
                    }
                }
            }
        }
        let mut max_seq = 0;
        for (seq, path, bytes) in last {
            max_seq = max_seq.max(seq);
            let result = match &bytes {
                Some(body) => fs.write_atomic(&path, body),
                None => fs.remove(&path),
            };
            if let Err(err) = result {
                tracing::error!(
                    path = %path.display(),
                    error = %err,
                    "durable write failed"
                );
            }
        }
        if max_seq > 0 {
            let mut applied = wait.applied.lock().unwrap_or_else(|err| err.into_inner());
            if *applied < max_seq {
                *applied = max_seq;
            }
            wait.cv.notify_all();
        }
        if stop {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dir(label: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "lvz-durable-{label}-{}-{}",
            std::process::id(),
            TMP_SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).expect("dir");
        path
    }

    #[test]
    fn local_fs_replaces_and_leaves_no_tmp() {
        let dir = dir("local");
        let path = dir.join("row.json");
        std::fs::write(&path, b"old").expect("seed");
        LocalFs.write_atomic(&path, b"new").expect("write");
        assert_eq!(std::fs::read(&path).expect("read"), b"new");
        let tmp = LocalFs::tmp_path(&path);
        assert!(!tmp.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn crash_before_rename_keeps_the_old_file() {
        let dir = dir("crash");
        let path = dir.join("row.json");
        std::fs::write(&path, b"old").expect("seed");
        let tmp = LocalFs::tmp_path(&path);
        std::fs::write(&tmp, b"new").expect("tmp");
        assert_eq!(std::fs::read(&path).expect("old stays"), b"old");
        std::fs::rename(&tmp, &path).expect("commit");
        assert_eq!(std::fs::read(&path).expect("new"), b"new");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn object_fs_writes_the_final_path_only() {
        let dir = dir("object");
        let path = dir.join("row.json");
        ObjectFs.write_atomic(&path, b"obj").expect("write");
        assert_eq!(std::fs::read(&path).expect("read"), b"obj");
        let names: Vec<_> = std::fs::read_dir(&dir)
            .expect("list")
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names, vec!["row.json".to_string()]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn sweep_removes_stray_tmp_only() {
        let dir = dir("sweep");
        std::fs::write(dir.join("keep.jobs.json"), b"{}").expect("keep");
        std::fs::write(dir.join("keep.jobs.tmp.1"), b"x").expect("old writer");
        std::fs::write(dir.join(".keep.jobs.json.1.2.tmp"), b"y").expect("local");
        let n = sweep_stray_tmp(&dir).expect("sweep");
        assert_eq!(n, 2);
        assert!(dir.join("keep.jobs.json").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn queue_does_not_apply_an_older_snapshot_last() {
        let dir = dir("queue");
        let path = dir.join("row.json");
        let q = PersistQueue::start(Arc::new(LocalFs));
        q.write_and_wait(path.clone(), Some(b"one".to_vec()));
        q.write_and_wait(path.clone(), Some(b"two".to_vec()));
        assert_eq!(std::fs::read(&path).expect("read"), b"two");
        q.write_and_wait(path.clone(), None);
        assert!(!path.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
