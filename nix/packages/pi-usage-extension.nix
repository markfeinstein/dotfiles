{ fetchurl, runCommand }:
let
  version = "0.10.4";
  src = fetchurl {
    name = "mturley-pi-usage-extension-${version}.tgz";
    url = "https://registry.npmjs.org/@mturley/pi-usage-extension/-/pi-usage-extension-${version}.tgz";
    hash = "sha512-Cw7FZeEt1LlY518inaADQn/Eyb/vGdrhFafGlUHUjygqlJv18hg/XDc11wLa91Pk09m6RR/9M+Gih7KlrQl39w==";
  };
in
# Pi supplies the only runtime peers. No npm install or lifecycle scripts.
runCommand "pi-usage-extension-${version}" { } ''
  mkdir -p "$out"
  tar xf ${src} -C "$out" --strip-components=1
''
