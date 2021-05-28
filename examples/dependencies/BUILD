package(default_visibility = ["//visibility:public"])

load('//:rules.bzl', 'dhall_library', 'dhall_text', 'dhall_to_json', 'dhall_to_yaml', 'dhall_util', 'json_to_dhall', 'yaml_to_dhall')
load("@bazel_tools//tools/build_rules:test_rules.bzl", "file_test")

deps = {
    'dependencies/a.dhall': '//examples/dependencies/a:package',
    'dependencies/b.dhall': '//examples/dependencies/b:package',
}

dhall_text(name='text', file="text.dhall", deps = deps)
file_test(name="test_text", file="text", content="Hello, World!")

dhall_to_json(name='json', deps = deps)
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

dhall_to_yaml(name='yaml', deps = deps)
file_test(name="test_yaml", file="yaml", content=
'''deps:
  a:
    greeting: Hello
  b:
    subject: World
''')

dhall_util(deps_from = "text")

# -- test *-to-dhall
json_to_dhall(name="json.dhall", file="json", schema = 'schema.dhall')
file_test(name="test_json.dhall", file="json.dhall", content=
  '{ deps = { a.greeting = "Hello", b.subject = "World" }, extra = None Text }\n')

yaml_to_dhall(name="yaml.dhall", file="yaml")
file_test(name="test_yaml.dhall", file="yaml.dhall", content=
  '{ deps = { a.greeting = "Hello", b.subject = "World" } }\n')
