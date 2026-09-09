//! Wave↔role roster — the single source of truth for "which agent-definition slugs belong to
//! which wave" (`CLAUDE.md` §1/§2's role↔wave table).
//!
//! **Why this lives here and not in `bathos-cli`:** this table used to be a CLI-private
//! function (`wave_role_slugs` in `bathos-cli/src/main.rs`). Moving it to `bathos-state` lets
//! `model_plan::resolve_effective`/`validate_wave` (via the `wave_id` they already take) and any
//! future crate that needs "who's in W5" share one definition instead of re-typing the table —
//! ladder step 2, "already lives a few files over, reuse it" (`ponytail-inject-kr.md` §2).
//!
//! This module makes **no policy decisions**: it is a static transcription of `CLAUDE.md`'s
//! table, nothing more. Changing who's in which wave is a `CLAUDE.md` edit followed by a match
//! arm edit here — never the other way around (this module must never drift from the document
//! that's the actual source of truth for role assignments).

/// Every wave ID this table knows about, in pipeline order. Used by [`role_wave`]'s scan — see
/// that function's doc comment for why "first match in this order" is the chosen tie-break for
/// roles that appear in more than one wave.
const WAVE_IDS: [&str; 7] = ["W0", "W1", "W2", "W3", "W4", "W5", "W6"];

/// Returns the agent-definition slugs assigned to `wave_id` (case-insensitive, e.g. `"w5"` and
/// `"W5"` both match), or `None` if `wave_id` isn't a recognized wave.
///
/// W3/W6's overlap (Thomas/Matthias/Timothy appear in both) is intentional and documented in
/// `CLAUDE.md` §1 ("+W3 independent review"/"+W3 assist") — this table transcribes that overlap verbatim
/// rather than picking one wave per role, so `bathos model show/validate --wave W3` and `--wave
/// W6` both correctly include them.
pub fn wave_role_slugs(wave_id: &str) -> Option<&'static [&'static str]> {
    match wave_id.to_ascii_uppercase().as_str() {
        "W0" => Some(&["caleb-market-analyst", "john-reverse-specialist"]),
        "W1" => Some(&["john-reverse-specialist", "caleb-market-analyst"]),
        "W2" => Some(&[
            "joshua-service-planner",
            "james-architect",
            "jonnathan-chief-designer",
        ]),
        "W3" => Some(&[
            "matthew-story-engineer",
            "thomas-code-reviewer",
            "matthias-qa-validator",
            "timothy-doc-specialist",
        ]),
        "W4" => Some(&["mark-ip-specialist", "nathanael-research-writer"]),
        "W5" => Some(&[
            "phillip-backend-engineer",
            "andrew-frontend-engineer",
            "stephen-ml-engineer",
        ]),
        "W6" => Some(&[
            "thomas-code-reviewer",
            "timothy-doc-specialist",
            "matthias-qa-validator",
            "michael-security-specialist",
            "hananiah-refactoring-specialist",
            "martin-monitoring-reporter",
        ]),
        _ => None,
    }
}

/// Reverse lookup: which wave "owns" `slug`, for callers with no wave context of their own
/// (e.g. `bathos model resolve <slug>` invoked without `--wave`).
///
/// **Multi-wave roles — documented policy (do not treat this as authoritative for them):**
/// Thomas/Matthias/Timothy each appear in both W3 and W6's rosters. This function returns the
/// **first match in `W0..W6` pipeline order** — i.e. `"W3"` for all three — which is a
/// deliberately simple, honest tie-break ("earliest wave this role touches"), **not** an
/// encoding of which wave `CLAUDE.md`'s prose calls their "primary" one (that would require a
/// second hardcoded precedence table with no independent source of truth, which is worse than
/// just being explicit about the limitation). Any caller that actually needs the W6-specific
/// policy for one of these three roles **must** pass `"W6"` explicitly to
/// `model_plan::resolve_effective`/`resolve_effective_runtime` rather than trust this function's
/// guess — this is why those two take `wave_id` as an explicit parameter instead of calling
/// `role_wave` internally.
pub fn role_wave(slug: &str) -> Option<&'static str> {
    WAVE_IDS
        .iter()
        .find(|w| {
            wave_role_slugs(w)
                .map(|roster| roster.contains(&slug))
                .unwrap_or(false)
        })
        .copied()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wave_role_slugs_is_case_insensitive_and_rejects_unknown_wave() {
        assert_eq!(wave_role_slugs("w5"), wave_role_slugs("W5"));
        assert!(wave_role_slugs("W5")
            .unwrap()
            .contains(&"phillip-backend-engineer"));
        assert_eq!(wave_role_slugs("W9"), None);
    }

    #[test]
    fn wave_role_slugs_w3_and_w6_both_list_the_shared_reviewers() {
        for slug in [
            "thomas-code-reviewer",
            "matthias-qa-validator",
            "timothy-doc-specialist",
        ] {
            assert!(wave_role_slugs("W3").unwrap().contains(&slug));
            assert!(wave_role_slugs("W6").unwrap().contains(&slug));
        }
    }

    #[test]
    fn role_wave_single_wave_role_resolves_unambiguously() {
        assert_eq!(role_wave("phillip-backend-engineer"), Some("W5"));
        assert_eq!(role_wave("joshua-service-planner"), Some("W2"));
    }

    #[test]
    fn role_wave_multi_wave_role_returns_earliest_wave_per_documented_policy() {
        // See `role_wave`'s doc comment: this is "earliest wave", not "CLAUDE.md's primary
        // column" — Thomas/Matthias/Timothy's CLAUDE.md-listed primary wave is actually W6, but
        // this function intentionally returns their first (W3) appearance.
        assert_eq!(role_wave("thomas-code-reviewer"), Some("W3"));
        assert_eq!(role_wave("matthias-qa-validator"), Some("W3"));
        assert_eq!(role_wave("timothy-doc-specialist"), Some("W3"));
    }

    #[test]
    fn role_wave_unknown_slug_returns_none() {
        assert_eq!(role_wave("nonexistent-slug"), None);
    }
}
