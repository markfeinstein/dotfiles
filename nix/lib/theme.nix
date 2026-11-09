let
  data = builtins.fromJSON (builtins.readFile ../../themes/rose-pine.json);
in {
  inherit data;
  variant = name: data.variants.${name};
  colors = name: data.variants.${name}.colors;
  terminal = name: data.variants.${name}.terminal;
  derived = name: data.derived.${name} or {};
}
