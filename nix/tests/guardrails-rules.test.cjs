// Runs the generated pi-guardrails permission-gate rules as pi-guardrails does:
// new RegExp(pattern) with no flags, tested against the raw command string.
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { test } = require("node:test");

const config = JSON.parse(readFileSync(process.env.GUARDRAILS_RULES, "utf8"));
const rules = config.permissionGate.patterns;
const allowed = config.permissionGate.allowedPatterns;

// pi-guardrails skips the gate for the whole command when any allowed pattern matches.
function isAllowed(command) {
  return allowed.some((rule) => (rule.regex ? new RegExp(rule.pattern).test(command) : command.includes(rule.pattern)));
}

function matchingRules(command) {
  return rules
    .filter((rule) => (rule.regex ? new RegExp(rule.pattern).test(command) : command.includes(rule.pattern)))
    .map((rule) => rule.description);
}

const GRAPHQL = "GitHub GraphQL API call with possible mutation";
const API_MUTATION = "GitHub issue or pull-request API mutation";

const inlineQuery =
  "gh api graphql -f query='{repository(owner:\"o\",name:\"r\"){pullRequest(number:1){reviewThreads(first:20){nodes{isResolved}}}}}'";

const noLongerMatch = {
  "inline read-only GraphQL query": [inlineQuery, GRAPHQL],
  "inline read-only GraphQL query with a jq pipe": [`${inlineQuery} --jq '.data|.repository'`, GRAPHQL],
  "inline read-only GraphQL query with options before graphql": [
    "gh api -H 'X-Test: 1' graphql -f query='{viewer{login}}'",
    GRAPHQL,
  ],
  "inline query with a GraphQL variable and a shell-expanded field": [
    "gh api graphql -f query='query($o: String!){viewer{login}}' -f o=\"$o\"",
    GRAPHQL,
  ],
  "inline query with an expansion inside the text": [
    'gh api graphql -f query="{repository(owner:\\"$o\\",name:\\"r\\"){id}}"',
    GRAPHQL,
  ],
  "explicit GET search": ["gh api --method GET search/issues -f 'q=repo:o/r is:pr'", API_MUTATION],
  "--method=GET search": ["gh api --method=GET search/issues -f 'q=repo:o/r is:pr'", API_MUTATION],
  "-X GET search": ["gh api -X GET repos/o/r/issues -f state=open", API_MUTATION],
  "GET after the endpoint": ["gh api repos/o/r/pulls -f state=open --method GET", API_MUTATION],
};

