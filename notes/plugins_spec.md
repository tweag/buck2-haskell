## Plugin support for buck2-haskell

Plugin support follows the user interface of `rules_haskell` [1].

[1]: https://release.api.haskell.build/haskell/defs#ghc_plugin

There is a `ghc_plugin` rule that groups haskell libraries with metadata
necessary to use the library as a plugin.

The metadata for a plugin is specified in attributes of the `ghc_plugin` rule.
The attributes should include:

* `name`: A name for the target identifying the plugin.
* `deps`: A list of dependencies of the plugin. They should point to Haskell
  libraries which must provide the `HaskellLibraryProvider` provider. And which
  should provide the module in the `module` attribute.
* `module`: The name of the Haskell module that provides the plugin.
* `tools`: List of tools that must be available when using the plugin when
  building a module.
* `plugin_opts`: options for the plugin. They are fed to GHC before the
  `compiler_flags` attribute of dependent rules.

All attributes are required except for `tools` and `plugin_opts` which default
to an empty list.

The rules `haskell_library`, `haskell_binary`, `haskell_test`, and
`haskell_ghci`, in turn, provide a `plugin` attribute where plugins can be
provided.

Without further configuration, the plugin is enabled globally for all the
modules in the given unit. It is possible, though, to instead enable the plugin
per-module by using an attribute `srcs_plugins`, which analogously to
`src_deps`, allows to specify which plugins to enable for each module with an
entry in `srcs_plugins`. Modules without an entry in this dictionary don't have
the plugin enabled.

### Validations

Whenever the `srcs_plugins` attribute is specified on a rule:
* Likewise, an error should be produced if `srcs_plugins` is used and the build
  mode is non-incremental, where GHC does not provide a way to specify plugins
  per-module.

Finally, an error should be produced if other targets than Haskell libraries are
provided in the dependencies of `ghc_plugins`.

### Other considerations

When a unit or module depends on a target produced with `ghc_plugin` rule:
* `-plugin-package=dep` is given to the GHC compiler for every dependency in
  the `deps` attribute of the `ghc_plugin` rule,
* `-fplugin=<module>` is given to the GHC compiler where `<module>` is the name
  given in the `module` attribute of the `ghc_plugin` rule,
* `-fplugin-opt=<module>:<opt>` is given to the GHC compiler, where `<module>`
  is the name given in the `module` attribute of the `ghc_plugin` rule, and
  opt is each of the options in the attribute `plugin_opts` of the `ghc_plugin`
  rule.

### Testing notes

There are tests illustrating use of each of the combinations of `plugin` and
`srcs_plugins` together with the `tools` attribute, with `haskell_library`,
`haskell_binary`, `haskell_test`, and `haskell_ghci`, and with both
link styles `static` and `shared`, and with both build types `release` and
`debug`.

Moreover, there should be a tests rehearsing the validations of `srcs_plugins`
and the `ghc_plugin` rule.

Finally, there should be a test of producing documentation with haddock for
a `haskell_library` target that requires a plugin.

Each test describes briefly in comments what configuration it is trying to test.

All tests run and pass with
```
buck test buck2-haskell//tests/...
```
except for tests with haddock and ghci, which are not expected to pass at the
moment.

### Documentation notes

The documentation of the `ghc_plugin` rule describes how plugins are supported
and provides three configuration examples.
One of them illustrates the use of the `plugin` attribute. A second example
illustrates the use of the `srcs_plugins` attribute. A third example
illustrates the use of the `tools` attribute.

All three examples appear as tests in `buck2-haskell/tests/plugins`.
