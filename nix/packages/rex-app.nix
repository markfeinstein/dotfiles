{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
stdenvNoCC.mkDerivation {
  pname = "rex-app";
  version = "0.1.0-1913";

  src = fetchurl {
    url = "https://blob.superlogical.com/public/rex-app/snapshot-arm64/Rex-0.1.0-1913.dmg";
    hash = "sha256-Wgfh8NgduqYTH5rM+Vq6KLjPsRY+e+L8dHDiSjYaG+Y=";
  };

  nativeBuildInputs = [undmg];
  sourceRoot = ".";
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -R "Rex Beta.app" "$out/Applications/Rex Beta.app"

    runHook postInstall
  '';

  passthru = {
    appName = "Rex Beta.app";
    bundleIdentifier = "com.superlogical.rex";
    teamIdentifier = "AG92C3PT77";
    buildVersion = "1913";
  };

  meta = {
    description = "Rex terminal application snapshot";
    homepage = "https://rex.superlogical.com";
    license = lib.licenses.unfree;
    platforms = ["aarch64-darwin"];
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
  };
}
