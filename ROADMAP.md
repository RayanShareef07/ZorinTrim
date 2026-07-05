# Roadmap

For the current version and implementation status, see [README.md](README.md).

## Done

- Read-only detection engine (v0.2.0): system inspection, Zorin OS 18.1
  compatibility validation, and a PASS/FAIL report. See
  [README.md](README.md) for details.
- Package Classification Engine, first pass (v0.3.0): installed packages are
  classified into categories (Games, Office, Multimedia, Internet,
  Utilities, Development, System/Essential, Uncategorized) using each
  package's Debian section and priority. Classification and reporting
  only — no package listing, selection, or removal yet.
- Candidate Analysis Engine (v0.4.0): every installed package gets a risk
  level (CRITICAL/HIGH/MEDIUM/LOW), an explainable reason, and a
  recommendation, derived from combining dpkg's Essential/Priority facts,
  metapackage-dependency analysis, and the v0.3.0 package categories — no
  hardcoded package names, no single signal decides alone. Reported with
  progressive disclosure (summary, actionable candidates, protected
  packages). Analysis and reporting only — still no removal.
- Safety Validation Engine (v0.5.0): every package's recommendation is now
  paired with a confidence level (HIGH/MEDIUM/LOW), derived from how many
  of the v0.4.0 risk signals agree, with no new signals and no hardcoded
  package names. Uncertain (Uncategorized) classification always yields
  LOW confidence and a conservative recommendation; fully optional
  packages state the absence of protective signals explicitly rather than
  leaving it implied. The reason for each actionable package is now shown
  as a full bulleted evidence list in a boxed report card, alongside the
  existing risk/recommendation. Still analysis and reporting only — no
  removal.

## Planned, unscheduled

In rough priority order:

1. **Next up.** Add an inspection mode (`--verbose`/`--all` flag) to the
   Candidate Analysis Engine, showing every package's full risk/reason/
   recommendation/confidence individually instead of the default summary +
   actionable-candidates-only view.
2. Implement actual debloating actions (e.g. removing known-safe optional
   packages), each requiring explicit confirmation and each reversible,
   per the safety philosophy in [README.md](README.md). The detection
   engine's compatibility checks are the gate this work will run behind,
   and the candidate analysis and safety validation from v0.4.0/v0.5.0 are
   the starting point for identifying removal candidates.
3. Support additional Zorin OS versions beyond 18.1.
4. Support other distributions.

None of the above is designed or scheduled — this list exists only to record
direction, not commitments.
