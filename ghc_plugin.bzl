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

PluginFlags = record(
    # -plugin-package, and -package-db
    # We keep these flags separate per-plugin label to ensure that we can de-dup them
    pkg_flags = field(dict[Label, cmd_args]),
    # -fplugin and -fplugin-opt
    mod_flags = field(cmd_args),
    # hidden inputs (interface, object files, and libraries)
    hidden = field(cmd_args),
)

def pkg_flags_as_cmd_args(pkg_flags: dict[Label, cmd_args]) -> cmd_args:
    """Extract just the package-related flags from PluginFlags."""
    pkg_args = cmd_args()
    for pkg_arg in pkg_flags.values():
        pkg_args.add(pkg_arg)
    return pkg_args

def plugin_flags_as_cmd_args(plugin_flags: PluginFlags) -> cmd_args:
    """Flatten PluginFlags into a single cmd_args object."""
    return cmd_args(
        pkg_flags_as_cmd_args(plugin_flags.pkg_flags),
        plugin_flags.mod_flags,
        hidden = plugin_flags.hidden,
    )

def get_plugin_flags(ctx, link_style) -> PluginFlags:
    """
    Compute GHC compiler flags for all plugins in `ctx.attrs.plugins`.

    For each plugin, the following flags are produced:
      - `-package-db <db>` and `-plugin-package <id>` for each dep
      - `-fplugin=<module>`
      - `-fplugin-opt=<module>:<opt>` for each option

    Args:
        ctx: An AnalysisContext
        link_style: The link style to use when looking up library info.
    """
    pkg_flags = {}
    mod_flags = cmd_args()
    hidden = cmd_args()
    plugins = getattr(ctx.attrs, "plugins", [])
    for plugin_dep in plugins:
        pkg_args = cmd_args()
        info = plugin_dep[GhcPluginInfo]
        _add_plugin_flags(pkg_args, mod_flags, info, link_style)
        _add_plugin_hidden_inputs(hidden, info, link_style)
        pkg_flags[plugin_dep.label] = pkg_args
    return PluginFlags(
        pkg_flags = pkg_flags,
        mod_flags = mod_flags,
        hidden = hidden,
    )

def _add_plugin_hidden_inputs(args, info, link_style):
    """Add the hidden inputs for the given plugin info (interface and object
       files, and libraries).
    """
    # Handle regular haskell_library deps.
    for dep in info.deps:
        lib_provider = dep[HaskellLibraryProvider]
        lib_info = lib_provider.lib[link_style]
        # GHC needs to load the plugin module's .hi files at startup when
        # -fplugin is used. Declare them as hidden inputs so Buck2
        # materializes them before the compile action runs.
        for profiling_enabled, ifaces in lib_info.interfaces.items():
            args.add(ifaces)
        for profiling_enabled, objs in lib_info.objects.items():
            args.add(objs)
        # Register package DBs and libs for this dep AND all its transitive
        # deps. GHC needs all transitive deps available to satisfy the plugin
        # package's dependency chain.
        if HaskellLinkInfo in dep:
            link_info = dep[HaskellLinkInfo]
            tset = link_info.info[link_style]
            args.add(cmd_args(hidden = tset.project_as_args("libs")))
            # GHC needs transitive interface files when loading the plugin
            # module (e.g. if the plugin re-exports from a dependency).
            args.add(tset.project_as_args("interfaces"))
            # GHC loads plugins dynamically regardless of the consumer's link
            # style. Ensure shared libs are materialized for all transitive
            # deps.
            if link_style != LinkStyle("shared"):
                shared_tset = link_info.info.get(LinkStyle("shared"))
                if shared_tset:
                    args.add(shared_tset.project_as_args("libs"))
        else:
            args.add(lib_info.libs)
            if link_style != LinkStyle("shared"):
                shared_lib_info = lib_provider.lib.get(LinkStyle("shared"))
                if shared_lib_info:
                    args.add(shared_lib_info.libs)

def _add_plugin_flags(args, mod_args, info, link_style):
    """Add flags for the given plugin info"""
    # Handle regular haskell_library deps.
    for dep in info.deps:
        lib_provider = dep[HaskellLibraryProvider]
        lib_info = lib_provider.lib[link_style]
        args.add("-plugin-package", lib_info.id)
        # Register package DBs and libs for this dep AND all its transitive
        # deps. GHC needs all transitive deps available to satisfy the plugin
        # package's dependency chain.
        if HaskellLinkInfo in dep:
            link_info = dep[HaskellLinkInfo]
            tset = link_info.info[link_style]
            args.add(cmd_args(tset.project_as_args("package_db"), prepend = "-package-db"))
        else:
            args.add("-package-db", lib_info.db)

    # Handle haskell_toolchain_library deps. Their package DBs are registered
    # by the compilation flow; we only need to tell GHC to use the package as
    # a plugin.
    for name in info.toolchain_deps:
        args.add("-plugin-package", name)
    mod_args.add("-fplugin={}".format(info.module))
    for opt in info.plugin_opts:
        mod_args.add("-fplugin-opt={}:{}".format(info.module, opt))


PluginParams = record(
    # unit-level plugin flags for global plugins
    unit = field(PluginFlags),
    # dict mapping source file to plugin flags for per-module plugins
    srcs = field(dict[typing.Any, PluginFlags]),
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
            pkg_flags = {}
            mod_flags = cmd_args()
            hidden = cmd_args()
            tools = []
            for plugin_dep in plugin_list:
                pkg_args = cmd_args()
                plugin_info = plugin_dep[GhcPluginInfo]
                _add_plugin_flags(pkg_args, mod_flags, plugin_info, link_style)
                _add_plugin_hidden_inputs(hidden, plugin_info, link_style)
                for tool in plugin_info.tools:
                    tools.append(tool[RunInfo])
                plugin_toolchain_deps.extend(plugin_info.toolchain_deps)
                pkg_flags[plugin_dep.label] = pkg_args
            srcs[src] = PluginFlags(
                pkg_flags = pkg_flags,
                mod_flags = mod_flags,
                hidden = hidden,
            )
            if tools:
                srcs_tool_paths[src] = tools

    return PluginParams(
        unit = unit,
        srcs = srcs,
        global_tool_paths = global_tool_paths,
        srcs_tool_paths = srcs_tool_paths,
        plugin_toolchain_deps = plugin_toolchain_deps,
    )

def plugin_params_srcs_as_cmd_args(params: PluginParams, srcfile: typing.Any) -> cmd_args:
    """Get the plugin flags for a given source file."""
    if srcfile in params.srcs:
        return plugin_flags_as_cmd_args(params.srcs[srcfile])
    else:
        return cmd_args()

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

