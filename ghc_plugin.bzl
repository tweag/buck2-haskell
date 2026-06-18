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
    ":link_info.bzl",
    "HaskellLinkInfo",
)
load(
    ":toolchain.bzl",
    "HaskellToolchainLibrary",
)
load(
    "@prelude//linking:link_info.bzl",
    "LinkStyle",
)

# Provider carrying GHC plugin metadata.
GhcPluginInfo = provider(
    fields = {
        "module": provider_field(str),
        # Regular haskell_library deps (provide HaskellLibraryProvider).
        "deps": provider_field(list[Dependency]),
        # Toolchain library dep names (provide HaskellToolchainLibrary).
        "toolchain_deps": provider_field(list[str]),
        "tools": provider_field(list[Dependency]),
        "plugin_opts": provider_field(list[str]),
    },
)

def ghc_plugin_impl(ctx: AnalysisContext) -> list[Provider]:
    """Implementation of the ghc_plugin rule."""
    lib_deps = []
    toolchain_dep_names = []
    for dep in ctx.attrs.deps:
        if dep.get(HaskellLibraryProvider) != None:
            lib_deps.append(dep)
        elif dep.get(HaskellToolchainLibrary) != None:
            toolchain_dep_names.append(dep[HaskellToolchainLibrary].name)
        else:
            fail(
                "ghc_plugin '{}': dependency '{}' does not provide " +
                "HaskellLibraryProvider or HaskellToolchainLibrary. " +
                "Plugin deps must be haskell_library or " +
                "haskell_toolchain_library targets.".format(
                    ctx.label.name,
                    dep.label,
                ),
            )

    return [
        DefaultInfo(),
        GhcPluginInfo(
            module = ctx.attrs.module,
            deps = lib_deps,
            toolchain_deps = toolchain_dep_names,
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
    # Handle regular haskell_library deps.
    for dep in info.deps:
        lib_provider = dep[HaskellLibraryProvider]
        lib_info = lib_provider.lib[link_style]
        args.add("-plugin-package", lib_info.id)
        # GHC needs to load the plugin module's .hi files at startup when
        # -fplugin is used. Declare them as hidden inputs so Buck2
        # materializes them before the compile action runs.
        for profiling_enabled, ifaces in lib_info.interfaces.items():
            args.add(cmd_args(hidden = ifaces))
        for profiling_enabled, objs in lib_info.objects.items():
            args.add(cmd_args(hidden = objs))
        # Register package DBs and libs for this dep AND all its transitive
        # deps. GHC needs all transitive deps available to satisfy the plugin
        # package's dependency chain.
        if HaskellLinkInfo in dep:
            link_info = dep[HaskellLinkInfo]
            tset = link_info.info[link_style]
            args.add(cmd_args(tset.project_as_args("package_db"), prepend = "-package-db"))
            args.add(cmd_args(hidden = tset.project_as_args("libs")))
            # GHC needs transitive interface files when loading the plugin
            # module (e.g. if the plugin re-exports from a dependency).
            args.add(cmd_args(hidden = tset.project_as_args("interfaces")))
            # GHC loads plugins dynamically regardless of the consumer's link
            # style. Ensure shared libs are materialized for all transitive
            # deps.
            if link_style != LinkStyle("shared"):
                shared_tset = link_info.info.get(LinkStyle("shared"))
                if shared_tset:
                    args.add(cmd_args(hidden = shared_tset.project_as_args("libs")))
        else:
            args.add("-package-db", lib_info.db)
            args.add(cmd_args(hidden = lib_info.libs))
            if link_style != LinkStyle("shared"):
                shared_lib_info = lib_provider.lib.get(LinkStyle("shared"))
                if shared_lib_info:
                    args.add(cmd_args(hidden = shared_lib_info.libs))
    # Handle haskell_toolchain_library deps. Their package DBs are registered
    # by the compilation flow; we only need to tell GHC to use the package as
    # a plugin.
    for name in info.toolchain_deps:
        args.add("-plugin-package", name)
    args.add("-fplugin={}".format(info.module))
    for opt in info.plugin_opts:
        args.add("-fplugin-opt={}:{}".format(info.module, opt))

PluginParams = record(
    # cmd_args for global plugins (from ctx.attrs.plugins), or None
    unit = field(cmd_args),
    # dict mapping source file to cmd_args for per-module plugins
    srcs = field(dict[typing.Any, cmd_args]),
    # list[RunInfo] for global plugin tools
    global_tool_paths = field(list[RunInfo]),
    # dict mapping source file to list[RunInfo] for per-module plugin tools
    srcs_tool_paths = field(dict[typing.Any, list[RunInfo]]),
    # list[str] toolchain library names needed by plugins
    plugin_toolchain_deps = field(list[str]),
)

def compute_plugin_flags(ctx: AnalysisContext, link_style) -> PluginParams:
    """
    Compute both unit-level and per-source plugin flags for a given link style.
    """
    unit = get_plugin_flags(ctx, link_style)
    srcs = {}
    srcs_plugin_modules = {}
    global_tool_paths = []
    srcs_tool_paths = {}
    plugin_toolchain_deps = []

    for plugin_dep in getattr(ctx.attrs, "plugins", []):
        info = plugin_dep[GhcPluginInfo]
        for tool in info.tools:
            global_tool_paths.append(tool[RunInfo])
        plugin_toolchain_deps.extend(info.toolchain_deps)

    if getattr(ctx.attrs, "srcs_plugins", None):
        for src, plugin_list in ctx.attrs.srcs_plugins.items():
            flags = cmd_args()
            tools = []
            for plugin_dep in plugin_list:
                plugin_info = plugin_dep[GhcPluginInfo]
                flags.add(get_plugin_flags(ctx, link_style, plugin_info = plugin_info))
                for tool in plugin_info.tools:
                    tools.append(tool[RunInfo])
                plugin_toolchain_deps.extend(plugin_info.toolchain_deps)
            srcs[src] = flags
            if tools:
                srcs_tool_paths[src] = tools

    return PluginParams(
        unit = unit,
        srcs = srcs,
        global_tool_paths = global_tool_paths,
        srcs_tool_paths = srcs_tool_paths,
        plugin_toolchain_deps = plugin_toolchain_deps,
    )

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
    Validate plugin attributes: `srcs_plugins` is not used with non-incremental builds.
    Produces an error if validation fails.
    """
    srcs_plugins = getattr(ctx.attrs, "srcs_plugins", {})
    incremental = getattr(ctx.attrs, "incremental", True)
    if srcs_plugins and not incremental:
        fail(
            "Target '{}' uses 'srcs_plugins' with 'incremental = False'. " +
            "Per-module plugins require incremental builds because non-incremental " +
            "mode (ghc --make) compiles all modules together and cannot apply " +
            "different plugin flags per module. Use 'plugins' for global plugin " +
            "support or set 'incremental = True'.".format(ctx.label),
        )

