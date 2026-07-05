# ZorinTrim

A debloating tool for **Zorin OS 18.1**.

## Status

Current version: **0.2.0**, a read-only detection engine. `zorintrim.sh`
inspects the system, checks it against ZorinTrim's supported target (Zorin
OS 18.1), and prints a report — it does not yet remove or change anything.

The report covers:

- System information: OS, distribution, Zorin OS version, Ubuntu base
  version, kernel version, CPU architecture, total/available RAM, available
  disk space, and internet connectivity
- Privilege status: whether the script is running as root and whether
  `sudo` is available
- Compatibility checks (PASS/FAIL): distribution is Zorin OS, version is
  18.1, and `apt`/`dpkg` are available
- A final support status (SUPPORTED/UNSUPPORTED)

Informational items (RAM, disk, kernel, architecture, internet, privilege
status, Ubuntu base) are reported for visibility only and never affect the
support status. This release makes no changes to the system under any
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
