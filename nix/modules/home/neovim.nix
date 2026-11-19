{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.neovim;
  jsonFormat = pkgs.formats.json { };

  # Periodic Notes (desktop) uses Moment tokens; obsidian.nvim uses strftime.
  # Only these tokens are translated, so other daily formats fail the assertion.
  momentDailyFormat =
    lib.replaceStrings
      [ "%Y" "%m" "%B" "%d" "%A" ]
      [ "YYYY" "MM" "MMMM" "DD" "dddd" ]
      cfg.obsidian.dailyNotes.dateFormat;
  periodicDaily = cfg.obsidian.periodic.settings.daily or { };
  periodicDailyMatches =
    !(periodicDaily.enabled or false)
    || (
      (periodicDaily.folder or null) == cfg.obsidian.dailyNotes.folder
      && (periodicDaily.format or null) == momentDailyFormat
    );

  baseTreesitterGrammars = [
    "bash"
    "cmake"
    "comment"
    "cpp"
    "css"
    "csv"
    "dockerfile"
    "editorconfig"
    "fish"
    "git_config"
    "git_rebase"
    "gitcommit"
    "go"
    "gomod"
    "gosum"
    "gowork"
    "gotmpl"
    "graphql"
    "hcl"
    "html"
    "http"
    "ini"
    "javascript"
    "jsdoc"
    "json"
    "jq"
    "just"
    "latex"
    "luadoc"
    "luap"
    "make"
    "markdown"
    "markdown_inline"
    "mermaid"
    "nginx"
    "nix"
    "nu"
    "proto"
    "python"
    "query"
    "regex"
    "rst"
    "rust"
    "scss"
    "sql"
    "ssh_config"
    "terraform"
    "toml"
    "tsx"
    "typescript"
    "typst"
    "vim"
    "xml"
    "yaml"
    "zsh"
  ];

  coreRuntimePackages = [
    # Core plugin and picker dependencies.
    pkgs.fd
    pkgs.fzf
    pkgs.gh
    pkgs.git
    pkgs.ripgrep

    # Core formatters and linters.
    pkgs.alejandra
    pkgs.nufmt
    pkgs.shellcheck
    pkgs.shfmt
    pkgs.stylua

    # Core language servers and required runtimes.
    pkgs.bash-language-server
    pkgs.lua-language-server
    pkgs.marksman
    pkgs.nix
    pkgs.nixd
    # Required by the fork's local Bases evaluator, independent of web tooling.
    pkgs.nodejs
    pkgs.nushell
    pkgs.yaml-language-server
  ];

  goRuntimePackages = [
    pkgs.delve
    pkgs.go
    pkgs.gofumpt
    pkgs.goimports-reviser
    pkgs.golangci-lint
    pkgs.gopls
    pkgs.gotestsum
  ];

  rustRuntimePackages = [
    pkgs.rust-analyzer
    pkgs.rustfmt
  ];

  webRuntimePackages = [
    pkgs.htmx-lsp
    pkgs.prettier
    pkgs.tailwindcss-language-server
    pkgs.typescript-language-server
    pkgs.vscode-langservers-extracted
  ];

  infrastructureRuntimePackages = [
    pkgs.buf
    pkgs.docker-language-server
    pkgs.terraform-ls
  ];

  sqlRuntimePackages = [
    pkgs.sqlfluff
    pkgs.sqls
  ];

  documentRuntimePackages = [
    pkgs.ghostscript
    pkgs.imagemagick
    pkgs.mermaid-cli
    pkgs.tectonic
  ];

  groupedRuntimePackages =
    lib.optionals cfg.tooling.go.enable goRuntimePackages
    ++ lib.optionals cfg.tooling.rust.enable rustRuntimePackages
    ++ lib.optionals cfg.tooling.web.enable webRuntimePackages
    ++ lib.optionals cfg.tooling.infrastructure.enable infrastructureRuntimePackages
    ++ lib.optionals cfg.tooling.sql.enable sqlRuntimePackages
    ++ lib.optionals cfg.tooling.documents.enable documentRuntimePackages;

  baseStartPlugins = [
    pkgs.vimPlugins.flash-nvim
    pkgs.vimPlugins.mini-nvim
    pkgs.vimPlugins.oil-nvim
    pkgs.vimPlugins.snacks-nvim
  ];

  basePlugins = [
    pkgs.vimPlugins.lazydev-nvim
    pkgs.vimPlugins.fzf-lua
    pkgs.vimPlugins.plenary-nvim
    pkgs.vimPlugins.nui-nvim
    pkgs.vimPlugins.which-key-nvim
    pkgs.vimPlugins.blink-cmp
    pkgs.vimPlugins.blink-emoji-nvim
    pkgs.vimPlugins.blink-nerdfont-nvim
    pkgs.vimPlugins.nvim-treesitter-textobjects
    pkgs.vimPlugins.codediff-nvim
    pkgs.vimPlugins.conform-nvim
    pkgs.vimPlugins.dial-nvim
    pkgs.vimPlugins.neogit
    pkgs.vimPlugins.neotest
    pkgs.vimPlugins.neotest-golang
    pkgs.vimPlugins.nvim-coverage
    pkgs.vimPlugins.nvim-dap
    pkgs.vimPlugins.nvim-dap-go
    pkgs.vimPlugins.nvim-dap-view
    pkgs.vimPlugins.nvim-dap-virtual-text
    pkgs.vimPlugins.nvim-lint
    pkgs.vimPlugins.nvim-lspconfig
    pkgs.vimPlugins.nvim-nio
    pkgs.vimPlugins.obsidian-nvim
    pkgs.vimPlugins.octo-nvim
    pkgs.vimPlugins.render-markdown-nvim
    pkgs.vimPlugins.trouble-nvim
  ];

  aiPlugins = [
    pkgs.vimPlugins.codecompanion-history-nvim
    pkgs.vimPlugins.codecompanion-nvim
    pkgs.vimPlugins.copilot-lua
  ];

  toolingState = {
    documents = cfg.tooling.documents.enable;
    go = cfg.tooling.go.enable;
    infrastructure = cfg.tooling.infrastructure.enable;
    rust = cfg.tooling.rust.enable;
    sql = cfg.tooling.sql.enable;
    web = cfg.tooling.web.enable;
  };

  neovimTreesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    grammars: map (name: grammars.${name}) cfg.treesitterGrammars
  );

  neovimRuntimeEnv = pkgs.buildEnv {
    name = "neovim-runtime-tools";
    paths = cfg.runtimePackages;
    pathsToLink = [ "/bin" ];
  };

  obsidianConfig = {
    workspaces = config.profile.obsidian.vaults;
    daily_notes = {
      folder = cfg.obsidian.dailyNotes.folder;
      date_format = cfg.obsidian.dailyNotes.dateFormat;
    };
    notes_subdir = cfg.obsidian.notesSubdir;
    templates.folder = cfg.obsidian.templates.folder;
    capture = {
      enabled = cfg.obsidian.capture.enable;
      questions_folder = cfg.obsidian.capture.questionsFolder;
      question_template = cfg.obsidian.capture.questionTemplate;
      log_heading = cfg.obsidian.capture.logHeading;
    };
    references = {
      enabled = cfg.obsidian.references.enable;
      people_folder = cfg.obsidian.references.peopleFolder;
    };
    periodic = {
      enabled = cfg.obsidian.periodic.enable;
      inherit (cfg.obsidian.periodic) settings;
    };
    autosave = {
      enabled = cfg.obsidian.autosave.enable;
      interval_ms = cfg.obsidian.autosave.intervalSeconds * 1000;
    };
  };

  isVaultRelativePath =
    path:
    path != ""
    && !lib.hasPrefix "/" path
    && !lib.hasPrefix "~/" path
    && lib.all (part: part != "..") (lib.splitString "/" path);

  profileLua = pkgs.writeText "dotfiles-neovim-profile.lua" (
    lib.concatStringsSep "\n" (
      [
        "vim.g.dotfiles_neovim_ai_enabled = ${if cfg.features.ai then "true" else "false"}"
        "vim.g.dotfiles_neovim_tooling = ${lib.generators.toLua { } toolingState}"
        "vim.g.dotfiles_obsidian = ${lib.generators.toLua { } obsidianConfig}"
        "return true"
      ]
      ++ lib.optional (cfg.extraLuaConfig != "") cfg.extraLuaConfig
    )
    + "\n"
  );

  configSource = pkgs.runCommand "dotfiles-neovim-config" { } ''
    cp -R ${../../../nvim} "$out"
    chmod -R u+w "$out"
    ${lib.optionalString (!cfg.features.ai) ''
      rm -f "$out/plugin/codecompanion.lua"
    ''}
    install -m 0644 ${profileLua} "$out/lua/mark/profile.lua"
    mkdir -p "$out/themes"
    ln -s ${../../../themes/rose-pine.json} "$out/themes/rose-pine.json"
  '';
