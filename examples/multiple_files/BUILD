package(default_visibility = ["//visibility:public"])

load('//:rules.bzl', 'dhall_text', 'dhall_util')
load("@bazel_tools//tools/build_rules:test_rules.bzl", "file_test")

dhall_text(name='text', srcs=['subject.dhall'])
file_test(name="test_text", file="text", content="Hello, World!")
dhall_util(name='eval', args=['exec', 'dhall', '--file', 'package.dhall'])
