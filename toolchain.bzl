DhallInfo = provider(
    doc = "Dhall binaries",
    # TODO rename binaries
    fields = ["binaries"],
)

def _dhall_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        dhall = DhallInfo(binaries = ctx.attr.binaries),
    )
    return [toolchain_info]

dhall_toolchain = rule(
    implementation = _dhall_toolchain_impl,
    attrs = {
        "binaries": attr.label(mandatory=True),
    },
)