in
{
  options.dotfiles.neovim = {
    features.ai = lib.mkEnableOption "CodeCompanion and Copilot integration";

    tooling = {
      documents.enable = lib.mkEnableOption "document, image, diagram, and TeX rendering tools" // {
        default = true;
      };
      go.enable =
        lib.mkEnableOption "Go formatting, language-server, linting, testing, and debugging tools"
        // {
          default = true;
        };
      infrastructure.enable = lib.mkEnableOption "Docker, Protobuf, and Terraform language tools" // {
        default = true;
      };
      rust.enable = lib.mkEnableOption "Rust formatting and language-server tools" // {
        default = true;
      };
      sql.enable = lib.mkEnableOption "SQL language-server and linting tools" // {
        default = true;
      };
      web.enable = lib.mkEnableOption "web formatting and language-server tools" // {
        default = true;
      };
    };

    obsidian = {
      dailyNotes = {
        folder = lib.mkOption {
          type = lib.types.strMatching ".+";
          default = "1 - Journals";
          description = "Vault-relative folder for Obsidian daily notes";
        };
        dateFormat = lib.mkOption {
          type = lib.types.strMatching ".+";
          default = "%Y/%m-%B/%Y-%m-%d-%A";
          description = "strftime format for Obsidian daily-note paths";
        };
      };

      notesSubdir = lib.mkOption {
        type = lib.types.strMatching ".+";
        default = "0 - Inbox";
        description = "Vault-relative folder for new Obsidian notes";
      };

      templates.folder = lib.mkOption {
        type = lib.types.strMatching ".+";
        default = "8 - Resources/Templates";
        description = "Vault-relative folder for Obsidian templates";
      };

      capture = {
        enable = lib.mkEnableOption "Obsidian question, answer, and daily-log capture commands";
        questionsFolder = lib.mkOption {
          type = lib.types.strMatching ".+";
          default = "Questions";
          description = "Vault-relative folder containing question notes";
        };
        questionTemplate = lib.mkOption {
          type = lib.types.strMatching ".+";
          default = "Question.md";
          description = "Template path relative to the configured Obsidian templates folder";
        };
        logHeading = lib.mkOption {
          type = lib.types.strMatching "^#+[[:space:]]+.+";
          default = "## Log";
          description = "Markdown heading under which timestamped capture entries are inserted";
        };
      };

      references = {
        enable = lib.mkEnableOption "Obsidian people and capture-prompt reference completion";
        peopleFolder = lib.mkOption {
          type = lib.types.strMatching ".+";
          default = "People";
          description = "Vault-relative folder containing person notes";
        };
      };

      periodic = {
        enable = lib.mkEnableOption "weekly, monthly, quarterly, and yearly Obsidian note commands";
        settings = lib.mkOption {
          inherit (jsonFormat) type;
          default =
            let
              journals = cfg.obsidian.dailyNotes.folder;
              template = name: "${cfg.obsidian.templates.folder}/${name}";
            in
            {
              daily = {
                enabled = true;
                folder = journals;
                format = momentDailyFormat;
                template = template "Daily Note";
              };
              weekly = {
                enabled = true;
                folder = "${journals}/Weekly";
                format = "GGGG-[W]WW";
                template = template "Weekly Review";
              };
              monthly = {
                enabled = true;
                folder = "${journals}/Monthly";
                format = "YYYY-MM";
                template = template "Monthly Review";
              };
              quarterly = {
                enabled = true;
                folder = "${journals}/Quarterly";
                format = "YYYY-[Q]Q";
                template = template "Quarterly Review";
              };
              yearly = {
                enabled = true;
                folder = "${journals}/Annual";
                format = "YYYY";
                template = template "Annual Review";
              };
            };
          defaultText = lib.literalMD "weekly/monthly/quarterly/yearly folders under the daily-notes folder, with `<Interval> Review` templates";
          description = ''
            Obsidian Periodic Notes plugin settings (its `data.json`): vault-relative
            `folder`, Moment `format`, and extensionless `template` per interval.
            Use the same object as the desktop plugin, for example with
            `lib.importJSON`, so both editors create identical paths.
          '';
        };
      };

      autosave = {
        enable =
          lib.mkEnableOption "periodic writes of modified Markdown buffers in configured Obsidian vaults"
          // {
            default = true;
          };
        intervalSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = "Seconds between periodic Obsidian Markdown auto-saves";
        };
      };
    };

    runtimePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = coreRuntimePackages ++ groupedRuntimePackages;
      description = "Core and enabled tooling-group packages exposed only inside Neovim's wrapped PATH";
    };

    startPlugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = baseStartPlugins;
      description = "Neovim plugins loaded from the start package directory";
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = basePlugins;
      description = "Optional Neovim plugins available for explicit lazy loading";
    };

    treesitterGrammars = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = baseTreesitterGrammars;
      description = "Tree-sitter grammar attribute names";
    };

    extraLuaConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Profile-owned Lua appended to the packaged Neovim configuration";
    };

    finalConfigSource = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      description = "Store-managed Neovim configuration source";
    };
  };

  config = {
    assertions = [
      {
        assertion = lib.all isVaultRelativePath [
          cfg.obsidian.capture.questionsFolder
          cfg.obsidian.capture.questionTemplate
          cfg.obsidian.references.peopleFolder
        ];
        message = "Obsidian capture and reference paths must be vault-relative and may not contain '..' components";
      }
      {
        assertion = !cfg.obsidian.periodic.enable || periodicDailyMatches;
        message = "dotfiles.neovim.obsidian.periodic.settings.daily must use the dailyNotes folder and the Moment equivalent of dailyNotes.dateFormat";
      }
    ];

    dotfiles.neovim = {
      finalConfigSource = configSource;
      obsidian = {
        capture = {
          enable = lib.mkDefault true;
          questionsFolder = lib.mkDefault "2 - Notes/Knowledge/Questions";
        };
        references = {
          enable = lib.mkDefault true;
          peopleFolder = lib.mkDefault "2 - Notes/People";
        };
      };
    };

    programs.neovim = {
      enable = true;
      package = pkgs.neovim;
      defaultEditor = true;
      sideloadInitLua = true;
      # The sideloaded wrapper runs this before init.lua enables vim.loader, so
      # each immutable config target gets its own bytecode cache namespace.
      initLua = lib.mkBefore (builtins.readFile ./neovim/cache-namespace.lua);
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      extraWrapperArgs = [
        "--prefix"
        "PATH"
        ":"
        "${neovimRuntimeEnv}/bin"
        "--set"
        "DOTFILES_THEME_FILE"
        "${../../../themes/rose-pine.json}"
        "--set"
        "DOTFILES_NIX_PROFILE"
        config.profile.name
      ];

      plugins =
        cfg.startPlugins
        ++ [
          {
            plugin = neovimTreesitter;
            optional = true;
          }
        ]
        ++ (map (plugin: {
          inherit plugin;
          optional = true;
        }) (cfg.plugins ++ lib.optionals cfg.features.ai aiPlugins));
    };

    home.shellAliases.v = "nvim";
    xdg.configFile."nvim".source = configSource;
  };
}