const stillMatch = {
  "inline mutation loop": [
    'for t in a b; do gh api graphql -f query="mutation{resolveReviewThread(input:{threadId:\\"$t\\"}){thread{id}}}"; done',
    GRAPHQL,
  ],
  "inline named mutation": ["gh api graphql -f query='mutation Resolve($id: ID!) { x }'", GRAPHQL],
  "mutation after a jq pipe": ["gh api graphql --jq '.a|.b' -f query='mutation{x}'", GRAPHQL],
  "mutation text built in an earlier statement": ["q='mutation{x}'; gh api graphql -f query=\"$q\"", GRAPHQL],
  "query from a file with -F": ["gh api graphql -F query=@mutation.graphql", GRAPHQL],
  "query from a file with --field": ["gh api graphql --field query=@mutation.graphql", GRAPHQL],
  "query from a file with --field=": ["gh api graphql --field=query=@mutation.graphql", GRAPHQL],
  "query from stdin": ["gh api graphql -F query=@- < mutation.graphql", GRAPHQL],
  "query file after a jq pipe": ["gh api graphql --jq '.a|.b' -F query=@mutation.graphql", GRAPHQL],
  "query from a shell variable in double quotes": ['gh api graphql -f query="$q"', GRAPHQL],
  "query from a bare shell variable": ["gh api graphql -f query=$q", GRAPHQL],
  "query from a braced shell variable": ['gh api graphql -f query="${q}"', GRAPHQL],
  "query from a command substitution": ['gh api graphql -F query="$(cat x.graphql)"', GRAPHQL],
  "query from a backtick substitution": ["gh api graphql -f query=`cat x.graphql`", GRAPHQL],
  "query from --raw-field and a variable": ["gh api graphql --raw-field query=$Q", GRAPHQL],
  "query from --raw-field= and a variable": ["gh api graphql --raw-field=query=$Q", GRAPHQL],
  "query from --field and a variable": ['gh api graphql --field query="$Q"', GRAPHQL],
  "query from an attached -f and a variable": ["gh api graphql -fquery=$q", GRAPHQL],
  "query variable after a jq pipe": ["gh api graphql --jq '.a|.b' -f query=\"$q\"", GRAPHQL],
  "request body from a file": ["gh api graphql --input body.json", GRAPHQL],
  "request body from stdin": ["cat body.json | gh api graphql --input -", GRAPHQL],
  "explicit POST": ["gh api -X POST repos/o/r/issues/1/comments -f body=x", API_MUTATION],
  "explicit PATCH after the endpoint": ["gh api repos/o/r/pulls/1 -X PATCH -f title=x", API_MUTATION],
  "explicit --method DELETE": ["gh api --method DELETE repos/o/r/issues/comments/1", API_MUTATION],
  "implicit POST from -f": ["gh api repos/o/r/issues/1/comments -f body=x", API_MUTATION],
  "implicit POST from --field": ["gh api repos/o/r/issues/1/comments --field body=x", API_MUTATION],
  "implicit POST from --input": ["gh api repos/o/r/pulls/1/comments --input body.json", API_MUTATION],
  "GET followed by a mutating method": ["gh api -X GET -X POST repos/o/r/issues/1/comments -f body=x", API_MUTATION],
  "GET in an earlier segment only": [
    "gh api --method GET repos/o/r/issues; gh api repos/o/r/issues/1/comments -f body=x",
    API_MUTATION,
  ],
};

for (const [name, [command, rule]] of Object.entries(noLongerMatch)) {
  test(`no longer matches: ${name}`, () => {
    assert.ok(!matchingRules(command).includes(rule), `${rule} still matches: ${command}`);
  });
}

for (const [name, [command, rule]] of Object.entries(stillMatch)) {
  test(`still matches: ${name}`, () => {
    assert.ok(matchingRules(command).includes(rule), `${rule} no longer matches: ${command}`);
  });
}

test("plain read-only gh api calls match no rule", () => {
  for (const command of [
    "gh api repos/o/r/pulls/1 --jq .updated_at",
    "gh api --paginate repos/o/r/issues/1/comments --jq '.[]|.id'",
    "gh api user --jq .login",
    "gh pr view 1 -R o/r --json state",
  ]) {
    assert.deepEqual(matchingRules(command), [], command);
  }
});

test("recursive deletes of scratch paths under /tmp skip the gate", () => {
  for (const command of [
    "rm -rf /tmp/sr-scan",
    "rm -fr /tmp/pi-review/out",
    "rm -r -f /private/tmp/pi-addon-trial.7j8TNi",
    "rm --recursive --force -- /tmp/a /tmp/b.c",
    "rm -rfv /tmp/calmeet-test",
    "  rm -rf /tmp/x  ",
  ]) {
    assert.ok(isAllowed(command), command);
  }
});

