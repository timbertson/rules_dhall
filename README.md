# rules_dhall

This repo contains rules for using [Dhall](https://dhall-lang.org) in [bazel](https://bazel.build/) builds.

<!--
The rules use the method described by [@Gabriel439](https://github.com/Gabriel439) in [this answer](https://stackoverflow.com/questions/61139099/how-can-i-access-the-output-of-a-bazel-rule-from-another-rule-without-using-a-re)
 on stack overflow.

rules_dhall fetches binary releases of dhall from github - see section [command targets](#command-targets).

## Rule reference
### dhall_library
This rule takes a dhall file and makes it available to other rules.  The output of the 
rule is a tar archive that contains 3 files:
* the binary encoded, alpha normalized dhall expression (.cache/dhall)
* the dhall source file (source.dhall)
* a placeholder that includes the sha256 hash (binary.dhall)
   
Attribute  | Description |
---------- |  ---- |
name       | __string; required.__ 
entrypoint | __label; required.__  This is name of the dhall file that contains the expression that is the entrypoint to the package.  Any dhall references from another dhall package _must_ include the sha256 hash.
srcs       | __List of labels; optional.__ List of source files that are referenced from *entrypoint*.
deps       | __List of labels; optional.__ List of dhall_library targets that this rule should depend on.
data       | __List of labels; optional.__ The output of these targets will copied into this package so that dhall can reference them.
verbose    | __bool; optional.__  If True, will output verbose logging to the console.

See example [abcd](https://github.com/humphrej/dhall-bazel/tree/master/examples/abcd).

### dhall_yaml / dhall_json
   This rule runs a dhall output generator.  The output of the rule is the YAML or JSON file.

Attribute | Description |
----------| -----------| 
entrypoint | __label; required.__  This is name of the dhall file that contains the expression that is the entrypoint to the package.  Any dhall references from another dhall package _must_ include the sha256 hash.
srcs       | __List of labels; optional.__ List of source files that are referenced from *entrypoint*.
deps      | __List of labels; optional.__ List of dhall_library targets that this rule depends on.
data      | __List of labels; optional.__ The output of these targets will copied into this package so that dhall can reference them.
out       | __string; optional.__ Defaults to the src file prefix plus an extension of ".yaml" or ".json".
verbose   | __bool; optional.__  If True, will output verbose logging to the console.
args      | __List of string; optional.__ Adds additional arguments to dhall-to-yaml or dhall-to-json.

See example [abcd](https://github.com/humphrej/dhall-bazel/tree/master/examples/abcd)

## Command targets

TODO implement these...

To run dhall or dhall-to-yaml via bazel:
```shell script
bazel run //cmds:dhall -- —help
bazel run //cmds:dhall-to-yaml -- —help
bazel run //cmds:dhall-to-json -- —help
``` 

-->

# Dependencies

When using dependencies, the original `rules_dhall` relied on dhall source files containing the exact hash corresponding to each dependency.
When upgrading the bazel file, the correspnding source needs to be updated as well.

This package uses dependency injection instead. When you pass in the following deps:

```
deps = {
  'k8s': '@dhall_k8s/package',
  'prelude: '@dhall_prelude/package',
}
```

Then during evaluation, the `DEPS` environment variable will be set to a dhall record with the same keys. To use it in your code, you would write:

```
let deps = env:DEPS
let k8s = deps.k8s
let prelude = deps.prelude
in ...
```

This saves you from having to manage duplicate imports between bazel and dhall.

However, such files can be more difficult to evaluate, since your editor / shell won't have an appropriate `$DEPS` value set.

TODO generate a file, and/or spawn a shell with DEPS set. Then use e.g. env:DEPS ? ./deps.dhall
