# ZorinTrim

A debloating tool for **Zorin OS 18.1**.

## Status

Current version: **0.1.0**, a bootstrap release. `zorintrim.sh` checks that
it's running on a supported system and does not yet remove or change
anything.

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
