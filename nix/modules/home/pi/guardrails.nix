{
  # Also gate live Kubernetes, Terraform, Helm, AWS and Google Cloud changes.
  gateInfraChanges ? false,
}:
let
  ghApiCommand = ''(?:^|[;&|(){}\s])gh(?:\s+(?:-[^\s;&|(){}]+|--[^\s;&|(){}]+)(?:[=\s]+(?:"[^"]*"|'[^']*'|[^\s;&|(){}]+))?)*\s+api\b'';
  # The rest of the current command segment, with quoted text treated as opaque.
  commandSegment = ''(?:[^;&|'"]|"(?:[^"\\]|\\.)*"|'[^']*')*'';
  # One absolute path below /tmp (or /private/tmp): at least one segment, no
  # "." or ".." segments, no trailing slash (it would follow a symlink), and
  # no quotes, globs, variables or other shell syntax.
  tmpPath = ''(?:/private)?/tmp(?:/(?!\.\.?(?:/|[ \t]|$))[A-Za-z0-9._@+-]+)+'';
  # The rest of the current command segment, up to the next separator.
  rest = ''[^;&|\n]*'';
  # The end of an option or word.
  end = ''(?=[\s;&|)]|$)'';
  # A git invocation, with global options, running the given subcommand.
  gitCommand = sub: ''(?:^|[;&|(){}\s])git(?:\s+(?:-[Cc]\s+\S+|-[^\s;&|(){}]+))*\s+${sub}${end}'';
  shortFlag = letters: "-[A-Za-z]*[${letters}][A-Za-z]*${end}";
  rule = pattern: description: {
    inherit pattern description;
    regex = true;
  };
  # A tool name at the start of a command segment.
  tool = name: ''(?:^|[;&|(){}\s])${name}(?=\s)'';
  # A copy or sync whose destination (a later argument) is a bucket URL.
  copyTo = scheme: ''(?:cp|sync|rsync)(?:\s+-\S+)*\s+[^\s;&|]+(?:\s+[^\s;&|]+)*?\s+${scheme}'';
  infraRules = [
    (rule ''${tool "kubectl"}(?!${rest}\s--dry-run(?:=(?:server|client))?${end})(?!${rest}\sauth\s+can-i${end})(?=${rest}\s(?:apply|create|delete|patch|replace|scale|autoscale|edit|label|annotate|drain|cordon|uncordon|taint|expose|run|set|rollout\s+(?:restart|undo|pause|resume))${end})'' "Kubernetes change")
    (rule ''${tool "(?:terraform|tofu)"}(?=${rest}\s(?:apply|destroy|import|taint|untaint|force-unlock|state\s+(?:rm|mv|push|replace-provider))${end})'' "Terraform state change")
    (rule ''${tool "helm"}(?!${rest}\s--dry-run${end})(?=${rest}\s(?:install|upgrade|uninstall|delete|rollback)${end})'' "Helm release change")
    (rule ''${tool "aws"}(?!${rest}\s--dryrun${end})(?=${rest}\s(?:s3\s+(?:rm|mv|rb)${end}|s3\s+${copyTo "s3://"}|lambda\s+invoke${end}|(?:delete|terminate|put|update|create|remove|modify|attach|detach|run|start|stop|reboot|invoke|deregister|register|revoke|authorize|reset|restore|replace|cancel|send|publish|tag|untag)-[a-z0-9-]+${end}))'' "AWS change")
    (rule ''${tool "gsutil"}(?=${rest}\s(?:(?:rm|mv|rb|setmeta)${end}|${copyTo "gs://"}|(?:acl|defacl|iam|lifecycle|versioning|retention|label|cors|web|notification|kms|ubla|pap|requesterpays|logging|autoclass|rpo)\s+(?:set|ch)${end}))'' "Cloud Storage change")
    (rule ''${tool "gcloud"}(?=${rest}\s(?:(?:delete|undelete|create|update|patch|deploy|apply|cancel|resize|start|stop|reset|rm|mv|import|enable|disable|rollback|promote|set-iam-policy|add-iam-policy-binding|remove-iam-policy-binding)${end}|jobs\s+(?:run|execute)${end}|${copyTo "gs://"}))'' "Google Cloud change")
  ];
in
{
  applyBuiltinDefaults = true;
  onboarding = {
    completed = true;
    completedAt = "1970-01-01T00:00:00.000Z";
  };
  enabled = true;
  features.permissionGate = true;
  permissionGate = {
    requireConfirmation = true;
    # An allowed pattern skips the gate for the whole command, so this one must
    # match the entire command: a single rm of paths under /tmp, nothing
    # chained before or after it.
    allowedPatterns = [
      {
        pattern = ''^[ \t]*rm(?:[ \t]+(?:-[rRfv]+|--(?:recursive|force|verbose)|--))+(?:[ \t]+${tmpPath})+[ \t]*$'';
        regex = true;
        description = "recursive delete of scratch paths under /tmp";
      }
    ];
    patterns =
      map
        (entry: {
          pattern = builtins.elemAt entry 0;
          description = builtins.elemAt entry 1;
        })
        [
          [
            "rm -rf"
            "recursive force delete"
          ]
          [
            "sudo"
            "superuser command"
          ]
          [
            "dd of="
            "disk write operation"
          ]
          [
            "mkfs."
            "filesystem format"
          ]
          [
            "chmod -R 777"
            "insecure recursive permissions"
          ]
          [
            "chown -R"
            "recursive ownership change"
          ]
          [
            "doas"
            "privileged command execution"
          ]
          [
            "pkexec"
            "privileged command execution"
          ]
          [
            "shred"
            "secure file overwrite"
          ]
          [
            "wipefs"
            "filesystem signature wipe"
          ]
          [
            "blkdiscard"
            "block device discard"
          ]
          [
            "fdisk"
            "disk partitioning"
          ]
          [
            "parted"
            "disk partitioning"
          ]
          [
            "docker run --privileged"
            "container with privileged mode"
          ]
        ]
      ++ [
        {
          pattern = ''(?:^|[;&|(){}\s])gh(?:\s+(?:-[^\s;&|(){}]+|--[^\s;&|(){}]+)(?:[=\s]+(?:"[^"]*"|'[^']*'|[^\s;&|(){}]+))?)*\s+issue(?:\s+(?:(?:-R\s+|-R(?=\S)|--repo(?:=|\s+))[^\s;&|(){}]+))*\s+(?!(?:list|status|view)\b)(?!-)\S+'';
          regex = true;
          description = "GitHub issue command outside read-only allow-list";
        }
        {
          pattern = ''(?:^|[;&|(){}\s])gh(?:\s+(?:-[^\s;&|(){}]+|--[^\s;&|(){}]+)(?:[=\s]+(?:"[^"]*"|'[^']*'|[^\s;&|(){}]+))?)*\s+pr(?:\s+(?:(?:-R\s+|-R(?=\S)|--repo(?:=|\s+))[^\s;&|(){}]+))*\s+(?!(?:checks|diff|list|status|view)\b)(?!-)\S+'';
          regex = true;
          description = "GitHub pull-request command outside read-only allow-list";
        }
        {
          pattern = ''${ghApiCommand}(?=[^;&|]*(?:/issues\b|/issues/|/pulls\b|/pulls/))(?:(?=[^;&|]*(?:-X|--method)(?:=|\s+)?(?:POST|PATCH|PUT|DELETE)\b)|(?![^;&|]*\s(?:-X\s*|--method(?:=|\s+))["']?(?:GET|get)\b)(?=[^;&|]*(?:\s(?:-f|-F)(?:=|\s|[^\s;&|(){}])|\s(?:--field|--raw-field|--input)(?:=|\s))))'';
          regex = true;
          description = "GitHub issue or pull-request API mutation";
        }
        {
          pattern = ''${ghApiCommand}(?=[^;&|]*\s["']?/?graphql\b["']?)(?:(?=[\s\S]*\bmutation\b)|(?<=\bmutation\b[\s\S]*)|(?=${commandSegment}(?:\s(?:-F\s*|--field(?:=|\s+))["']?query=@|\s--input(?:=|\s)|\s(?:-[fF]\s*|--(?:field|raw-field)(?:=|\s+))["']?query=["']?[$`])))'';
          regex = true;
          description = "GitHub GraphQL API call with possible mutation";
        }
      ]
      # Backstops for the global agent rules: never force-push, delete a remote
      # ref, hard-reset, destructively clean, force-delete branches, drop
      # stashes, or pass force flags to Worktrunk.
      ++ [
        (rule ''${gitCommand "push"}(?=${rest}\s(?:--(?:force|force-with-lease|force-if-includes|delete|mirror|prune)(?:=\S*)?${end}|${shortFlag "fd"}|[+:][^\s;&|]))'' "Git force-push or remote ref deletion")
        (rule ''${gitCommand "reset"}(?=${rest}\s--hard${end})'' "Git hard reset")
        (rule ''${gitCommand "clean"}(?=${rest}\s(?:--force${end}|${shortFlag "f"}))'' "Git clean that deletes files")
        (rule ''${gitCommand "branch"}(?:(?=${rest}\s${shortFlag "D"})|(?=${rest}\s(?:--delete${end}|${shortFlag "d"}))(?=${rest}\s(?:--force${end}|${shortFlag "f"})))'' "Git branch force delete")
        (rule "${gitCommand ''stash\s+(?:drop|clear)''}" "Git stash drop or clear")
        (rule ''${gitCommand ''worktree\s+remove''}(?=${rest}\s(?:--force${end}|${shortFlag "f"}))'' "Git worktree force removal")
        (rule ''${tool "wt"}(?=${rest}\s(?:--(?:force|force-delete|clobber)${end}|${shortFlag "fD"}))'' "Worktrunk force flag")
      ]
      ++ (if gateInfraChanges then infraRules else [ ]);
  };
}
