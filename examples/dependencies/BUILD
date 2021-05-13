load('//:rules.bzl', 'dhall_text', 'dhall_to_json', 'dhall_to_yaml')
deps = {
  'a': '//examples/dependencies/a:package',
  'b': '//examples/dependencies/b:package',
}
dhall_text(name='text', deps = deps)
dhall_to_json(name='json', deps = deps, path="record.dhall")
dhall_to_yaml(name='yaml', deps = deps, path="record.dhall")
