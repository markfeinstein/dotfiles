{
  self,
  nixpkgs,
  nix-darwin,
  home-manager,
  nix-homebrew,
  neovim-nightly-overlay,
  rex-picker,
  yabai,
  ...
}: let
  inherit (nixpkgs) lib;

  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  packageOverlay = import ./overlays;
  rexPickerOverlay = final: _prev: {
    rex-picker = rex-picker.packages.${final.stdenv.hostPlatform.system}.default;
  };
  yabaiOverlay = final: _prev: let
    rawYabai = yabai.packages.${final.stdenv.hostPlatform.system}.default;
  in {
    yabai = rawYabai;

    yabaiAppBundle =
      final.runCommand "yabai-app-bundle-${rawYabai.version}" {
        passthru.rawPackage = rawYabai;
      } ''
        app="$out/Applications/Yabai.app"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
        /usr/bin/lipo -thin arm64 ${rawYabai}/bin/yabai -output "$app/Contents/MacOS/yabai"
        chmod 0755 "$app/Contents/MacOS/yabai"
        /usr/bin/codesign --remove-signature "$app/Contents/MacOS/yabai"
        cat >"$app/Contents/Info.plist" <<'EOF'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key>
          <string>yabai</string>
          <key>CFBundleIdentifier</key>
          <string>com.asmvik.yabai</string>
          <key>CFBundleName</key>
          <string>Yabai</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
          <key>CFBundleShortVersionString</key>
          <string>${rawYabai.version}</string>
          <key>CFBundleVersion</key>
          <string>${rawYabai.version}</string>
          <key>LSUIElement</key>
          <true/>
        </dict>
        </plist>
        EOF
        (
          cd "$app"
          ${final.coreutils}/bin/sha256sum Contents/Info.plist Contents/MacOS/yabai \
            >Contents/Resources/content-manifest.sha256
        )
      '';

    yabaiAppShim = final.writeShellScriptBin "yabai" ''
      exec /Applications/Yabai.app/Contents/MacOS/yabai "$@"
    '';
  };
  overlay = lib.composeManyExtensions [
    neovim-nightly-overlay.overlays.default
    rexPickerOverlay
    yabaiOverlay
    packageOverlay
  ];
  nixpkgsConfig.allowUnfreePredicate = package:
    builtins.elem (lib.getName package) [
      "1password-cli"
      "copilot-language-server"
      "terraform"
    ];
  pkgsFor = system:
    import nixpkgs {
      inherit system;
      config = nixpkgsConfig;
      overlays = [overlay];
    };

  homeCommon.imports = [
    ./modules/home
    ./profiles/home-common.nix
  ];
  homePersonal = {
    imports = [
      homeCommon
      ./profiles/personal.nix
    ];
  };
  homeWork = {
    imports = [
      homeCommon
      ./profiles/work.nix
    ];
  };
  homeProfiles = {
    personal = homePersonal;
    work = homeWork;
  };

  darwinFoundation = {
    imports = [
      ./modules/darwin
      ./modules/darwin/profile.nix
      home-manager.darwinModules.home-manager
      nix-homebrew.darwinModules.nix-homebrew
      ({config, ...}: {
        nix-homebrew = {
          enable = true;
          user = config.system.primaryUser;
          autoMigrate = true;
        };
      })
    ];
    nixpkgs = {
      hostPlatform = "aarch64-darwin";
      config = nixpkgsConfig;
      overlays = [overlay];
    };
  };

  mkDarwinProfile = profileName: homeModule: {config, ...}: {
    imports = [darwinFoundation];
    profile.name = profileName;
    home-manager.users.${config.profile.user.username}.imports = [homeModule];
  };

  darwinPersonal = mkDarwinProfile "personal" homePersonal;
  darwinWork = mkDarwinProfile "work" homeWork;

  mkHome = system: profileModule:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      modules = [profileModule];
    };

  mkDarwin = profileModule:
    nix-darwin.lib.darwinSystem {
      modules = [
        profileModule
        (_: {
          system.configurationRevision = self.rev or self.dirtyRev or null;
        })
      ];
    };

  homeConfigurations = builtins.listToAttrs (
    lib.concatMap (
      system:
        lib.mapAttrsToList (profileName: profileModule: {
          name = "${system}-${profileName}";
          value = mkHome system profileModule;
        })
        homeProfiles
    )
    systems
  );
  darwinConfigurations = {
    personal = mkDarwin darwinPersonal;
    work = mkDarwin darwinWork;
  };
  checks =
    lib.recursiveUpdate
    (lib.genAttrs systems (system: {
      home-personal = homeConfigurations."${system}-personal".activationPackage;
      home-work = homeConfigurations."${system}-work".activationPackage;
    }))
    {
      aarch64-darwin = {
        darwin-personal = darwinConfigurations.personal.config.system.build.toplevel;
        darwin-work = darwinConfigurations.work.config.system.build.toplevel;
      };
    };
in {
  overlays.default = overlay;

  packages = lib.genAttrs systems (system: let
    pkgs = pkgsFor system;
  in {
    inherit
      (pkgs)
      configure-repository-worktrees
      git-project
      git-readonly
      ;
  });

  homeModules = {
    common = homeCommon;
    personal = homePersonal;
    work = homeWork;
  };

  darwinModules = {
    common = darwinFoundation;
    personal = darwinPersonal;
    work = darwinWork;
  };

  inherit
    checks
    darwinConfigurations
    homeConfigurations
    ;

  formatter = lib.genAttrs systems (
    system: nixpkgs.legacyPackages.${system}.alejandra
  );
}
