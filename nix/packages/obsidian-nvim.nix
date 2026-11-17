{
  buildNpmPackage,
  fetchFromGitHub,
  obsidian-nvim,
}: let
  revision = "4d4d8676e2b13c01eb4013ecf7c6e1bb909e89af";
  version = "3.16.10-unstable-2026-11-17";
  src = fetchFromGitHub {
    owner = "markfeinstein";
    repo = "obsidian.nvim";
    rev = revision;
    hash = "sha256-t9+4AS3ljwLTXBE4Rg3YwcFWcKFIL+YI/FBEeX8qyxo=";
  };
  evaluator = buildNpmPackage {
    pname = "obsidian-nvim-bases-runtime";
    inherit version src;
    npmDepsHash = "sha256-lru5XdCcN8SRGVhoWnYgIGDoLun0zuKDnjllZGtIZvo=";
    npmFlags = ["--ignore-scripts"];
    dontNpmBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -R node_modules "$out/node_modules"
      runHook postInstall
    '';
  };
in
  obsidian-nvim.overrideAttrs (old: {
    inherit version src;
    # The worker resolves its npm dependencies relative to the plugin root.
    postInstall =
      (old.postInstall or "")
      + ''
        ln -s ${evaluator}/node_modules "$out/node_modules"
      '';
    passthru = (old.passthru or {}) // {inherit revision;};
    meta =
      old.meta
      // {
        homepage = "https://github.com/markfeinstein/obsidian.nvim";
      };
  })
