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
}:
let
  inherit (nixpkgs) lib;

  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  packageOverlay = import ./overlays;
  rexPickerOverlay = final: _prev: {
    rex-picker = rex-picker.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
      # Newer Cargo hooks disable bundled SQLite; the pinned flake omits these inputs.
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ final.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [ final.sqlite ];
      # Use Nix's SQLite consistently, including with older Cargo hooks.
      env = (old.env or { }) // {
        LIBSQLITE3_SYS_USE_PKG_CONFIG = "1";
      };
    });
  };
  yabaiOverlay = final: _prev: {
    yabai = yabai.packages.${final.stdenv.hostPlatform.system}.default;
  };
  overlay = lib.composeManyExtensions [
    neovim-nightly-overlay.overlays.default
    rexPickerOverlay
    yabaiOverlay
    packageOverlay
  ];
  nixpkgsConfig.allowUnfreePredicate =
    package:
    builtins.elem (lib.getName package) [
      "1password-cli"
      "claude-code"
      "copilot-language-server"
      "rex-app"
      "terraform"
    ];
  pkgsFor =
    system:
    import nixpkgs {
      inherit system;
      config = nixpkgsConfig;
      overlays = [ overlay ];
    };

  homeCommon.imports = [ ./modules/home ];
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
    _module.args.yabaiInput = yabai;

    imports = [
      ./modules/darwin
      ./modules/profile.nix
      home-manager.darwinModules.home-manager
      nix-homebrew.darwinModules.nix-homebrew
      ({ config, ... }: {
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
      overlays = [ overlay ];
    };
  };

  mkDarwinProfile = profileName: homeModule: { config, ... }: {
    imports = [ darwinFoundation ];
    profile.name = profileName;
    home-manager.users.${config.profile.user.username}.imports = [ homeModule ];
  };

  darwinPersonal = mkDarwinProfile "personal" homePersonal;
  darwinWork = {
    imports = [ (mkDarwinProfile "work" homeWork) ];
    dotfiles = {
      openlogi.enable = true;
      rex.tailnetEnable = true;
    };
  };
  darwinHosts = {
    m5 = ./hosts/m5.nix;
  };

  mkHome =
    system: profileModule:
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      modules = [ profileModule ];
    };

  mkDarwin =
    modules:
    nix-darwin.lib.darwinSystem {
      modules = modules ++ [
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
      }) homeProfiles
    ) systems
  );
  darwinConfigurations = {
    personal = mkDarwin [ darwinPersonal ];
    work = mkDarwin [ darwinWork ];
  }
  // lib.mapAttrs (
    _: hostModule:
    mkDarwin [
      darwinPersonal
      hostModule
    ]
  ) darwinHosts;
  m5Pkgs = darwinConfigurations.m5.pkgs;
  m5Username = darwinConfigurations.m5.config.system.primaryUser;
  m5YabaiPackage =
    darwinConfigurations.m5.config.home-manager.users.${m5Username}.programs.yabai.finalPackage;
  checks =
    lib.recursiveUpdate
      (lib.genAttrs systems (
        system:
        let
          pkgs = pkgsFor system;
          obsidianEnabledHome = homeConfigurations."${system}-work".extendModules {
            modules = [
              {
                profile.obsidian.vaults = lib.mkForce [
                  {
                    name = "alpha";
                    path = "~/vaults/alpha";
                  }
                  {
                    name = "beta";
                    path = "~/vaults/alpha-other";
                  }
                ];
                dotfiles.neovim.obsidian = {
                  dailyNotes = {
                    folder = "Journal";
                    dateFormat = "%Y/%m/%Y-%m-%d-%A";
                  };
                  templates.folder = "Templates";
                  notesSubdir = "Inbox";
                  capture = {
                    enable = true;
                    questionsFolder = "Knowledge/Questions";
                    questionTemplate = "Question.md";
                    logHeading = "## Activity";
                  };
                  references = {
                    enable = true;
                    peopleFolder = "Notes/People";
                  };
                  autosave.enable = false;
                };
              }
            ];
          };
          obsidianDisabledHome = homeConfigurations."${system}-personal".extendModules {
            modules = [
              {
                dotfiles.neovim.obsidian = {
                  capture = {
                    enable = false;
                    questionsFolder = "Questions";
                  };
                  references = {
                    enable = false;
                    peopleFolder = "People";
                  };
                };
              }
            ];
          };
          obsidianNoWorkspaceHome = homeConfigurations."${system}-work".extendModules {
            modules = [
              {
                profile.obsidian.vaults = lib.mkForce [ ];
                dotfiles.neovim.obsidian = {
                  capture.enable = true;
                  references.enable = true;
                  periodic.enable = true;
                };
              }
            ];
          };
        in
        {
          home-personal = homeConfigurations."${system}-personal".activationPackage;
          home-work = homeConfigurations."${system}-work".activationPackage;
          profile-obsidian = import ./tests/profile-obsidian.nix {
            inherit
              darwinConfigurations
              homeConfigurations
              lib
              pkgs
              system
              ;
          };
          rex-worker-labels =
            pkgs.runCommand "rex-worker-labels-check"
              {
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.gawk
                  pkgs.jq
                  pkgs.python3
                ];
              }
              ''
                export PATH="${pkgs.bashNonInteractive}/bin:$PATH"
                python ${./tests/rex-label-window.py} ${../.}
                touch "$out"
              '';
          pi-coordinator = import ./tests/pi-coordinator.nix {
            home = homeConfigurations."${system}-work";
            inherit lib pkgs;
          };
          obsidian-quickadd =
            pkgs.runCommand "obsidian-quickadd-check" { nativeBuildInputs = [ pkgs.nodejs ]; }
              ''
                QUESTION_SCRIPT=${../obsidian/quickadd/new-question.js} \
                DOTFILES_OBSIDIAN_LOG_CASES=${./tests/question-log-cases.json} \
                  node --test ${./tests/new-question.test.cjs}
                touch "$out"
              '';
          git-readonly =
            pkgs.runCommand "git-readonly-check"
              {
                nativeBuildInputs = [
                  pkgs.git
                  pkgs.python3
                ];
              }
              ''
                python ${./tests/git-readonly.py} ${../bin/git-readonly.py}
                touch "$out"
              '';
          guardrails-rules =
            pkgs.runCommand "guardrails-rules-check" { nativeBuildInputs = [ pkgs.nodejs ]; }
              ''
                GUARDRAILS_RULES=${
                  pkgs.writeText "guardrails.json" (builtins.toJSON (import ./modules/home/pi/guardrails.nix { }))
                } \
                GUARDRAILS_RULES_INFRA=${
                  pkgs.writeText "guardrails-infra.json" (
                    builtins.toJSON (import ./modules/home/pi/guardrails.nix { gateInfraChanges = true; })
                  )
                } \
                  node --test ${./tests/guardrails-rules.test.cjs}
                touch "$out"
              '';
          rebuild-source =
            let
              inlineShellLibrary = import ./lib/inline-shell-library.nix { inherit lib; };
              script = pkgs.writeText "rebuild" (inlineShellLibrary ../bin/rebuild ../bin/lib/profile.sh);
            in
            pkgs.runCommand "rebuild-source-check" { nativeBuildInputs = [ pkgs.git ]; } ''
              ${pkgs.stdenv.shell} ${./tests/rebuild-source.sh} ${script}
              touch "$out"
            '';
          pi-profile-options = import ./tests/pi-profile-options.nix {
            home = homeConfigurations."${system}-personal";
            inherit lib pkgs;
          };
          marksman-binary = pkgs.runCommand "marksman-binary-check" { } ''
            ${pkgs.python3}/bin/python ${./tests/marksman-lsp.py} ${lib.getExe pkgs.marksman}
            touch "$out"
          '';
          obsidian-capture = pkgs.runCommand "obsidian-capture-check" { } ''
            run_profile_state() {
              state="$1"
              config="$2"
              pack="$3"
              profile_home="$TMPDIR/$state/home"
              export HOME="$profile_home"
              export XDG_CONFIG_HOME="$profile_home/.config"
              export XDG_DATA_HOME="$profile_home/.local/share"
              export XDG_STATE_HOME="$profile_home/.local/state"
              export XDG_CACHE_HOME="$profile_home/.cache"
              mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack"
              ln -s "$config" "$XDG_CONFIG_HOME/nvim"
              ln -s "$pack" "$XDG_DATA_HOME/nvim/site/pack/hm"
              DOTFILES_OBSIDIAN_EXPECT_STATE="$state" \
                ${lib.getExe homeConfigurations."${system}-personal".config.programs.neovim.finalPackage} \
                --headless -i NONE -n -c 'lua dofile("${./tests/obsidian-profile-state-test.lua}")'
            }

            run_profile_state \
              disabled \
              ${obsidianDisabledHome.config.dotfiles.neovim.finalConfigSource} \
              ${obsidianDisabledHome.config.xdg.dataFile."nvim/site/pack/hm".source}
            run_profile_state \
              no-workspace \
              ${obsidianNoWorkspaceHome.config.dotfiles.neovim.finalConfigSource} \
              ${obsidianNoWorkspaceHome.config.xdg.dataFile."nvim/site/pack/hm".source}

            export HOME="$TMPDIR/enabled/home"
            export XDG_CONFIG_HOME="$HOME/.config"
            export XDG_DATA_HOME="$HOME/.local/share"
            export XDG_STATE_HOME="$HOME/.local/state"
            export XDG_CACHE_HOME="$HOME/.cache"
            mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack"
            ln -s ${obsidianEnabledHome.config.dotfiles.neovim.finalConfigSource} "$XDG_CONFIG_HOME/nvim"
            ln -s ${
              obsidianEnabledHome.config.xdg.dataFile."nvim/site/pack/hm".source
            } "$XDG_DATA_HOME/nvim/site/pack/hm"
            DOTFILES_OBSIDIAN_LOG_CASES=${./tests/question-log-cases.json} \
              ${lib.getExe obsidianEnabledHome.config.programs.neovim.finalPackage} \
              --headless -i NONE -n -c 'lua dofile("${./tests/obsidian-capture-test.lua}")'
            touch "$out"
          '';
          obsidian-periodic =
            let
              home = homeConfigurations."${system}-work".extendModules {
                modules = [
                  {
                    profile.obsidian.vaults = lib.mkForce [
                      {
                        name = "first";
                        path = "~/vaults/first";
                      }
                      {
                        name = "second";
                        path = "~/vaults/second";
                      }
                    ];
                    dotfiles.neovim.obsidian = {
                      periodic.enable = true;
                      autosave.enable = false;
                    };
                  }
                ];
              };
            in
            # The default must stay identical to the desktop plugin's data.json.
            assert lib.assertMsg (
              home.config.dotfiles.neovim.obsidian.periodic.settings
              == lib.importJSON ./tests/periodic-notes-desktop.json
            ) "default periodic settings differ from the desktop data.json";
            pkgs.runCommand "obsidian-periodic-check" { } ''
              # Vault roots must be canonical, so resolve any symlinked TMPDIR.
              export HOME="$(cd "$TMPDIR" && pwd -P)/home"
              export XDG_CONFIG_HOME="$HOME/.config"
              export XDG_DATA_HOME="$HOME/.local/share"
              export XDG_STATE_HOME="$HOME/.local/state"
              export XDG_CACHE_HOME="$HOME/.cache"
              mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack" "$HOME/vaults/first" "$HOME/vaults/second"
              ln -s ${home.config.dotfiles.neovim.finalConfigSource} "$XDG_CONFIG_HOME/nvim"
              ln -s ${home.config.xdg.dataFile."nvim/site/pack/hm".source} "$XDG_DATA_HOME/nvim/site/pack/hm"
              cd "$TMPDIR"
              ${lib.getExe home.config.programs.neovim.finalPackage} \
                --headless -i NONE -n -c 'lua dofile("${./tests/obsidian-periodic-test.lua}")'
              touch "$out"
            '';
          obsidian-bases =
            let
              home = obsidianEnabledHome.extendModules {
                modules = [ { dotfiles.neovim.tooling.web.enable = false; } ];
              };
            in
            pkgs.runCommand "obsidian-bases-check" { } ''
              export HOME="$TMPDIR/home"
              export XDG_CONFIG_HOME="$HOME/.config"
              export XDG_DATA_HOME="$HOME/.local/share"
              export XDG_STATE_HOME="$HOME/.local/state"
              export XDG_CACHE_HOME="$HOME/.cache"
              mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME/nvim/site/pack"
              ln -s ${home.config.dotfiles.neovim.finalConfigSource} "$XDG_CONFIG_HOME/nvim"
              ln -s ${home.config.xdg.dataFile."nvim/site/pack/hm".source} "$XDG_DATA_HOME/nvim/site/pack/hm"
              ${lib.getExe home.config.programs.neovim.finalPackage} \
                --headless -i NONE -n -c 'lua dofile("${./tests/obsidian-bases-test.lua}")'
              touch "$out"
            '';
          neovim-cached-plugins =
            let
              home = homeConfigurations."${system}-personal";
              upstreamPkgs = import nixpkgs {
                inherit system;
                config = nixpkgsConfig;
              };
              grammarNames = pkgs.writeText "neovim-test-grammars.json" (
                builtins.toJSON home.config.dotfiles.neovim.treesitterGrammars
              );
            in
            assert lib.all (name: pkgs.vimPlugins.${name}.drvPath == upstreamPkgs.vimPlugins.${name}.drvPath) [
              "flash-nvim"
              "blink-cmp"
              "codediff-nvim"
              "nvim-treesitter"
            ];
            pkgs.runCommand "neovim-cached-plugins-check" { } ''
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
          neovim-cache-namespace =
            let
              home = homeConfigurations."${system}-personal";
            in
            pkgs.runCommand "neovim-cache-namespace-check" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              DOTFILES_NVIM=${lib.getExe home.config.programs.neovim.finalPackage} \
                DOTFILES_NVIM_CONFIG=${home.config.dotfiles.neovim.finalConfigSource} \
                DOTFILES_NVIM_PACK=${home.config.xdg.dataFile."nvim/site/pack/hm".source} \
                node --test ${./tests/neovim-cache-namespace.test.cjs}
              touch "$out"
            '';
        }
      ))
      {
        aarch64-darwin = {
          darwin-personal = darwinConfigurations.personal.config.system.build.toplevel;
          darwin-work = darwinConfigurations.work.config.system.build.toplevel;
          darwin-m5 = darwinConfigurations.m5.config.system.build.toplevel;
          yabai-signed-app = m5Pkgs.runCommand "yabai-signed-app-check" { } ''
            app=${m5YabaiPackage}/Applications/Yabai.app
            executable="$app/Contents/MacOS/yabai"

            test -x "$executable"
            /usr/bin/lipo "$executable" -verify_arch arm64
            test "$(/usr/bin/lipo -archs "$executable")" = arm64
            test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = \
              com.markfeinstein.yabai
            /usr/bin/codesign --verify --deep --strict "$app"
            /usr/bin/codesign -dv --verbose=4 "$app" 2>&1 \
              | ${m5Pkgs.gnugrep}/bin/grep -Fx 'TeamIdentifier=GYXXG6S7KM'
            touch "$out"
          '';
          rex-app-bundle = m5Pkgs.runCommand "rex-app-bundle-check" { } ''
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
in
{
  overlays.default = overlay;

  packages = lib.genAttrs systems (
    system:
    let
      pkgs = pkgsFor system;
    in
    {
      inherit (pkgs)
        git-project
        git-readonly
        marksman
        ;
    }
  );

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

  formatter = lib.genAttrs systems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
}
