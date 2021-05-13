load('//toolchain:setup.bzl', 'TOOLCHAIN')

DhallLibrary = provider(
        doc="Compiled dhall package",
        fields = {
            "cache": "Cache file",
            "binary": "Binary file path",
        })

def _exec_dhall(ctx, exe_name, arguments, inputs, deps, output=None, outputs=None, env={}):
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

  cache_path = []
  dep_attrs = []
  for dep, name in deps.items():
      dep = dep[DhallLibrary]
      inputs.extend([dep.cache, dep.binary])
      cache_path.append(dep.cache.path)
      dep_attrs.append('`' + name + '` = ./' + dep.binary.path)
  env['DHALL_CACHE_ARCHIVES'] = ':'.join(cache_path)
  env['DEPS'] = '{' + ', '.join(dep_attrs) + '}'
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
  srcs = ctx.attr.srcs
  _exec_dhall(ctx,
              'dhall',
              ['--alpha', '--file', path.path],
              inputs = [path] + srcs,
              output = source_file,
              deps = ctx.attr.deps)

  hash_file = ctx.actions.declare_file(ctx.label.name + '/hash')
  _exec_dhall(ctx,
              'dhall',
              ['hash', '--file', source_file.path],
              inputs = [source_file],
              output = hash_file,
              deps={})

  cache_file = ctx.actions.declare_file(ctx.label.name + '/cache')
  binary_file = ctx.actions.declare_file(ctx.label.name + '/binary.dhall')
  _exec_dhall(ctx,
              'dhall',
              ['encode', '--file', source_file.path],
              inputs = [source_file, hash_file],
              outputs = [cache_file, binary_file],
              env = {
                  'CAPTURE_HASH': hash_file.path,
                  'BINARY_FILE': binary_file.path,
                  'OUTPUT_TO': cache_file.path,
              },
              deps={})

  return [
    DefaultInfo(files = depset([
      source_file,
      binary_file,
    ])),
    DhallLibrary(
            cache = cache_file,
            binary = binary_file,
    )
  ]

def _output_impl(ctx):
  path = _extract_path(ctx)
  output = ctx.actions.declare_file(ctx.label.name)
  srcs = ctx.attr.srcs
  _exec_dhall(ctx,
              ctx.attr.exe,
              ctx.attr.args + ['--file', path.path],
              inputs = [path] + srcs,
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
  "path": attr.label(allow_single_file = True, mandatory = True),
  "srcs": attr.label_list(allow_files = [".dhall"]),
  "deps": attr.label_keyed_string_dict(providers = [DhallLibrary]),
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

    if 'deps' in kw:
        # bazel supports a map of label -> string, but we want the opposite
        deps = {}
        for name, label in kw['deps'].items():
            deps[label] = name
        kw['deps'] = deps
    return kw

def dhall_lib(name='package', **kw):
    return _lib_rule(name=name, **_fix_args(kw))

def dhall_text(**kw):
    return _output_rule(exe='dhall', args=['text'], **_fix_args(kw))

def dhall_to_json(**kw):
    return _output_rule(exe='dhall-to-json', args=[], **_fix_args(kw))

def dhall_to_yaml(**kw):
    return _output_rule(exe='dhall-to-yaml', args=[], **_fix_args(kw))
