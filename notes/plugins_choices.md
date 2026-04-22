# GHC Plugin Support — Technical Report

## Overview

This report documents the implementation of GHC compiler plugin support for
the `buck2-haskell` rules, as specified in `plugins_spec.md`. The
implementation introduces a `ghc_plugin` rule and integrates plugin flags into
the existing compilation pipeline.

## Technical Choices

### 1. Plugin flags are compilation-only, not metadata-only

**Decision:** Plugin flags (`-fplugin`, `-plugin-package`, `-package-db`) are
passed to the compilation step but **not** to the metadata step
(`target_metadata` / `ghc -M`).

**Reason:** The metadata step runs `ghc -M` to discover module import
dependencies. At this stage, plugin library artifacts (`.hi` files) may not yet
be compiled. Passing plugin flags to `ghc -M` causes failures because GHC
eagerly loads the plugin module, which requires its `.hi` files to exist. Since
plugins don't affect the module dependency graph, omitting them from the
metadata step is safe and necessary.

### 2. Hidden artifact tracking for plugin dependencies

**Decision:** When computing plugin flags, the plugin library's interface
files, object files, and library artifacts are added as `hidden` inputs to the
`cmd_args`.

**Reason:** GHC loads plugin modules at startup when `-fplugin` is specified.
The plugin's `.hi` files are referenced from its package DB but are not
directly on the GHC command line. Without tracking them as hidden inputs, Buck2
would not materialize them before running the compile action, causing "file not
found" errors. Adding them as `hidden` ensures Buck2's dependency graph
correctly orders the actions.

### 3. Dual-mode `get_plugin_flags` API

**Decision:** `get_plugin_flags` supports two calling modes: (1) with a
context to compute flags for all global plugins, and (2) with a specific
`plugin_info` to compute flags for a single plugin.

**Reason:** Global plugins (`plugins` attr) compute all plugin flags at once
for the unit level. Per-module plugins (`srcs_plugins` attr) need flags
computed for each source file's plugin list individually. A single function
with a mode parameter avoids code duplication while serving both use cases.

### 4. Per-module plugin flags via `srcs_plugin_flags` dict

**Decision:** The `_DynamicDoCompileOptions` record carries a
`srcs_plugin_flags` dictionary mapping sources to their per-module plugin
flags. In `_compile_incr`, each module's source is looked up in this dict to
add module-specific plugin flags.

**Reason:** This follows the existing pattern used by `sources_deps` and
`srcs_envs`, which already map source files to per-module data. Using the same
pattern makes the implementation consistent and leverages the existing
infrastructure in `_compile_module`.

### 5. Mutual exclusion of `plugins` and `srcs_plugins`

**Decision:** Validation is performed at the beginning of each rule
implementation (`haskell_library_impl`, `_haskell_executable`). If both
attributes are non-empty, a `fail()` is called with a clear error message.

**Reason:** Per the spec, using both `plugins` (global) and `srcs_plugins`
(per-module) is an error. Early validation prevents this confusion. The check
uses `getattr` with defaults to safely handle rules that may not have both
attributes.

### 6. Mutual exclusion of `srcs_plugins` and `incremental = False`

**Decision:** Validation also checks that `srcs_plugins` is not used together
with  non-incremental mode, where `fail()` is called with an informative error
message.

**Reason:** Non-incremental mode invokes GHC once for all modules. There is no
mechanism to apply different flags per module, so the `srcs_plugins` attribute is
meaningful only in incremental mode.

### 7. `GhcPluginInfo` provider design

**Decision:** The `GhcPluginInfo` provider stores `module` (str), `deps`
(list[Dependency]), `tools` (list[Dependency]), and `plugin_opts` (list[str]).
The `deps` field uses `providers = [HaskellLibraryProvider]` in the attribute
definition to enforce type safety at the rule level.

**Reason:** Storing raw dependencies rather than pre-computed flags allows the
consumer to compute flags appropriate for its own link style. This is necessary
because the same plugin may be used by targets with different link styles
(static vs shared), and the package DB path varies by link style.

### 8. Expected-failure tests in a self-contained package

