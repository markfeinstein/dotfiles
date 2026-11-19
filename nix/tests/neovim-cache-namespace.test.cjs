const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const neovim = process.env.DOTFILES_NVIM;
const config = process.env.DOTFILES_NVIM_CONFIG;
const pack = process.env.DOTFILES_NVIM_PACK;
assert.ok(neovim, 'Set DOTFILES_NVIM to the built Neovim wrapper');
assert.ok(config, 'Set DOTFILES_NVIM_CONFIG to the built Neovim config source');
assert.ok(pack, 'Set DOTFILES_NVIM_PACK to the built Home Manager plugin pack');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'neovim-cache-namespace-'));
  t.after(() => fs.rmSync(root, { recursive: true }));
  const configHome = path.join(root, 'config');
  fs.mkdirSync(configHome);
  return {
    root,
    link: path.join(configHome, 'nvim'),
    env: {
      ...process.env,
      XDG_CONFIG_HOME: configHome,
      XDG_DATA_HOME: path.join(root, 'data'),
      XDG_CACHE_HOME: path.join(root, 'cache'),
      XDG_STATE_HOME: path.join(root, 'state'),
      NVIM_LOG_FILE: path.join(root, 'nvim.log'),
    },
  };
}

function pointConfig(f, target) {
  if (fs.existsSync(f.link)) fs.unlinkSync(f.link);
  fs.symlinkSync(target, f.link, 'dir');
}

function run(f, expression, { baseline = false, plugins = false } = {}) {
  const args = ['--headless', '-i', 'NONE', '-n'];
  if (!plugins) args.push('--noplugin');
  if (baseline) {
    // Reproduce the old loader's shared cache after the real wrapper bootstrap,
    // but before init.lua enables caching. Only this temporary fixture is used.
    args.push('--cmd', 'lua vim.loader.path = vim.fn.stdpath("cache") .. "/luac"');
  }
  args.push(`+lua print("CACHE_TEST=" .. vim.json.encode(${expression}))`, '+qa!');
  const result = spawnSync(neovim, args, {
    env: f.env,
    cwd: f.root,
    encoding: 'utf8',
    timeout: 15000,
  });
  assert.ifError(result.error);
  const output = result.stdout + result.stderr;
  assert.equal(result.status, 0, output);
  assert.doesNotMatch(output, /Error (in|detected)|E\d{3,}:/, output);
  const match = output.match(/CACHE_TEST=([^\r\n]+)/);
  assert.ok(match, output);
  return JSON.parse(match[1]);
}

const probeResult = `{
  marker = require("cache_probe"),
  cache = vim.loader.path,
  enabled = vim.loader.enabled,
  old_map = vim.fn.maparg("<leader>mq", "n") ~= "",
  new_map = vim.fn.maparg("<leader>oq", "n") ~= "",
}`;

function generation(f, name, lhs, marker) {
  const root = path.join(f.root, name);
  fs.mkdirSync(path.join(root, 'lua'), { recursive: true });
  fs.writeFileSync(path.join(root, 'init.lua'), [
    'vim.g.mapleader = " "',
    'vim.loader.enable()',
    'require("cache_probe")',
    '',
  ].join('\n'));
  const probe = path.join(root, 'lua', 'cache_probe.lua');
  fs.writeFileSync(probe, [
    `vim.keymap.set("n", "<leader>${lhs}", "<Nop>", { desc = "New Question Note" })`,
    `return "${marker}"`,
    '',
  ].join('\n'));
  // Nix store files all have the same timestamp; m -> o preserves file size.
  fs.utimesSync(probe, 1, 1);
  return { root, probe };
}

test('same-size Nix-like config changes cannot reuse stale bytecode', (t) => {
  const f = fixture(t);
  const a = generation(f, 'store-config-a', 'mq', 'old');
  const b = generation(f, 'store-config-b', 'oq', 'new');
  assert.equal(fs.statSync(a.probe).size, fs.statSync(b.probe).size);
  assert.equal(fs.statSync(a.probe).mtimeMs, fs.statSync(b.probe).mtimeMs);

  pointConfig(f, a.root);
  assert.equal(run(f, probeResult, { baseline: true }).marker, 'old');
  pointConfig(f, b.root);
  const stale = run(f, probeResult, { baseline: true });
  assert.equal(stale.marker, 'old', 'Control reproduces the observed stale-cache bug');
  assert.equal(stale.old_map, true);
  assert.equal(stale.new_map, false);

  // The actual built wrapper must bypass the stale legacy cache without deleting it.
  const fixed = run(f, probeResult);
  const hash = createHash('sha256').update(fs.realpathSync(f.link)).digest('hex');
  assert.equal(fixed.cache, path.join(f.env.XDG_CACHE_HOME, 'nvim', 'luac', hash));
  assert.equal(fixed.marker, 'new');
  assert.equal(fixed.enabled, true, 'Caching stays enabled');
  assert.equal(fixed.old_map, false);
  assert.equal(fixed.new_map, true);
  assert.notEqual(fixed.cache, stale.cache);
  assert.ok(fs.readdirSync(stale.cache).some(name => name.includes('cache_probe')));

  const bytecode = fs.readdirSync(fixed.cache).filter(name => name.includes('cache_probe'));
  assert.equal(bytecode.length, 1, 'Native loader writes into the selected namespace');
  const cachedFile = path.join(fixed.cache, bytecode[0]);
  const mtime = fs.statSync(cachedFile, { bigint: true }).mtimeNs;
  assert.deepEqual(run(f, probeResult), fixed, 'Same config reuses the namespace');
  assert.equal(fs.statSync(cachedFile, { bigint: true }).mtimeNs, mtime, 'Valid bytecode is not rewritten');

  pointConfig(f, a.root);
  const rollback = run(f, probeResult);
  assert.equal(rollback.marker, 'old');
  assert.notEqual(rollback.cache, fixed.cache);
  pointConfig(f, b.root);
  assert.deepEqual(run(f, probeResult), fixed, 'Switching back safely reuses the correct namespace');
});

test('built wrapper and config select the namespace on a full startup', (t) => {
  const f = fixture(t);
  pointConfig(f, config);
  const site = path.join(f.env.XDG_DATA_HOME, 'nvim', 'site', 'pack');
  fs.mkdirSync(site, { recursive: true });
  fs.symlinkSync(pack, path.join(site, 'hm'), 'dir');
  const result = run(f, `{ cache = vim.loader.path, enabled = vim.loader.enabled }`, { plugins: true });
  const hash = createHash('sha256').update(fs.realpathSync(f.link)).digest('hex');
  assert.equal(result.cache, path.join(f.env.XDG_CACHE_HOME, 'nvim', 'luac', hash));
  assert.equal(result.enabled, true);
  assert.ok(fs.readdirSync(result.cache).length > 0, 'Shared config modules are cached in the namespace');
});
