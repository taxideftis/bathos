//! # bathos-state — BATHOS M1: state store
//!
//! The **state-foundation (M1)** crate of the BATHOS orchestration engine.
//!
//! ## Responsibilities
//! - **domain model** (`model`): serde structs based on the manifest.json ERD
//! - **JSON Schema validation** (`schema`): embed `manifest-schema.json` → invariant validation
//! - **state store** (`store`): single writer + file lock (fs4) + atomic write
//! - **audit hash chain** (`audit`): append-only sha256 integrity chain — detects accidental
//!   corruption / linkage breaks (KEYLESS; malicious forgery needs HMAC or external anchoring — SEC-02)
//! - **error model** (`error`): 1:1 mapping of exceptions.md E-STATE-*
//! - **fingerprint cache** (`fingerprint`, new in Dynamis): risky-change diff fingerprint normalization / re-approval prevention (SS1 · CF-A1)
//! - **model plan** (`model_plan`, W2 panes/model design): per-role model/runtime selection
//!   SSOT (`_state/model-plan.json`) — resolve priority chain + GLM/Codex mixed-batch validation
//! - **runtime host detection** (`runtime_host`, ADR-CX-01): pure env classification of which
//!   CLI host runtime (`claude`|`codex`|`unknown`) the current process is running under — never
//!   persisted, orthogonal to `model_plan::SessionBackend`
//! - **wave↔role roster** (`wave_roles`): static `CLAUDE.md` §1/§2 role↔wave table (moved here
//!   from a `bathos-cli`-private function so `model_plan`'s wave-aware resolve/validate and the
//!   CLI share one definition instead of two)
//!
//! ## Usage example
//! ```rust,no_run
//! use bathos_state::{store::StateStore, model::Project};
//! use std::path::Path;
//!
//! // create a new project
//! let project = Project::new("BATHOS", 3);
//! let mut store = StateStore::create(Path::new("./_state"), project).unwrap();
//!
//! // commit after a state change
//! let mut updated = store.project().clone();
//! updated.codename = "BATHOS-v2".into();
//! store.commit(updated, "Phillip", "project.updated").unwrap();
//! ```
//!
//! ## Invariants (E-STATE-* error on violation)
//! - `current_level` ∈ [0, 4]
//! - `GateVerdict.verdict` ∈ {PASS, CONCERNS, FAIL}
//! - `Wave.active_roles.len()` ≤ 3
//! - `audit-log.jsonl` hash chain: hash_prev[n] == hash_self[n-1]
//! - no direct editing of manifest.json — must go through `StateStore::commit()`

pub mod audit;
pub mod error;
pub mod fingerprint;
pub mod model;
pub mod model_plan;
pub mod runtime_host;
pub mod schema;
pub mod store;
pub mod wave_roles;

// re-export the most frequently used types
pub use error::{StateError, StateResult};
pub use model::{
    ApprovedFingerprint, Artifact, AuditEntry, GateVerdict, LevelDecision, PlugModule, Project,
    ProjectContext, ProjectStatus, RiskLog, RoleInstance, RoleStatus, StoryFile, StoryStatus, Task,
    TaskStatus, Verdict, Wave, WaveStatus,
};
pub use store::StateStore;