**Decision:** Tests for error conditions (mutual exclusion, bad deps,
srcs_plugins + non-incremental, ghci, haddock) are placed in a separate
`expected_failures/` package at the repo root, outside `tests/`. A shell
script (`tests/plugins/test_expected_failures.sh`) invokes `buck build` on
each target, verifies the build fails, and checks that the error message
contains an expected substring. The script is wrapped in an `sh_test` target.

**Reason:** Targets that are expected to fail at analysis time cannot live
under `tests/` because `buck test 'buck2-haskell//tests/...'` discovers all
targets in the recursive pattern. Even though the expected-failure targets are
not test rules, Buck2 still analyzes them when evaluating the pattern, and
analysis failures count as build failures. Moving them to `expected_failures/`
at the repo root keeps them out of the standard test pattern.

The `expected_failures/` package is self-contained: it defines its own
toolchain libraries (`base`, `ghc`), its own `NoopPlugin.hs`, and its own
`noop_plugin` target. This avoids visibility issues — targets under `tests/`
have `visibility = ["//tests/..."]`, which does not include `//expected_failures/`.

The shell script (run as `sh_test`) calls `buck build` for each target and
checks the output with `grep -qF`. This is a nested Buck invocation (buck
build inside buck test). The expected error substrings are
chosen to be specific enough to avoid false positives:
- `"mutually exclusive"` — not just the word from the target name
- `"HaskellLibraryProvider"` — the provider name from Buck2's error
- `"Per-module plugins require incremental"` — avoids matching the target name
- `"GHC binary path"` — actual ghci failure message
- `"already used by another action"` — actual haddock failure message

### 9. Plugin tools automatically injected into compilation PATH

**Decision:** Plugin tools (from `ghc_plugin.tools`) provide `RunInfo` and
are automatically merged into the compilation `external_tool_paths`. This is
done via `_get_all_plugin_tool_paths()` in `haskell.bzl` which collects
`RunInfo` from all plugins (both global and per-module), and the `compile()`
function in `compile.bzl` accepts an `extra_tool_paths` parameter that is
merged with `external_tool_paths`.

**Reason:** The `ghc_wrapper.py` script accepts `--bin-exe=<path>` arguments
and adds each executable's directory to `PATH`. By injecting plugin tool
`RunInfo` into this mechanism, the tool binaries become available on `PATH`
during compilation. This is essential for plugins like the test `Plugin.hs`
which invokes tools via `readProcess` — without the tool on `PATH`, the
plugin fails at compile time. Unlike rules_haskell which uses `$(location)`
macro expansion for absolute tool paths, buck2-haskell uses PATH-based
discovery, so the plugin finds tools by name rather than by absolute path.

### 10. Compiler flags come after plugin opts in GHC invocation

**Decision:** In both `unit_ghc_args()` (incremental mode) and `compile_args()`
(non-incremental mode) in `compile.bzl`, `compiler_flags` are now added to the
GHC command line AFTER `plugin_flags`.

**Reason:** GHC processes `-fplugin-opt` flags in order. If `compiler_flags`
were inserted between plugin flags (e.g., between `-fplugin=Foo` and
`-fplugin-opt=Foo:bar`), it could interfere with how GHC associates options
with plugins. More importantly, users should be able to override
plugin behavior via `compiler_flags`, which only works if they appear later
in the command line. The `OrderPlugin` test enforces this: it verifies that
`plugin_opts = ["alpha", "beta", "gamma"]` arrive in exactly that order, which
would fail if `compiler_flags` were interleaved.

### 11. `srcs_plugins` requires incremental builds

**Decision:** `validate_plugins_attrs()` in `ghc_plugin.bzl` now also checks
that `srcs_plugins` is not used with `incremental = False`, raising a clear
error message.

**Reason:** In non-incremental mode, GHC receives all source files in a single
`ghc --make` invocation. There is no mechanism to apply different plugin flags
to different modules in this mode. Rather than silently applying all plugins to
all modules (which violates the per-module intent), we fail early with an
explanatory message guiding the user to either use global `plugins` or enable
incremental builds.

## Test files

