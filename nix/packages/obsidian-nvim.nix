{
  buildNpmPackage,
  fetchFromGitHub,
  obsidian-nvim,
}: let
  revision = "1fcc60890427aadf2b6bbce74daa938a0b111dca";
  version = "3.16.10-unstable-2026-11-17";
  src = fetchFromGitHub {
    owner = "markfeinstein";
    repo = "obsidian.nvim";
    rev = revision;
    hash = "sha256-gGNm8rh+tdmWyyROhp1vCyoxMJKfpRyWJU/F+40XmaI=";
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
