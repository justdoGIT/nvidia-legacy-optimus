# Repository Guidelines

## Project Structure & Module Organization

This repository is documentation- and script-driven. Top-level Markdown files hold user-facing guidance: `README.md` covers installation and usage, and `COMPATIBILITY.md` tracks known-good hardware. Runtime configuration snippets live in `configs/` for Bumblebee, Xorg, and `nvidia_drm`. Operational scripts live in `scripts/`, notably `inttf-nvidia-patcher.sh`, `nvidia-health-check.sh`, and `gpu-run`. Recovery and troubleshooting notes belong in `guides/`.

## Build, Test, and Development Commands

There is no compiled application or Makefile. Use the repository scripts directly:

- `bash scripts/inttf-nvidia-patcher.sh -v 390.157` downloads, patches, and repacks the NVIDIA `.run` installer.
- `bash scripts/nvidia-health-check.sh` verifies `nvidia-smi`, kernel modules, GLX wiring, and `optirun`.
- `bash -n scripts/*.sh` performs a basic Bash syntax check before submitting changes.
- `shellcheck scripts/*.sh` is recommended when available to catch quoting and portability issues.

For config changes, validate paths and filenames against the install steps in `README.md`.

## Coding Style & Naming Conventions

Use Bash for automation and keep scripts readable over clever. Match the existing style: 2-4 space indentation, lowercase function and variable names, and descriptive filenames such as `nvidia-health-check.sh`. Prefer explicit commands, quote variable expansions unless unquoted behavior is required, and keep user-facing output concise. Config files should preserve upstream syntax and comments.

## Testing Guidelines

Automated tests are not currently present. Every script change should include, at minimum, `bash -n` validation and a manual dry run on a non-production system where possible. For changes that affect install or recovery steps, update the relevant Markdown guide and record any confirmed hardware behavior in `COMPATIBILITY.md`.

## Commit & Pull Request Guidelines

Recent commits use short, repo-scoped subjects such as `nvidia-legacy: PCIe retrain wrapper for GT 720M`. Follow that pattern: `<scope>: <concise summary>`. Every commit must also be created with `git commit -s` so the message includes a `Signed-off-by:` trailer. Keep commits focused. Pull requests should explain the hardware or kernel scenario addressed, list any commands used for validation, and include terminal output or screenshots only when they clarify failures or recovery steps.

## Security & Configuration Notes

These scripts can modify kernel-module and Xorg-related system state. Do not hardcode host-specific paths beyond documented NVIDIA/Bumblebee locations, and call out any command that writes to `/etc`, `/usr/lib`, or bootloader configuration.
