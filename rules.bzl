load('//toolchain:setup.bzl', 'TOOLCHAIN')

DhallLibrary = provider(
        doc="Compiled dhall package",
        fields = {
            "cache": "Cache file",
            "binary": "Binary file",
            "source": "Alpha-normalized source file",
        })

DhallDependencies = provider(
        doc="Set of dependencies",
        fields = {
            "inputs": "list of files",
            "caches": "list of strings",
            "output": "output file",
            "workspace_path": "",
        })

DhallSources = provider(
        doc="enum for sources",
        fields = {
            "inputs": "plain inputs",
            "dep_file": "optional DhallDependencies",
        })


def _path_of_label(label):
  '''
  Returns the path to a label from the workspace root
  '''
  path = label.package
  if path != '':
    path += '/'
  path += label.name
  return path

def _extract_deps(srcs):
  inputs = []
  dep_file = None
  for src in srcs:
      # print(repr(src))
      if DhallDependencies in src:
          # print("dep: "+ repr(src))
          dep = src[DhallDependencies]
          dep_file = dep
          inputs.append(dep.output)
          inputs.extend(dep.inputs)
      else:
          # print("src: "+ repr(src))
          inputs.append(src)
  return DhallSources(inputs = inputs, dep_file = dep_file)

def _exec_dhall(ctx, exe_name, arguments, inputs, srcs, deps, output=None, outputs=None, env={}):
  info = ctx.toolchains[Label(TOOLCHAIN)].dhall
  dhall_exe = None
  dhall_target = None

  # TODO this feels a bit silly...
  for target in info.bin_dirs:
      files = target.files.to_list()
      for file in files:
          if file.basename == exe_name:
              # print("FOUND  " + repr(file))
              dhall_exe = file
              dhall_target = target
  if dhall_exe == None:
      fail("No such binary:" + exe_name)

  # weird way to write `copy()` :/
  # copy()
  original_env = env
  env = {}
  env.update(original_env)
  if output != None:
      env['OUTPUT_TO'] = output.path
      if outputs != None:
          fail("both output and outputs given")
      outputs = [ output ]
  if outputs == None:
      fail("outputs (or output) not given")

  caches = []
  dep_attrs = []
  srcs = _extract_deps(srcs)
  inputs = inputs + srcs.inputs

  if srcs.dep_file == None:
      deps_impl = ''
  else:
      dep = srcs.dep_file
      # print("DEP: " + repr(dep))
      deps_impl = dep.output.path
      caches = dep.caches
      env['DEPS_PATH'] = dep.workspace_path

  env['DEPS_IMPL'] = deps_impl
  env['DHALL_CACHE_ARCHIVES'] = ':'.join(caches)
  if ctx.attr.debug:
      env['DEBUG'] = '1'

  ctx.actions.run(
    executable = ctx.attr._wrapper.files_to_run.executable,
    arguments = [dhall_exe.path] + arguments,
    inputs = inputs,
    tools = dhall_target.files,
    outputs = outputs,
    progress_message = " ".join([exe_name] + arguments),
    env = env
  )

def _extract_path(ctx):
  path = ctx.attr.path.files.to_list()
  if len(path) != 1:
      fail("Invalid path")
  return path[0]

def _lib_impl(ctx):
  path = _extract_path(ctx)
  source_file = ctx.actions.declare_file(ctx.label.name + '/package.dhall')
  _exec_dhall(ctx,
              'dhall',
              ['--alpha', '--file', path.path],
              inputs = [path],
              srcs = ctx.attr.srcs,
              output = source_file,
              deps = ctx.attr.deps)

  hash_file = ctx.actions.declare_file(ctx.label.name + '/hash')
  _exec_dhall(ctx,
              'dhall',
              ['hash', '--file', source_file.path],
              inputs = [source_file],
              output = hash_file,
              srcs = [],
              deps=None)

  cache_file = ctx.actions.declare_file(ctx.label.name + '/cache')
  binary_file = ctx.actions.declare_file(ctx.label.name + '/binary.dhall')
  _exec_dhall(ctx,
              'dhall',
              ['encode', '--file', source_file.path],
              inputs = [source_file, hash_file],
              srcs = [],
              outputs = [cache_file, binary_file],
              env = {
                  'CAPTURE_HASH': hash_file.path,
                  'BINARY_FILE': binary_file.path,
                  'OUTPUT_TO': cache_file.path,
              },
              deps=None)

  return [
    DefaultInfo(files = depset([
      source_file,
      cache_file,
    ])),
    DhallLibrary(
            cache = cache_file,
            binary = binary_file,
            source = source_file,
    )
  ]