test("other recursive deletes still need confirmation", () => {
  for (const command of [
    "rm -rf /tmp",
    "rm -rf /tmp/",
    "rm -rf /tmp/*",
    "rm -rf /tmp/link/",
    "rm -rf /tmp/..",
    "rm -rf /tmp/x/../../etc",
    "rm -rf /tmp/x/.",
    "rm -rf /tmp/x ~/dev",
    "rm -rf /tmp/x /",
    "rm -rf tmp/x",
    "rm -rf /tmpfoo",
    "rm -rf /var/tmp/x",
    'rm -rf "$TMPDIR"/x',
    "rm -rf /tmp/$x",
    "rm -rf /tmp/x && ls /tmp/x",
    "rm -rf /tmp/x; sudo ls",
    "rm -rf /tmp/x\nsudo ls",
    "rm -rf /tmp/x | tee log",
    "rm -rf /tmp/x $(echo /)",
    "echo hi; rm -rf /tmp/x",
    "sudo rm -rf /tmp/x",
    "rm -rf /tmp/x 2>/dev/null",
  ]) {
    assert.ok(!isAllowed(command), command);
  }
});

const destructiveGit = {
  "Git force-push or remote ref deletion": [
    "git push --force origin main",
    "git push -f",
    "git push -uf origin x",
    "git push --force-with-lease",
    "git push --force-with-lease=main:abc origin main",
    "git -C ~/dev/repo push origin +main",
    "git push origin :old-branch",
    "git push --delete origin old-branch",
    "git push -d origin old-branch",
    "git push --mirror",
    "cd repo && git push --force",
  ],
  "Git hard reset": ["git reset --hard", "git reset --hard origin/main", "git -C repo reset --hard HEAD~1"],
  "Git clean that deletes files": ["git clean -fd", "git clean -xdf", "git clean --force", "git clean -f;"],
  "Git branch force delete": [
    "git branch -D feature",
    "git branch -d -f feature",
    "git branch -df feature",
    "git branch --delete --force feature",
  ],
  "Git stash drop or clear": ["git stash drop", "git stash drop stash@{1}", "git stash clear"],
  "Git worktree force removal": ["git worktree remove --force ../wt", "git worktree remove -f ../wt"],
  "Worktrunk force flag": [
    "wt remove --force ../x",
    "wt remove -D feat/x",
    "wt -C ~/dev/repo remove --force-delete feat/x",
    "wt switch --clobber feat/x",
    "wt remove -f",
  ],
};

for (const [rule, commands] of Object.entries(destructiveGit)) {
  test(`gates: ${rule}`, () => {
    for (const command of commands) {
      assert.ok(matchingRules(command).includes(rule), command);
    }
  });
}

test("everyday Git and Worktrunk commands are not gated", () => {
  for (const command of [
    "git push",
    "git push -u origin feat/x",
    "git push origin HEAD:main",
    "git push --dry-run origin main",
    "git reset --soft HEAD~1",
    "git reset HEAD file",
    "git clean -n",
    "git branch -d merged",
    "git branch --list 'fix/*' -v",
    "git branch --format='%(refname)' --sort=-committerdate",
    "git stash list",
    "git stash pop",
    "git worktree remove ../wt",
    "git restore --source=HEAD --worktree -- flake.lock",
    "git checkout -- file",
    "git commit -m 'feat: x' && git push",
    "git log --format='%an <%ae>' -1",
    "git-readonly log --oneline -3",
    "rg 'git reset --hard' docs",
    "wt list --format=json",
    "wt remove --foreground --format=json ../x",
    "wt -C ~/dev/repo step push --format=json main",
    "wt merge --no-commit --no-rebase --no-remove --format=json main",
  ]) {
    assert.deepEqual(matchingRules(command), [], command);
  }
});

test("unrelated rules are unchanged", () => {
  assert.ok(matchingRules("sudo ls").includes("superuser command"));
  assert.ok(matchingRules("rm -rf build").includes("recursive force delete"));
  assert.ok(matchingRules("gh issue close 1").includes("GitHub issue command outside read-only allow-list"));
  assert.ok(matchingRules("gh pr merge 1").includes("GitHub pull-request command outside read-only allow-list"));
  assert.deepEqual(matchingRules("gh issue list"), []);
  assert.deepEqual(matchingRules("gh pr view 1"), []);
});
