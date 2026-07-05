# Roadmap

For the current version and implementation status, see [README.md](README.md).

## Done

- Read-only detection engine (v0.2.0): system inspection, Zorin OS 18.1
  compatibility validation, and a PASS/FAIL report. See
  [README.md](README.md) for details.

## Planned, unscheduled

In rough priority order:

1. **Next up.** Implement actual debloating actions (e.g. removing
   known-safe optional packages), each requiring explicit confirmation and
   each reversible, per the safety philosophy in [README.md](README.md).
   The detection engine's compatibility checks are the gate this work will
   run behind.
2. Support additional Zorin OS versions beyond 18.1.
3. Support other distributions.

None of the above is designed or scheduled — this list exists only to record
direction, not commitments.
