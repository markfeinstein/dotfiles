{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  nodejs,
}: let
  version = "0.0.34";
in
  buildNpmPackage {
    pname = "pi-acp";
    inherit version;

    src = fetchFromGitHub {
      owner = "svkozak";
      repo = "pi-acp";
      rev = "v${version}";
      hash = "sha256-QRwxOtTZOY+Np3PkAoy2o2PrUzEqjItM/372sCPlSMo=";
    };

    npmDepsHash = "sha256-BvLNtFfp1cMVjzWcMRSdhTqiJrTfbFoUbWkkPW9200o=";

    patches = [../patches/pi-acp-session-mcp.patch];

    npmBuildScript = "build";

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm run typecheck
      npm run lint
      npm run test
      runHook postCheck
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [nodejs];
    installCheckPhase = ''
      runHook preInstallCheck
      test -x "$out/bin/pi-acp"
      test -f "$out/lib/node_modules/pi-acp/dist/session-mcp-extension.js"
      node --check "$out/lib/node_modules/pi-acp/dist/index.js"
      node --check "$out/lib/node_modules/pi-acp/dist/session-mcp-extension.js"
      runHook postInstallCheck
    '';

    meta = {
      description = "ACP adapter for the Pi coding agent";
      homepage = "https://github.com/svkozak/pi-acp";
      changelog = "https://github.com/svkozak/pi-acp/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "pi-acp";
      platforms = lib.platforms.unix;
    };
  }
