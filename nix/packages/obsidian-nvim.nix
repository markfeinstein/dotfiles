{
  buildNpmPackage,
  fetchFromGitHub,
  obsidian-nvim,
}:
let
  revision = "7853809d57cbfe4843b0310c81985cac589a29ec";
  version = "3.16.10-unstable-2026-11-17";
  src = fetchFromGitHub {
    owner = "markfeinstein";
    repo = "obsidian.nvim";
    rev = revision;
    hash = "sha256-UzAcoVNXwV+Gp2sIR8zrwVA1Ypo/I9qZpseig9PfLSU=";
  };
  evaluator = buildNpmPackage {
    pname = "obsidian-nvim-bases-runtime";
    inherit version src;
    npmDepsHash = "sha256-lru5XdCcN8SRGVhoWnYgIGDoLun0zuKDnjllZGtIZvo=";
    npmFlags = [ "--ignore-scripts" ];
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
  postInstall = (old.postInstall or "") + ''
    ln -s ${evaluator}/node_modules "$out/node_modules"
  '';
  passthru = (old.passthru or { }) // {
    inherit revision;
  };
  meta = old.meta // {
    homepage = "https://github.com/markfeinstein/obsidian.nvim";
  };
})
