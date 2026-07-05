# ZorinTrim

A debloating tool for **Zorin OS 18.1**.

## Status

Current version: **0.5.0**, a read-only detection engine with a package
intelligence layer, a candidate analysis engine, and a safety validation
engine. `zorintrim.sh` inspects the system, checks it against ZorinTrim's
supported target (Zorin OS 18.1), and prints a report — it does not yet
remove or change anything.

The report covers:

- System information: OS, distribution, Zorin OS version, Ubuntu base
  version, kernel version, CPU architecture, total/available RAM, available
  disk space, and internet connectivity
- Privilege status: whether the script is running as root and whether
  `sudo` is available
- Compatibility checks (✔/✘): distribution is Zorin OS, version is 18.1,
  and `apt`/`dpkg` are available
- Package categories: installed packages classified into Games, Office,
  Multimedia, Internet, Utilities, Development, and System/Essential,
  based on each package's Debian section and priority. A package is only
  counted under a category when the classification is unambiguous —
  anything else is counted as Uncategorized rather than guessed at
- Candidate analysis: every installed package is assessed for **risk**
  (CRITICAL/HIGH/MEDIUM/LOW) and given exactly one **recommendation**
  (`DO NOT REMOVE`, `KEEP (CORE)`, `KEEP`, `REVIEW`, or `OPTIONAL`). Risk
  combines several independent, deterministic signals — dpkg's own
  `Essential` flag and `required`/`important` `Priority` (Debian's own
  authoritative facts, so these alone reach CRITICAL), `standard` priority,
  whether a package is directly depended on by an installed desktop
  metapackage, and its package category. No signal decides the outcome
  alone, and no package names are hardcoded. Uncertain (Uncategorized)
  packages are never treated as safe to remove
- Safety validation: every recommendation is explainable. Each signal that
  fired is recorded as its own piece of evidence, and every package also
  gets a **confidence** level (HIGH/MEDIUM/LOW) reflecting how much of that
  evidence agrees. Uncategorized packages — where the underlying
  classification itself is unreliable — always get LOW confidence, which
  the recommendation logic already treats conservatively (e.g. a
  MEDIUM-risk Uncategorized package is recommended `KEEP`, not `REVIEW`).
  A fully optional (LOW risk) package explicitly states the absence of
  protective signals (non-base-system priority, no metapackage dependency)
  as corroborating evidence rather than leaving it unsaid. Confidence is
  never inferred by guessing — only from signals already computed for risk.
  The report presents this with progressive disclosure: a summary of
  counts by risk, recommendation, and confidence; a boxed card for each
  LOW/MEDIUM ("actionable") package showing its risk, recommendation,
  confidence, and full bulleted evidence; and counts only for HIGH/CRITICAL
  ("protected") packages — this is classification and analysis only;
  ZorinTrim does not remove anything yet
- A final support status (SUPPORTED/UNSUPPORTED)

Informational items (RAM, disk, kernel, architecture, internet, privilege
status, Ubuntu base, package categories, candidate analysis, safety
validation) are reported for visibility only and never affect the support
status. This release makes no changes to the system under any
circumstances — no packages are installed, removed, or configured, and no
files outside the repository are touched.

## Scope

ZorinTrim targets **Zorin OS 18.1 only**. There is no support for other
distributions or other Zorin OS versions at this time. See
[ROADMAP.md](ROADMAP.md) for future plans.

## Safety philosophy

- Essential system packages are never removed.
- Every destructive operation must be reversible.
- Default behavior is always conservative.
- Any potentially dangerous action requires explicit user confirmation.

These principles apply to all current and future functionality, not just what
exists today.

## Usage

From inside this repository:

```bash
bash zorintrim.sh
```

## License

[MIT](LICENSE)
