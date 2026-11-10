{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  versionCheckHook,
  icu,
  krb5,
  libunwind,
  openssl,
  zlib,
}: let
  version = "2026-02-08";
  macos = {
    asset = "marksman-macos";
    hash = "sha256-aoAcF7WsDbppeHxSgrOzvUFuZsliU/rgmNMRxrvRgzs=";
  };
  sources = {
    aarch64-darwin = macos;
    x86_64-darwin = macos;
    aarch64-linux = {
      asset = "marksman-linux-arm64";
      hash = "sha256-244SRSf3+ASOPmyRghucUu8XPZLAHkfSIb8TN6/ZYvs=";
    };
    x86_64-linux = {
      asset = "marksman-linux-x64";
      hash = "sha256-vlCY6CEyGSacR/wNkWpm+jHOBgLslnR1xyImCqvyYIc=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
  runtimeLibraries = [
    stdenv.cc.cc.lib
    icu
    krb5
    libunwind
    openssl
    zlib
  ];
in
  stdenvNoCC.mkDerivation {
    pname = "marksman";
    inherit version;

    src = fetchurl {
      url = "https://github.com/artempyanykh/marksman/releases/download/${version}/${source.asset}";
      inherit (source) hash;
    };

    dontUnpack = true;
    # Preserve the upstream universal Mach-O binary and its signature.
    dontFixup = stdenvNoCC.hostPlatform.isDarwin;
    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [autoPatchelfHook makeWrapper];
    buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux runtimeLibraries;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/marksman"
      runHook postInstall
    '';

    # The self-contained release can also dlopen libraries not listed in ELF NEEDED.
    postFixup = lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
      wrapProgram "$out/bin/marksman" \
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibraries}
    '';

    nativeInstallCheckInputs = [versionCheckHook];
    doInstallCheck = true;

    meta = {
      description = "Markdown language server (upstream precompiled executable)";
      homepage = "https://github.com/artempyanykh/marksman";
      license = lib.licenses.mit;
      mainProgram = "marksman";
      platforms = builtins.attrNames sources;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
