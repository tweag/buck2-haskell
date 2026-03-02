def _ghc_proxy_impl(ctx: AnalysisContext) -> list[Provider]:
    cmd = cmd_args(ctx.attrs.exe[RunInfo])
    cmd.add(ctx.attrs.args)
    return [DefaultInfo(), RunInfo(args = cmd)]

ghc_proxy = rule(
    impl = _ghc_proxy_impl,
    attrs = {
        "exe": attrs.dep(providers = [RunInfo]),
        "args": attrs.list(attrs.arg(), default = []),
    },
)
