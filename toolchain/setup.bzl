PLATFORMS = ['macos-x86_64', 'linux-x86_64', 'windows-x86_64']
TOOLCHAIN = '@dhall_toolchain//:toolchain_type'

# If a sha is present it improves caching (and security), unknown releases
# will be downloaded without integrity checks or caching
DIGESTS = {
    '1.38.0': '02ec9efce241bfcd1ea0a586d3020dc2c50dc65576a1ed6366faada6fcff5382',
    'dhall-1.38.0-macos-x86_64': 'f78d830731539087b2e35ed5d034b192052f973c1a60654983efd9562ddaad1d',
    'dhall-json-1.38.0-macos-x86_64': '1cd5e54a2a21a92d1c3c0831af3c14a86c2de1851a1e390c1b87c9abb5e8a000',
    'dhall-yaml-1.38.0-macos-x86_64': '33132b4d6f69c0c8e799a1fe9c7f8e19062917d71fff59365b0fe9dee5621546',
}

def extract_urls(json):
  # TODO JSON parser?

  # structure: (platform, arch): { tool: url }
  result = {}
  for line in json.split(","):
    line = line.strip("{, }[]")
    if "browser_download_url" in line:
      _,url = line.split(":", 1)
      url = url.strip('" ')
      # print(url)

      _, filename = url.rsplit("/", 1)
      # print(filename)
      filename, ext = filename.rsplit('.', 1)
      if filename.endswith('.tar'):
        # lob another one off
        filename, ext = filename.rsplit('.', 1)
      # print(filename)

      base, url_platform = filename.rsplit("-", 1)
      base, url_arch = base.rsplit("-", 1)
      base, url_version = base.rsplit("-", 1)
      key = (url_platform, url_arch)

      if base not in ['dhall', 'dhall-json', 'dhall-yaml']:
        continue

      # print(key)
      # print(base)
      if key not in result:
        result[key] = {}
      result[key][base] = url
  # print(repr(result))
  return result


# generate a repo with downloaded binaries for a specific platform
def _setup_impl(ctx):
  version = ctx.attr.version
  ctx.download(
      "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/" + version,
      output = "release.json",
      sha256 = DIGESTS.get(version) or '')
  json = ctx.read("release.json")

  build_lines = [
    'package(default_visibility = ["//visibility:public"])',
    'load("@dhall_toolchain//:dhall.bzl", "dhall_toolchain")',
  ]

  for (platform, arch), impls in extract_urls(json).items():
    key='%s-%s' % (platform, arch)
    if key != ctx.attr.platform:
      continue

    bin_dirs = []
    for tool, url in impls.items():
      digest_key = "%s-%s-%s" % (tool, version, key)
      digest = DIGESTS.get(digest_key)
      if digest == None:
        print("Note: no known digest for %s, add it to @rules_dhall/toolchain/setup.bzl for better caching" % digest_key)
      ctx.download_and_extract(url=url, output=tool, sha256=digest or '')
      build_lines.append('filegroup(name="%s", srcs=glob(["%s/bin/*"]))' % (tool, tool))
      bin_dirs.extend([
          '    ":%s",' % tool
      ])

    build_lines.extend([
      'dhall_toolchain(',
      '  name="dhall-impl-%s",' % (key,),
      '  bin_dirs=[',
    ] + bin_dirs + [
      '  ]',
      ')',
    ])

    constraints = [
      '    "@platforms//os:%s",' % platform,
      '    "@platforms//cpu:%s",' % arch,
    ]

    build_lines.extend([
      'toolchain(',
      '  name="dhall-%s",' % key,
      '  toolchain="dhall-impl-%s",' % key,
      '  toolchain_type="%s",' % TOOLCHAIN,
      '  exec_compatible_with = [',
    ] + constraints + [
      '  ],',
      '  target_compatible_with = [',
    ] + constraints + [
      '  ],',
      ')'
    ])

  ctx.file("BUILD", "\n".join(build_lines))

_setup_dhall = repository_rule(
    implementation=_setup_impl,
    local = False,
    attrs = {
        "version": attr.string(mandatory=True),
        "platform": attr.string(mandatory=True),
    },
)

# toolchain repo holds the common type & definition functions shared by
# each platform-specific repo
def _toolchain_repo_impl(ctx):
  ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
toolchain_type(name = "toolchain_type")
""")
  ctx.template("dhall.bzl", Label("//toolchain:dhall.bzl"))

_toolchain_repo = repository_rule(
    _toolchain_repo_impl,
)

# some parts from https://github.com/gregmagolan/rules_nodejs/blob/596018a96ed2d7f872609ee20ea65ce0b943dfac/internal/node/node_repositories.bzl
def os_name(rctx):
    os_name = rctx.os.name.lower()
    if os_name.startswith("mac os"):
        return PLATFORMS[0]
    elif os_name.startswith("linux"):
        return PLATFORMS[1]
    elif os_name.find("windows") != -1:
        return PLATFORMS[2]
    else:
        fail("Unsupported operating system: " + os_name)

# make an alias for @dhall_toolchain_PLATFORM
# so that we can conveniently register @dhall_toolchain_host as the single impl
# (we don't know what the host is in a .bzl file, we can only
# find it out from within a rule impl)
def _host_alias_impl(ctx):
    host_platform = os_name(ctx)
    platform = ctx.attr.platform or host_platform
    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
alias(name = "dhall", actual = "@dhall_toolchain_%s//:dhall-%s")
""" % (platform, platform))

_host_alias = repository_rule(
    _host_alias_impl,
    attrs = {
        "platform": attr.string(mandatory=False, default=''),
    },
)

def setup_dhall(version, install=True):
  _toolchain_repo(name="dhall_toolchain")
  for platform in PLATFORMS:
    _setup_dhall(
        name = "dhall_toolchain_%s" % platform,
        version = version,
        platform = platform,
    )
  if install:
    _host_alias(name="dhall_toolchain_host")
    native.register_toolchains('@dhall_toolchain_host//:dhall')

# TODO does this even work?
def register_toolchains(*platforms):
  for platform in platforms:
    native.register_toolchains('@dhall_toolchain_%s//:dhall-%s' % (platform, platform))