- **`buck2-haskell/tests/plugins/`** — Complete test suite:
  - `Plugin.hs` — Real GHC plugin that invokes a tool via `readProcess` and replaces string literals (exercises `tools` and `plugin_opts`)
  - `PluginTool.hs` — Trivial binary invoked by `Plugin.hs` at compile time
  - `PluginLib.hs` — Library compiled with the real plugin
  - `PluginMain.hs` — Binary/test that verifies string replacement at runtime
  - `TestPluginLib.hs` — Consumer test for library targets compiled with the plugin
  - `OrderPlugin.hs` — Plugin that verifies `plugin_opts` arrive as `["alpha", "beta", "gamma"]` (flag ordering test)
  - `OrderMain.hs` — Minimal main for order plugin test
  - `Lib.hs`, `Main.hs` — Modules for order plugin library tests
  - `test_expected_failures.sh` — Shell script testing expected-failure scenarios
  - `BUCK` — Test targets covering all combinations in the spec

- **`buck2-haskell/expected_failures/`** — Self-contained expected-failure targets:
  - `BUCK` — 5 targets that are expected to fail at analysis time
  - `NoopPlugin.hs`, `Lib.hs` — Local sources to avoid cross-package visibility issues

## Test Matrix

Every test uses a plugin that **verifies its execution**: the real plugin
invokes a tool and replaces string literals (compile-time and runtime checks),
and the order plugin asserts option ordering (compile-time check). There are
no noop plugin tests — a noop plugin cannot guarantee it was actually loaded.

The test suite in `buck2-haskell/tests/plugins/` covers:

| Rule type | Plugin | Mode | Link style | Target name |
|---|---|---|---|---|
| `haskell_library` | real (tools+opts) | global | any | `lib_real_plugin` |
| `haskell_library` | real (tools+opts) | srcs_plugins | any | `lib_srcs_real_plugin` |
| `haskell_library` | order (flag ordering) | global | any | `lib_order_plugin` |
| `haskell_library` consumer | real (tools+opts) | — | static | `ht_lib_real_plugin` |
| `haskell_library` consumer | real (tools+opts) | — | static | `ht_lib_srcs_real_plugin` |
| `haskell_library` consumer | order (flag ordering) | — | static | `ht_lib_order_plugin` |
| `haskell_binary` | real (tools+opts) | global | static | `bin_real_plugin_static` |
| `haskell_binary` | real (tools+opts) | global | shared | `bin_real_plugin_shared` |
| `haskell_binary` | real (tools+opts) | srcs_plugins | static | `bin_srcs_real_plugin_static` |
| `haskell_binary` | real (tools+opts) | srcs_plugins | shared | `bin_srcs_real_plugin_shared` |
| `haskell_binary` | order (flag ordering) | global | static | `bin_order_plugin` |
| `haskell_test` | real (tools+opts) | global | static | `ht_real_plugin_static` |
| `haskell_test` | real (tools+opts) | global | shared | `ht_real_plugin_shared` |
| `haskell_test` | real (tools+opts) | srcs_plugins | static | `ht_srcs_real_plugin_static` |
| `haskell_test` | real (tools+opts) | srcs_plugins | shared | `ht_srcs_real_plugin_shared` |
| `haskell_test` | order (flag ordering) | global | static | `ht_order_plugin` |

Tests marked **real (tools+opts)** use `Plugin.hs` which invokes a tool at
compile time and replaces string literals. They fail if:
- The tool binary is not available on PATH during compilation
- The plugin_opts are not passed to the plugin
- The Core-to-Core pass does not execute

Tests marked **order (flag ordering)** use `OrderPlugin.hs` which verifies
that `plugin_opts` arrive in the expected order `["alpha", "beta", "gamma"]`.

### Expected-failure tests (in `expected_failures/`)

| Error condition | Target name | Expected error substring |
|---|---|---|
| `plugins` + `srcs_plugins` both set | `err_mutual_exclusion` | `"mutually exclusive"` |
| `ghc_plugin.deps` is not a haskell_library | `err_bad_deps` | `"HaskellLibraryProvider"` |
| `srcs_plugins` + `incremental = False` | `err_srcs_plugins_non_incremental` | `"Per-module plugins require incremental"` |
| `haskell_ghci` broken (no GHC binary) | `err_ghci_plugin` | `"GHC binary path"` |
| `haskell_haddock` broken (artifact collision) | `err_haddock_plugin` | `"already used by another action"` |

