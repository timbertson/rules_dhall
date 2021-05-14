load('//:rules.bzl', 'dhall_library', 'dhall_dependencies', 'dhall_text', 'dhall_to_json', 'dhall_to_yaml')
load("@bazel_tools//tools/build_rules:test_rules.bzl", "file_test")

dhall_library(name='meta', path='meta.dhall', srcs=['//examples/dependencies:dependencies.dhall'])

dhall_dependencies({ 'meta': 'meta' })
dhall_to_yaml(name='yaml', srcs = ["dependencies.dhall"])
file_test(name="test_yaml", file="yaml", content=
'''meta_deps:
  meta:
    initial_deps:
      a:
        greeting: Hello
      b:
        subject: World
''')

