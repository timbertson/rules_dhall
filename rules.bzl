load('//toolchain:setup.bzl', 'TOOLCHAIN')

DhallLibrary = provider(
        doc="Compiled dhall package",
        fields = {
            "cache": "Cache file",
            "binary": "Binary file",
            "source": "Alpha-normalized source file",
        })

_Deps = provider(
        doc="Deps attr",
        fields = {
            "deps": "",
        })

def _package_path_of_label(label):
  '''
  Returns the package path to a label from the workspace root
  '''
  return (label.package or '.')

def _path_of_label(label):
  '''
  Returns the path to a label from the workspace root
  '''
  path = label.package
  if path != '':
    path += '/'
  path += label.name
  return path

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

  inputs = inputs + srcs
  caches = []
  dhall_inject = []
  for dep, path in (deps or {}).items():
      dep = dep[DhallLibrary]
      dhall_inject.extend([
              _package_path_of_label(ctx.label) + '/' + path,
              dep.binary.path
      ])
      caches.append(dep.cache.path)
      inputs.extend([dep.cache, dep.binary])

  env['DHALL_INJECT'] = ':'.join(dhall_inject)
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
    ),
    _Deps(deps = ctx.attr.deps),
  ]

def _output_impl(ctx):
  path = _extract_path(ctx)
  output = ctx.actions.declare_file(ctx.label.name)
  srcs = ctx.attr.srcs
  _exec_dhall(ctx,
              ctx.attr.exe,
              ctx.attr.dhall_args + ['--file', path.path],
              inputs = [path],
              srcs = srcs,
              output = output,
              deps = ctx.attr.deps)

  return [
    DefaultInfo(files = depset([ output ])),
    _Deps(deps = ctx.attr.deps),
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

def _util_impl(ctx):
  deps = {}
  if ctx.attr.deps:
      deps = ctx.attr.deps
  elif ctx.attr.deps_from:
      deps = ctx.attr.deps_from[_Deps].deps

  dhall_inject = []
  inputs = []
  for dep, path in deps.items():
      dep = dep[DhallLibrary]
      dhall_inject.extend([
              _package_path_of_label(ctx.label) + '/' + path,
              dep.source.path
      ])
      inputs.append(dep.source)
  exe = ctx.actions.declare_file(ctx.label.name)
  ctx.actions.expand_template(
      template = ctx.file._template,
      output = exe,
      substitutions = {
        '%{DHALL_INJECT}%': ':'.join(dhall_inject),
      },
      is_executable=True)

  return DefaultInfo(executable = exe)

COMMON_ATTRS = {
  # TODO rename file? matches dhall...
  "path": attr.label(allow_single_file = True, mandatory = True),
  "srcs": attr.label_list(),
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
  "dhall_args": attr.string_list(mandatory = True),
})
_output_rule = _make_rule(
    implementation = _output_impl,
    attrs = OUTPUT_ATTRS,
)

_dhall_util = rule(
    implementation = _util_impl,
    executable = True,
    attrs = {
      'deps': COMMON_ATTRS['deps'],
      'deps_from': attr.label(),
      '_template': attr.label(
        default = Label('//cmds:util-template.sh'),
        allow_single_file = True,
      ),
    },
)

def dhall_util(name='util', **kw):
  return _dhall_util(name=name, **_fix_args(kw, default_path=False))

# TODO input_rule, for json-to-dhall etc

def _fix_args(kw, default_path=True):
    if default_path:
        if 'path' not in kw:
            kw['path'] = '//' + native.package_name() + ":package.dhall"
    if 'deps' in kw:
        # flip keys/values because bazel's label_keyed_string_dict is weird
        deps = {}
        for path, label in kw['deps'].items():
            deps[label] = path
        kw['deps'] = deps
    return kw

def dhall_library(name='package', **kw):
    return _lib_rule(name=name, **_fix_args(kw))

def dhall_text(**kw):
    return _output_rule(exe='dhall', dhall_args=['text'], **_fix_args(kw))

def dhall_to_json(**kw):
    return _output_rule(exe='dhall-to-json', dhall_args=[], **_fix_args(kw))

def dhall_to_yaml(**kw):
    return _output_rule(exe='dhall-to-yaml', dhall_args=[], **_fix_args(kw))