def _generate_deps(ctx, output, use_binary):
  caches = []
  dep_attrs = []
  inputs = []
  args = []
  for dep, name in ctx.attr.deps.items():
      dep = dep[DhallLibrary]
      args.append(name)
      if use_binary:
          inputs.extend([dep.cache, dep.binary])
          args.append(dep.binary.path)
          caches.append(dep.cache.path)
      else:
          inputs.extend([dep.source])
          args.append(dep.source.path)
  env = { 'OUTPUT_TO': output.path }
  env['INLINE'] = 'false' if use_binary else 'true'

  ctx.actions.run(
    executable = ctx.attr._script.files_to_run.executable,
    arguments = args,
    inputs = inputs,
    outputs = [output],
    env = env
  )
  return DhallDependencies(
    caches = caches,
    inputs = inputs,
    output = output,
    workspace_path = _path_of_label(ctx.label),
  )

def _deps_impl(ctx):
  source = ctx.actions.declare_file(ctx.label.name)
  binary = ctx.actions.declare_file(ctx.label.name + '.bin')
  exe = ctx.actions.declare_file(ctx.label.name + '-install')
  _generate_deps(ctx, source, use_binary=False)
  dependency_file = _generate_deps(ctx, binary, use_binary=True)
  local_path = _path_of_label(ctx.label)
  
  ctx.actions.write(exe, '''
#!/usr/bin/env bash
set -eu -o pipefail
cd "$BUILD_WORKSPACE_DIRECTORY"
set -x
ln -sfn "$BUILD_WORKSPACE_DIRECTORY/%s" "%s"
''' % (source.path, local_path), is_executable=True)

  return [
    DefaultInfo(files = depset([ source ]), executable = exe),
    dependency_file
  ]

_deps_rule = rule(
    implementation = _deps_impl,
    executable = True,
    attrs = {
      "deps": attr.label_keyed_string_dict(providers = [DhallLibrary]),
      "_script": attr.label(
            default = Label("//cmds:deps"),
            executable = True,
            cfg="exec",
      ),
    }
)

def _output_impl(ctx):
  path = _extract_path(ctx)
  output = ctx.actions.declare_file(ctx.label.name)
  srcs = ctx.attr.srcs
  _exec_dhall(ctx,
              ctx.attr.exe,
              ctx.attr.args + ['--file', path.path],
              inputs = [path],
              srcs = srcs,
              output = output,
              deps = ctx.attr.deps)

  return [
    DefaultInfo(files = depset([ output ])),
  ]

def _make_rule(implementation, **kw):
    args = {}
    args.update(kw)
    attrs = {
      "_wrapper": attr.label(
            default = Label("//cmds:wrapper"),
            executable = True,
            cfg="exec",
      ),
      "debug": attr.bool(default = False),
    }
    attrs.update(kw['attrs'])
    args['attrs'] = attrs
    return rule(implementation = implementation,
        toolchains = [TOOLCHAIN],
         **args)

COMMON_ATTRS = {
  # TODO rename file? matches dhall...
  "path": attr.label(allow_single_file = True, mandatory = True),
  "srcs": attr.label_list(),
  # "deps": attr.label_keyed_string_dict(providers = [DhallLibrary]),
  # TODO remove
  "deps": attr.label(allow_single_file = True, providers = [DhallDependencies]),
}

_lib_rule = _make_rule(
    implementation = _lib_impl,
    attrs = COMMON_ATTRS,
)

OUTPUT_ATTRS = {}
OUTPUT_ATTRS.update(COMMON_ATTRS)
OUTPUT_ATTRS.update({
  "exe": attr.string(mandatory = True),
  "args": attr.string_list(mandatory = True),
})
_output_rule = _make_rule(
    implementation = _output_impl,
    attrs = OUTPUT_ATTRS,
)

# TODO input_rule, for json-to-dhall etc

def _fix_args(kw):
    if 'path' not in kw:
        kw['path'] = '//' + native.package_name() + ":package.dhall"
    return kw

# TODO rename deps -> contents
def dhall_dependencies(deps, name='dependencies.dhall'):
    # bazel supports a map of label -> string, but we want the opposite
    _deps = {}
    for dep_name, label in deps.items():
        _deps[label] = dep_name

    return _deps_rule(name=name, deps=_deps)

def dhall_library(name='package', **kw):
    return _lib_rule(name=name, **_fix_args(kw))

def dhall_text(**kw):
    return _output_rule(exe='dhall', args=['text'], **_fix_args(kw))

def dhall_to_json(**kw):
    return _output_rule(exe='dhall-to-json', args=[], **_fix_args(kw))

def dhall_to_yaml(**kw):
    return _output_rule(exe='dhall-to-yaml', args=[], **_fix_args(kw))
