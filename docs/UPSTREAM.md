# Upstream tracking

This branch (`stable`) is a Lua port of vMenu Enhanced and tracks upstream's `enhanced` branch.
The `original` branch tracks upstream's `legacy` branch instead, see [BRANCH-PLAN.md](BRANCH-PLAN.md).

Port from release tags (`enhanced-v*`), not every commit. Upstream lands dozens of commits a
week, and `develop` feeds `enhanced`, so a release tag is the first point worth porting.

## Pinned upstream

| | |
|---|---|
| Repo | https://github.com/tomgrobbe/vMenu |
| Branch | `enhanced` |
| Tag | `enhanced-v1.0.3` |
| Commit | `ee284020fadf00e58199b7ddb02746bb5b06f901` |
| Date | 2026-10-02 |

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
