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
    bundleIdentifier = "com.markfeinstein.yabai.local-development";
  in {
    yabai = rawYabai;

    yabaiAppBundle =
      final.runCommand "yabai-app-bundle-${rawYabai.version}" {
        passthru = {
          inherit bundleIdentifier;
          rawPackage = rawYabai;
        };
      } ''
        app="$out/Applications/Yabai.app"
        executable="$app/Contents/MacOS/yabai"
        source_executable=${rawYabai}/bin/yabai
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
        /usr/bin/lipo "$source_executable" -verify_arch arm64
        if [ "$(/usr/bin/lipo -archs "$source_executable")" = arm64 ]; then
          cp "$source_executable" "$executable"
        else
          /usr/bin/lipo -thin arm64 "$source_executable" -output "$executable"
        fi
        chmod 0755 "$executable"
        /usr/bin/codesign --remove-signature "$app/Contents/MacOS/yabai"
        cat >"$app/Contents/Info.plist" <<'EOF'
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleExecutable</key>
          <string>yabai</string>
          <key>CFBundleIdentifier</key>
          <string>${bundleIdentifier}</string>
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
      "rex-app"
      "terraform"
    ];
  pkgsFor = system:
    import nixpkgs {
      inherit system;
      config = nixpkgsConfig;
      overlays = [overlay];
    };

  homeCommon.imports = [./modules/home];
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
      ./modules/profile.nix
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
  darwinHosts = {
    m5 = ./hosts/m5.nix;
  };

  mkHome = system: profileModule:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      modules = [profileModule];
    };

  mkDarwin = modules:
    nix-darwin.lib.darwinSystem {
      modules =
        modules
        ++ [
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
  darwinConfigurations =
    {
      personal = mkDarwin [darwinPersonal];
      work = mkDarwin [darwinWork];
    }
    // lib.mapAttrs (_: hostModule: mkDarwin [darwinPersonal hostModule]) darwinHosts;
  m5Pkgs = darwinConfigurations.m5.pkgs;
  checks =
    lib.recursiveUpdate
    (lib.genAttrs systems (system: let
      pkgs = pkgsFor system;
    in {
      home-personal = homeConfigurations."${system}-personal".activationPackage;
      home-work = homeConfigurations."${system}-work".activationPackage;
      marksman-binary = pkgs.runCommand "marksman-binary-check" {} ''
        ${pkgs.python3}/bin/python ${./tests/marksman-lsp.py} ${lib.getExe pkgs.marksman}
        touch "$out"
      '';
      neovim-cached-plugins = let
        home = homeConfigurations."${system}-personal";
        upstreamPkgs = import nixpkgs {
          inherit system;
          config = nixpkgsConfig;
        };
        grammarNames = pkgs.writeText "neovim-test-grammars.json" (
          builtins.toJSON home.config.dotfiles.neovim.treesitterGrammars
        );
      in
        assert lib.all (name:
          pkgs.vimPlugins.${name}.drvPath == upstreamPkgs.vimPlugins.${name}.drvPath) [
          "flash-nvim"
          "blink-cmp"
          "codediff-nvim"
          "nvim-treesitter"
        ];
          pkgs.runCommand "neovim-cached-plugins-check" {} ''
            export HOME="$TMPDIR/home"
            export XDG_CONFIG_HOME="$HOME/.config"
            export XDG_DATA_HOME="$HOME/.local/share"
            export XDG_STATE_HOME="$HOME/.local/state"
            export XDG_CACHE_HOME="$HOME/.cache"
            export DOTFILES_TEST_GRAMMARS=${grammarNames}
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack"
            ln -s ${home.config.dotfiles.neovim.finalConfigSource} "$XDG_CONFIG_HOME/nvim"
            ln -s ${home.config.xdg.dataFile."nvim/site/pack/hm".source} "$XDG_DATA_HOME/nvim/site/pack/hm"
            ${lib.getExe home.config.programs.neovim.finalPackage} --headless -i NONE \
              -c 'lua dofile("${./tests/neovim-cached-plugins.lua}")'
            touch "$out"
          '';
    }))
    {
      aarch64-darwin = {
        darwin-personal = darwinConfigurations.personal.config.system.build.toplevel;
        darwin-work = darwinConfigurations.work.config.system.build.toplevel;
        darwin-m5 = darwinConfigurations.m5.config.system.build.toplevel;
        yabai-app-bundle = m5Pkgs.runCommand "yabai-app-bundle-check" {} ''
          app=${m5Pkgs.yabaiAppBundle}/Applications/Yabai.app
          executable="$app/Contents/MacOS/yabai"

          test -x "$executable"
          /usr/bin/lipo "$executable" -verify_arch arm64
          test "$(/usr/bin/lipo -archs "$executable")" = arm64
          test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = \
            com.markfeinstein.yabai.local-development
          (cd "$app" && ${m5Pkgs.coreutils}/bin/sha256sum -c Contents/Resources/content-manifest.sha256)
          touch "$out"
        '';
        rex-app-bundle = m5Pkgs.runCommand "rex-app-bundle-check" {} ''
          app="${m5Pkgs.rex-app}/Applications/Rex Beta.app"

          test -x "$app/Contents/MacOS/Rex"
          /usr/bin/codesign --verify --deep --strict "$app"
          test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = \
            com.superlogical.rex
          /usr/bin/codesign -dv --verbose=4 "$app" 2>&1 \
            | ${m5Pkgs.gnugrep}/bin/grep -Fx 'TeamIdentifier=AG92C3PT77'
          touch "$out"
        '';
      };
    };
in {
  overlays.default = overlay;

  packages = lib.genAttrs systems (system: let
    pkgs = pkgsFor system;
  in {
    inherit
      (pkgs)
      git-project
      git-readonly
      marksman
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
    hosts = darwinHosts;
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
