{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  apple-sdk,
  bintools-unwrapped,
  darwin,
  llvmPackages,
}:
stdenvNoCC.mkDerivation {
  pname = "pam-tid-look";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "samuelb";
    repo = "pam_tid_look";
    rev = "7ec6bd66c3a6134eeb62e181cd07806e07578858";
    hash = "sha256-M07Y6rwNxXsZWv6Tjk/khKRn53fUTbG8ytRVttwdbpI=";
  };

  nativeBuildInputs = [
    llvmPackages.clang-unwrapped
    bintools-unwrapped
    darwin.sigtool
  ];

  # System sudo loads arm64e code. Use the unwrapped compiler and Apple's
  # unfiltered SDK so the module links to macOS's PAM, not a Nix copy.
  buildPhase = ''
    runHook preBuild
    make "CC=clang -isysroot ${apple-sdk.src}" "ARCHS=-arch arm64e -arch arm64" \
      build/pam_tid_look.so build/pam_tid_look_probe
    runHook postBuild
  '';

  # Let nix-darwin own sudo_local; never run the upstream system installer.
  installPhase = ''
    runHook preInstall
    install -Dm555 build/pam_tid_look.so "$out/lib/pam/pam_tid_look.so"
    runHook postInstall
  '';
  dontFixup = true; # Preserve the module's ad-hoc signature.

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    module="$out/lib/pam/pam_tid_look.so"
    lipo "$module" -verify_arch arm64e arm64
    /usr/bin/codesign --verify --strict --all-architectures "$module"
    build/pam_tid_look_probe module "$module"
    runHook postInstallCheck
  '';

  meta = {
    description = "Touch ID for macOS sudo with a configurable dialog timeout";
    homepage = "https://github.com/samuelb/pam_tid_look";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
  };
}
