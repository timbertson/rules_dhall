# Some old code...

def _toolchain_impl(ctx):
  ctx.download(
      "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/" + ctx.attr.version,
      output = "release.json")
  # print(ctx.path(""))
  json = ctx.read("release.json")

  build_lines = [
    'package(default_visibility = ["//visibility:public"])',
    'toolchain_type(name = "toolchain_type")',
    'load("dhall.bzl", "dhall_toolchain")',
  ]
  workspace_lines = [
    # 'load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")',
  ]

  for (platform, arch), impls in extract_urls(json).items():
    key='%s-%s' % (platform, arch)
    build_lines.extend([
      'dhall_toolchain(',
      '  name="dhall-impl-%s",' % (key,),
      '  bin_dirs=[',
    ])
    for tool, url in impls.items():
      repo = "dhall-bin-%s-%s" % (key, tool)
      build_lines.extend([
          '    "@%s//:files",' % repo
      ])
      workspace_lines.extend([
        'http_archive(',
        '  name="dhall-bin-%s-%s",' % (key, tool),
        '  url="%s",' % (url,),
        """  build_file_content='filegroup(name="files", srcs=glob(["**/*"]), visibility = ["//visibility:public"])',""",
        ')'
      ])
    build_lines.extend([
      '  ]',
      ')',
    ])

    build_lines.extend([
      'toolchain(',
      '  name="dhall-%s",' % key,
      '  toolchain="dhall-impl-%s",' % key,
      '  toolchain_type=":toolchain_type",',
    ])
    constraints = [
      '    "@platforms//os:%s",' % platform,
      '    "@platforms//cpu:%s",' % arch,
    ]
    build_lines.extend([
      '  exec_compatible_with = [',
    ])
    build_lines.extend(constraints)
    build_lines.extend([
      '  ],',
      '  target_compatible_with = [',
    ])
    build_lines.extend([
      '  ],',
      ')'
    ])

  # SETUP for loading this toolchain from outside of itself
  setup_lines = workspace_lines[:]
  setup_lines.extend([
    'native.register_toolchains('
  ])
  for (platform, arch), impls in extract_urls(json).items():
    key='%s-%s' % (platform, arch)
    setup_lines.append('"@dhall_toolchain//:dhall-%s",' % key)
  setup_lines.extend([ ')' ])

  ## WORKSPACE for having the toolchain within the generated repo (probably not needed, just for testing)
  #workspace_lines.extend([
  #  'register_toolchains('
  #])
  #for (platform, arch), impls in extract_urls(json).items():
  #  key='%s-%s' % (platform, arch)
  #  workspace_lines.append('":dhall-%s",' % key)
  #workspace_lines.extend([ ')' ])

  ctx.file("setup.bzl", """
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
def init():
""" + "    " + "\n    ".join(setup_lines))

  # TODO move this up top when we remove setup / workspace
  # workspace_lines = ['load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")'] + workspace_lines
  #
  # ctx.file("WORKSPACE", "\n".join(workspace_lines))

  ctx.file("BUILD", "\n".join(build_lines))
  ctx.template("dhall.bzl", Label("//toolchain:dhall.bzl"))

_dhall_toolchain = repository_rule(
    implementation=_toolchain_impl,
    local = False,
    attrs = {"version": attr.string(mandatory=True)},
)

def dhall_toolchain(version):
  _dhall_toolchain(
      name = "dhall_toolchain",
      version = version,
  )
