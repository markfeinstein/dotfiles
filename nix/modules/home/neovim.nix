{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.dotfiles.neovim;

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

  neovimTreesitter =
    pkgs.vimPlugins.nvim-treesitter.withPlugins (grammars:
      map (name: grammars.${name}) cfg.treesitterGrammars);

  neovimRuntimeEnv = pkgs.buildEnv {
    name = "neovim-runtime-tools";
    paths = cfg.runtimePackages;
    pathsToLink = ["/bin"];
  };

  profileLua = pkgs.writeText "dotfiles-neovim-profile.lua" (
    lib.concatStringsSep "\n" (
      [
        "vim.g.dotfiles_neovim_ai_enabled = ${
          if cfg.features.ai
          then "true"
          else "false"
        }"
        "vim.g.dotfiles_neovim_tooling = vim.json.decode([==[${builtins.toJSON toolingState}]==])"
        "vim.g.dotfiles_obsidian_workspaces = vim.json.decode([==[${builtins.toJSON cfg.obsidian.workspaces}]==])"
        "return true"
      ]
      ++ lib.optional (cfg.extraLuaConfig != "") cfg.extraLuaConfig
    )
    + "\n"
  );

  configSource = pkgs.runCommand "dotfiles-neovim-config" {} ''
    cp -R ${../../../nvim} "$out"
    chmod -R u+w "$out"
    ${lib.optionalString (!cfg.features.ai) ''
      rm -f "$out/plugin/codecompanion.lua"
    ''}
    install -m 0644 ${profileLua} "$out/lua/mark/profile.lua"
    mkdir -p "$out/themes"
    ln -s ${../../../themes/rose-pine.json} "$out/themes/rose-pine.json"
  '';
in {
  options.dotfiles.neovim = {
    features.ai = lib.mkEnableOption "CodeCompanion and Copilot integration";

    tooling = {
      documents.enable = lib.mkEnableOption "document, image, diagram, and TeX rendering tools" // {default = true;};
      go.enable = lib.mkEnableOption "Go formatting, language-server, linting, testing, and debugging tools" // {default = true;};
      infrastructure.enable = lib.mkEnableOption "Docker, Protobuf, and Terraform language tools" // {default = true;};
      rust.enable = lib.mkEnableOption "Rust formatting and language-server tools" // {default = true;};
      sql.enable = lib.mkEnableOption "SQL language-server and linting tools" // {default = true;};
      web.enable = lib.mkEnableOption "web formatting and language-server tools" // {default = true;};
    };

    obsidian.workspaces = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Obsidian workspace name";
          };
          path = lib.mkOption {
            type = lib.types.str;
            description = "Absolute or home-relative Obsidian vault path";
          };
        };
      });
      default = [];
      description = "Profile-owned Obsidian vault workspaces";
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
        assertion = lib.all (workspace:
          lib.hasPrefix "/" workspace.path || lib.hasPrefix "~/" workspace.path)
        cfg.obsidian.workspaces;
        message = "dotfiles.neovim.obsidian.workspaces paths must be absolute or start with ~/";
      }
      {
        assertion =
          lib.length (lib.unique (map (workspace: workspace.name) cfg.obsidian.workspaces))
          == lib.length cfg.obsidian.workspaces;
        message = "dotfiles.neovim.obsidian.workspaces names must be unique";
      }
    ];

    dotfiles.neovim.finalConfigSource = configSource;

    programs.neovim = {
      enable = true;
      package = pkgs.neovim;
      defaultEditor = true;
      sideloadInitLua = true;
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
