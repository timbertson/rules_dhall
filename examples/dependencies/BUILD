package(default_visibility = ["//visibility:public"]

load('//:rules.bzl', 'dhall_library', 'dhall_dependencies', 'dhall_text', 'dhall_to_json', 'dhall_to_yaml')
load("@bazel_tools//tools/build_rules:test_rules.bzl", "file_test")

dhall_dependencies({
  'a': '//examples/dependencies/a:package',
  'b': '//examples/dependencies/b:package',
})

dhall_text(name='text', path="text.dhall", srcs = ['dependencies.dhall'])
file_test(name="test_text", file="text", content="Hello, World!")

dhall_to_json(name='json', srcs = ["dependencies.dhall"])
file_test(name="test_json", file="json", content='''{
  "deps": {
    "a": {
      "greeting": "Hello"
    },
    "b": {
      "subject": "World"
    }
  }
}
''')

dhall_to_yaml(name='yaml', srcs = ["dependencies.dhall"])
file_test(name="test_yaml", file="yaml", content=
'''deps:
  a:
    greeting: Hello
  b:
    subject: World
''')
