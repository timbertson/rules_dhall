package(default_visibility = ["//visibility:public"])

load('//:rules.bzl', 'dhall_library', 'dhall_to_yaml')
load("@bazel_tools//tools/build_rules:test_rules.bzl", "file_test")

dhall_library(name='lib', file='_lib_impl.dhall')
dhall_to_yaml(name='yaml', deps = {'dependencies/lib.dhall': 'lib'})
file_test(name="test_yaml", file="yaml", content='lib:\n  hello: world\n')
