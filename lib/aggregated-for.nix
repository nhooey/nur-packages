# Pulls one flake-output field (e.g. "packages") from every input in
# `inputs` for `system`, with `{ }` if that input doesn't expose the field
# or doesn't support that system, and merges them in input-name order.
#
# The `metaKeys` (aliases such as `default`, which is how `nix run
# github:owner/repo` resolves without `#name`) are stripped before merging,
# as every input's `default` would otherwise shadow the previous one
# silently. Last input still wins on real-name collisions.
#
# Single-package flakes expose only `default`, so blind stripping would drop
# them entirely. When an input has *no* other named attributes, its
# `default` is promoted to the input's name: `<field>.<sys>.<input-name>`.
# Inputs that already expose proper names keep their `default` stripped to
# avoid noise aliases.
{ lib, metaKeys }:
inputs: field: system:
lib.foldl' (
  acc: name:
  let
    attrs = inputs.${name}.${field}.${system} or { };
    named = builtins.removeAttrs attrs metaKeys;
    promoted = if attrs ? default && named == { } then { ${name} = attrs.default; } else { };
  in
  acc // promoted // named
) { } (builtins.attrNames inputs)
