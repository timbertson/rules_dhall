PLATFORMS = ['macos-x86_64', 'linux-x86_64', 'windows-x86_64']
TOOLCHAIN = '@dhall_toolchain//:toolchain_type'

# If a sha is present it improves caching (and security), unknown releases
# will be downloaded without integrity checks or caching
DIGESTS = {
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
def _binaries_impl(ctx):
  version = ctx.attr.version
  ctx.download(
      "https://api.github.com/repos/dhall-lang/dhall-haskell/releases/tags/" + version,
      output = "release.json",
      sha256 = DIGESTS.get(version) or '')
  json = ctx.read("release.json")

  for (platform, arch), impls in extract_urls(json).items():
    key='%s-%s' % (platform, arch)
    if key != ctx.attr.platform:
      continue

    for tool, url in impls.items():
      digest_key = "%s-%s-%s" % (tool, version, key)
      digest = DIGESTS.get(digest_key)
      if digest == None:
        print("Note: no known digest for %s, add it to @rules_dhall//:toolchain.bzl for better caching" % digest_key)
      ctx.download_and_extract(url=url, output=tool, sha256=digest or '')
  ctx.file("BUILD", 'filegroup(name="binaries", srcs=glob(["**/bin/*"]), visibility=["//visibility:public"])')

_binaries = repository_rule(
    implementation=_binaries_impl,
    local = False,
    attrs = {
        "version": attr.string(mandatory=True),
        "platform": attr.string(mandatory=True),
    },
)

# Generate a single repo with all toolchain definitions
# It's separate from the toolchain binaries so that we only
# end up downloading binaries we need.
def _dhall_toolchain_impl(ctx):
  ctx.template("toolchain.bzl", Label("//:toolchain.bzl"))
  build_lines = [
    'package(default_visibility = ["//visibility:public"])',
    'toolchain_type(name = "toolchain_type")',
    'load("toolchain.bzl", "dhall_toolchain")',
  ]

  for key in PLATFORMS:
    (platform, arch) = key.split('-')
    constraints = [
      '    "@platforms//os:%s",' % platform,
      '    "@platforms//cpu:%s",' % arch,
    ]
    build_lines.extend([
      'dhall_toolchain(',
      '  name="dhall-toolchain-%s",' % key,
      '  binaries="@dhall_toolchain_bin_%s//:binaries"' % key,
      ')',
      'toolchain(',
      '  name="toolchain-%s",' % key,
      '  toolchain="dhall-toolchain-%s",' % key,
      '  toolchain_type="toolchain_type",',
      '  exec_compatible_with = [',
    ] + constraints + [
      '  ],',
      '  target_compatible_with = [',
    ] + constraints + [
      '  ],',
      ')'
    ])

  ctx.file("BUILD", "\n".join(build_lines))

_dhall_toolchain = repository_rule(
    implementation=_dhall_toolchain_impl,
    local = False,
)

def setup_dhall(version):
  _dhall_toolchain(name="dhall_toolchain")
  for platform in PLATFORMS:
    _binaries(
        name = "dhall_toolchain_bin_%s" % platform,
        version = version,
        platform = platform,
    )
    native.register_toolchains('@dhall_toolchain//:toolchain-%s' % platform)
