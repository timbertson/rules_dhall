load('setup.bzl', 'TOOLCHAIN')

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

def _exec_dhall(ctx, exe_name, arguments, src_depset, deps, output=None, outputs=None, env={}):
  info = ctx.toolchains[Label(TOOLCHAIN)].dhall
  dhall_exe = None
  dhall_target = None

  bin_files = info.binaries.files.to_list()
  for bin_file in bin_files:
      if bin_file.basename == exe_name:
          # print("FOUND  " + repr(file))
          dhall_exe = bin_file
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

  inputs = []
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
    inputs = depset(direct = inputs, transitive = [src_depset]),
    tools = info.binaries.files,
    outputs = outputs,
    progress_message = " ".join([exe_name] + arguments),
    env = env
  )



def _extract_file(ctx):
  file = ctx.attr.file.files.to_list()
  if len(file) != 1:
      fail("Invalid file")
  return file[0]

def _join_file_and_srcs(file, srcs):
  return depset(direct=[file], transitive = [src.files for src in srcs])

def _lib_impl(ctx):
  # don't use .dhall extension due to https://github.com/bazelbuild/bazel/issues/11875
  file = _extract_file(ctx)
  source_file = ctx.actions.declare_file(ctx.label.name + '.dhall-source')
  _exec_dhall(ctx,
              'dhall',
              ['--alpha', '--file', file.path],
              src_depset = _join_file_and_srcs(file, ctx.attr.srcs),
              output = source_file,
              deps = ctx.attr.deps)

  hash_file = ctx.actions.declare_file(ctx.label.name + '.dhall-hash')
  _exec_dhall(ctx,
              'dhall',
              ['hash', '--file', source_file.path],
              src_depset = depset([source_file]),
              output = hash_file,
              deps=None)

  cache_file = ctx.actions.declare_file(ctx.label.name + '.dhall-cache')
  binary_file = ctx.actions.declare_file(ctx.label.name + '.dhall-binary')
  _exec_dhall(ctx,
              'dhall',
              ['encode', '--file', source_file.path],
              src_depset = depset([source_file, hash_file]),
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
  file = _extract_file(ctx)
  output = ctx.actions.declare_file(ctx.label.name)
  _exec_dhall(ctx,
              ctx.attr.exe,
              ctx.attr.dhall_args + ctx.attr.args + ['--file', file.path],
              src_depset = _join_file_and_srcs(file, ctx.attr.srcs),
              output = output,
              deps = ctx.attr.deps)

  return [
    DefaultInfo(files = depset([ output ])),
    _Deps(deps = ctx.attr.deps),
  ]

def _input_impl(ctx):
  file = _extract_file(ctx)
  schema_args = []
  srcs = [file]
  schema = ctx.attr.schema
  if schema:
      schema_file = schema.files.to_list()[0]
      srcs.append(schema_file)
      schema_args.append('./' + schema_file.path)
  output = ctx.actions.declare_file(ctx.label.name)
  _exec_dhall(ctx,
              ctx.attr.exe,
              ctx.attr.args + schema_args + ['--file', file.path],
              src_depset = depset(direct=srcs),
              output = output,
              deps = None)

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

  info = ctx.toolchains[Label(TOOLCHAIN)].dhall
  runfiles = []
  path = []
  bin_files = info.binaries.files.to_list()
  runfiles.extend(bin_files)
  for file in bin_files:
      path.append('$EXEC_ROOT/' + file.dirname)

  ctx.actions.expand_template(
      template = ctx.file._template,
      output = exe,
      substitutions = {
        '%{DHALL_INJECT}%': ':'.join(dhall_inject),
        '%{PATH}%': ':'.join(path),
        '%{PACKAGE}%': _package_path_of_label(ctx.label),
      },
      is_executable=True)

  return DefaultInfo(executable = exe, runfiles = ctx.runfiles(files=runfiles))

COMMON_ATTRS = {
  "file": attr.label(allow_single_file = True, mandatory = True),
  "srcs": attr.label_list(allow_files = True),
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
  "args": attr.string_list(mandatory = False, default=[]),
})
_output_rule = _make_rule(
    implementation = _output_impl,
    attrs = OUTPUT_ATTRS,
)

INPUT_ATTRS = {
  "file": attr.label(allow_single_file = True, mandatory = True),
  "schema": attr.label(allow_single_file = True, mandatory = False),
  "exe": attr.string(mandatory = True),
  "args": attr.string_list(mandatory = False, default=[]),
}
_input_rule = _make_rule(
    implementation = _input_impl,
    attrs = INPUT_ATTRS,
)

_dhall_util = rule(
    implementation = _util_impl,
    executable = True,
    toolchains = [TOOLCHAIN],
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
  return _dhall_util(name=name, **_fix_args(kw, default_file=False))

# TODO input_rule, for json-to-dhall etc

def _fix_args(kw, default_file=True):
    if default_file:
        if 'file' not in kw:
            kw['file'] = '//' + native.package_name() + ":package.dhall"
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

def json_to_dhall(**kw):
    return _input_rule(exe='json-to-dhall', **kw)

def yaml_to_dhall(**kw):
    return _input_rule(exe='yaml-to-dhall', **kw)
