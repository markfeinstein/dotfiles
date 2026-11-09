{lib}: script: library: let
  sourceLine = ''source "$(dirname -- "$(realpath -- "''${BASH_SOURCE[0]}")")/lib/${builtins.baseNameOf library}"'';
  text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile script);
in
  assert builtins.length (lib.splitString sourceLine text) == 2;
    builtins.replaceStrings [sourceLine] [(builtins.readFile library)] text
