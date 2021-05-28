DhallInfo = provider(
    doc = "Dhall binaries",
    # TODO rename binaries
    fields = ["bin_dirs"],
)

def _dhall_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        dhall = DhallInfo(bin_dirs = ctx.attr.bin_dirs),
    )
    return [toolchain_info]

dhall_toolchain = rule(
    implementation = _dhall_toolchain_impl,
    attrs = {
        "bin_dirs": attr.label_list(mandatory=True),
    },
)
