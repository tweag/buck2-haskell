# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under both the MIT license found in the
# LICENSE-MIT file in the root directory of this source tree and the Apache
# License, Version 2.0 found in the LICENSE-APACHE file in the root directory
# of this source tree.

"""
GHC compiler plugin support for buck2-haskell.
"""

load(
    ":library_info.bzl",
    "HaskellLibraryProvider",
)
load(
    "@prelude//linking:link_info.bzl",
    "LinkStyle",
)

# Provider carrying GHC plugin metadata.
GhcPluginInfo = provider(
    fields = {
        "module": provider_field(str),
        "deps": provider_field(list[Dependency]),
        "tools": provider_field(list[Dependency]),
        "plugin_opts": provider_field(list[str]),
    },
)

def ghc_plugin_impl(ctx: AnalysisContext) -> list[Provider]:
    """Implementation of the ghc_plugin rule."""
    # Validate that all deps provide HaskellLibraryProvider
    for dep in ctx.attrs.deps:
        if dep.get(HaskellLibraryProvider) == None:
            fail(
                "ghc_plugin '{}': dependency '{}' does not provide HaskellLibraryProvider. " +
                "Plugin deps must be haskell_library targets.".format(
                    ctx.label.name,
                    dep.label,
                ),
            )

    return [
        DefaultInfo(),
        GhcPluginInfo(
            module = ctx.attrs.module,
            deps = ctx.attrs.deps,
            tools = ctx.attrs.tools,
            plugin_opts = ctx.attrs.plugin_opts,
        ),
    ]

def get_plugin_flags(ctx, link_style, plugin_info = None) -> cmd_args:
    """
    Compute GHC compiler flags for GHC plugins.

    Can be called in two modes:
    1. With a context: `get_plugin_flags(ctx, link_style)` - computes flags for all
       plugins in `ctx.attrs.plugins`.
    2. With a specific plugin_info: `get_plugin_flags(ctx, link_style, plugin_info = info)` -
       computes flags for a single plugin.

    For each plugin, the following flags are produced:
      - `-package-db <db>` and `-plugin-package <id>` for each dep
      - `-fplugin=<module>`
      - `-fplugin-opt=<module>:<opt>` for each option

    Args:
        ctx: An AnalysisContext
        link_style: The link style to use when looking up library info.
        plugin_info: Optional single GhcPluginInfo to compute flags for.

    Returns:
        cmd_args with all plugin-related GHC flags.
    """
    args = cmd_args()

    if plugin_info != None:
        # Single plugin mode
        _add_plugin_flags(args, plugin_info, link_style)
        return args

    # Context mode: get all plugins from ctx.attrs.plugins
    plugins = getattr(ctx.attrs, "plugins", [])
    for plugin_dep in plugins:
        info = plugin_dep[GhcPluginInfo]
        _add_plugin_flags(args, info, link_style)
    return args

def _add_plugin_flags(args, info, link_style):
    """Add GHC flags for a single plugin to the given cmd_args."""
    for dep in info.deps:
        lib_provider = dep[HaskellLibraryProvider]
        lib_info = lib_provider.lib[link_style]
        args.add("-package-db", lib_info.db)
        args.add("-plugin-package", lib_info.id)
        # GHC needs to load the plugin module's .hi files at startup when
        # -fplugin is used. Declare them as hidden inputs so Buck2
        # materializes them before the compile action runs.
        for profiling_enabled, ifaces in lib_info.interfaces.items():
            args.add(cmd_args(hidden = ifaces))
        for profiling_enabled, objs in lib_info.objects.items():
            args.add(cmd_args(hidden = objs))
        args.add(cmd_args(hidden = lib_info.libs))
        # GHC loads plugins dynamically regardless of the consumer's link
        # style. The package DB's library-dirs includes the shared lib
        # directory even for static builds, so the .so must be materialized.
        if link_style != LinkStyle("shared"):
            shared_lib_info = lib_provider.lib.get(LinkStyle("shared"))
            if shared_lib_info:
                args.add(cmd_args(hidden = shared_lib_info.libs))
    args.add("-fplugin={}".format(info.module))
    for opt in info.plugin_opts:
        args.add("-fplugin-opt={}:{}".format(info.module, opt))

def compute_plugin_flags(ctx: AnalysisContext, link_style) -> struct:
    """
    Compute both unit-level and per-source plugin flags for a given link style.

    Returns a struct with:
        unit: cmd_args for global plugins (from ctx.attrs.plugins), or None
        srcs: dict mapping source file to cmd_args for per-module plugins
    """
    unit = get_plugin_flags(ctx, link_style)
    srcs = {}
    if getattr(ctx.attrs, "srcs_plugins", None):
        for src, plugin_list in ctx.attrs.srcs_plugins.items():
            flags = cmd_args()
            for plugin_dep in plugin_list:
                plugin_info = plugin_dep[GhcPluginInfo]
                flags.add(get_plugin_flags(ctx, link_style, plugin_info = plugin_info))
            srcs[src] = flags

    return struct(unit = unit, srcs = srcs)

def get_plugin_tool_paths(plugins: list[Dependency]) -> list[RunInfo]:
    """Extract RunInfo tool paths from all plugins."""
    tools = []
    for plugin_dep in plugins:
        info = plugin_dep[GhcPluginInfo]
        for tool in info.tools:
            tools.append(tool[RunInfo])
    return tools

def validate_plugins_attrs(ctx: AnalysisContext):
    """
    Validate plugin attribute constraints:
    1. `plugins` and `srcs_plugins` are not both specified.
    2. `srcs_plugins` is not used with non-incremental builds.
    Produces a build error if any constraint is violated.
    """
    plugins = getattr(ctx.attrs, "plugins", [])
    srcs_plugins = getattr(ctx.attrs, "srcs_plugins", {})
    if plugins and srcs_plugins:
        fail(
            "Target '{}' specifies both 'plugins' and 'srcs_plugins'. " +
            "These attributes are mutually exclusive. Use 'plugins' to enable " +
            "plugins globally for all modules, or 'srcs_plugins' to enable " +
            "plugins per-module, but not both.".format(ctx.label),
        )
    incremental = getattr(ctx.attrs, "incremental", True)
    if srcs_plugins and not incremental:
        fail(
            "Target '{}' uses 'srcs_plugins' with 'incremental = False'. " +
            "Per-module plugins require incremental builds because non-incremental " +
            "mode (ghc --make) compiles all modules together and cannot apply " +
            "different plugin flags per module. Use 'plugins' for global plugin " +
            "support or set 'incremental = True'.".format(ctx.label),
        )

