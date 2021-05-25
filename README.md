# rules_dhall

This repo contains rules for using [Dhall](https://dhall-lang.org) in [bazel](https://bazel.build/) builds.

It started as some improvements for [rules_dhall][original], but ended up becoming a full rewrite with many more features.

rules_dhall fetches arbitrary releases of dhall from github (you specify the dhall version in your WORKSPACE file).

It supports sharing dhall libraries, as well as generating other files (text, json, yaml, etc) from dhall sources.

To use it, you need to add the repository and then call `setup_dhall` with the version of dhall you wish to use:

```
# WORKSPACE
rules_dhall_version = "1cbf2a8351de9c6ac845464bc03ebe0435959633"
http_archive(
    name = "rules_dhall",
    type = "zip",
    strip_prefix = "rules_dhall-%s" % rules_dhall_version,
    url = "https://github.com/timbertson/rules_dhall/archive/%s.zip" % rules_dhall_version,
)
load("@rules_dhall//toolchain:setup.bzl", "setup_dhall")
setup_dhall(version="1.38.0")
```

```
# BUILD
load("@rules_dhall//rules.bzl", "dhall_library")
dhall_library()
```

See example [dependencies](/examples/dependencies)

## Rule reference
### dhall_library
This rule takes a dhall file and makes it available to other rules.

This normalizes the full expression into a single file, and includes metadata to enable efficient caching (TODO link).

Attribute  | Description |
---------- |  ---- |
name       | __string; default `package`.__
file | __label; default `package.dhall`.__
srcs       | __List of labels; optional.__ List of additional dhall files that are referenced from *file*.
deps       | __Dictionary of `path: label`; optional.__ Dictionary of dependencies (key: local file path, value: dhall_library label).
verbose    | __bool; optional.__  If True, will output verbose logging to the console.

### dhall_text / dhall_to_yaml / dhall_to_json

These output rules produce some non-dhall files from a dhall expression.

Attribute | Description |
----------| -----------| 
name       | __string; required.__
file | __label; default `package.dhall`.__
srcs       | __List of labels; optional.__ List of additional dhall files that are referenced from *file*.
deps       | __Dictionary of `path: label`; optional.__ Dictionary of dependencies (key: local file path, value: dhall_library label).
verbose   | __bool; optional.__  If True, will output verbose logging to the console.
args      | __List of string; optional.__ Pass additional arguments to dhall-to-yaml, dhall-to-json, etc.

## Utility target

The `dhall_util` rule creates a runnable target (invoked via `bazel run`), with a number of useful subcommands.

Attribute | Description |
----------| -----------|
name | __label; default `'util'`.__

Sample use:

```
$ bazel run util -- exec which dhall
/private/var/tmp/_bazel_tim/efa3e6520271e5b3f713522276be1fed/execroot/dhall/bazel-out/darwin-fastbuild/bin/examples/dependencies/util.runfiles/dhall/external/dhall_toolchain_macos-x86_64/dhall/bin/dhall
```

# Dependencies (remote imports)

When using dependencies, the [original][original] `rules_dhall` relies on dhall source files containing the exact hash corresponding to each dependency.

This means that when upgrading a dependency, both the bazel dependency and the corresponding dhall import need to be updated separately (but consistently), which makes for an awkward and brittle workflow.

This package instead uses bazel to inject dependencies. Each rule accepts a `deps` dictionary which lets you place dhall libraries at the specified paths during execution:

```
dhall_library(name="package", deps={
  'dependencies/k8s.dhall': '@dhall_k8s//:package',
  'dependencies/prelude.dhall: '@dhall_prelude//:package',
})
```

This will place the given libraries as files during execution, so that you can rely on always using the version of the upstream dependency provided by bazel.

Generating dependency files inside bazel has one big drawback: it makes local evaluation difficult (e.g in your shell / editor). To work around this, there is a `dhall_util` rule. This works with `bazel run` to provide some utility functions for development. e.g.:

```
# BUILD
dhall_util(deps_from="package")
```

```
$ bazel run util symlink
```

This will generate dependency files (as symlinks to bazel's build locations). These links are not stable and should not be committed to git, but can be useful for local development.

If you would rather stick to remote imports in your source tree, you can still do that. You should still specify `deps` for your bazel targets though, so that you get the efficiency of a local dependency when building within bazel (remote imports cannot be cached across bazel builds).

[original]: https://github.com/humphrej/rules_dhall
