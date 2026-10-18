# Upstream tracking

This branch (`stable`) is a Lua port of vMenu Enhanced. Upstream develops it on `main` (the
`enhanced` branch stopped at enhanced-v1.0.3). The `original` branch tracks upstream's `legacy`
branch instead, see [BRANCH-PLAN.md](BRANCH-PLAN.md).

Port from release tags (`enhanced-v*`), not every commit. Upstream lands dozens of commits a
week, so a release tag is the first point worth porting. Upstream builds two flavors from one
tree: `src/Enhanced/` for FiveM Enhanced and `src/Legacy/` for FiveM Legacy. Port from
`src/Enhanced/` and `src/Shared/`, and read `src/Legacy/` when a feature behaves differently per
platform.

## Pinned upstream

| | |
|---|---|
| Repo | https://github.com/tomgrobbe/vMenu |
| Branch | `main` |
| Tag | `enhanced-v1.0.16` |
| Commit | `109cc5e5a505a342a3db6c7fc9e6284fbc31f8a5` |
| Date | 2026-10-16 |

## File to module map

The C# project to Lua module map lives in
[BRANCH-PLAN.md](BRANCH-PLAN.md#project-to-module-map) until the port settles. Inside a project,
one C# file maps to one Lua module with a snake_case name, in the same folder layout.

## Porting workflow

1. `pwsh scripts/upstream-diff.ps1` fetches upstream, diffs the pin against the head of the
   pinned branch, and lists the commits and changed files.
2. Port each hunk into the mapped module.
3. If a diff changes a permission, setting, event name, plugin protocol payload, or KVP save
   shape, update the matching spec first, then the code.
4. Bump the pin above to the new release tag.
