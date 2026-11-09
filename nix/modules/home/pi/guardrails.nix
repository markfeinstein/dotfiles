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
    allowedPatterns = [];
    patterns =
      map (entry: {
        pattern = builtins.elemAt entry 0;
        description = builtins.elemAt entry 1;
      }) [
        ["rm -rf" "recursive force delete"]
        ["sudo" "superuser command"]
        ["dd of=" "disk write operation"]
        ["mkfs." "filesystem format"]
        ["chmod -R 777" "insecure recursive permissions"]
        ["chown -R" "recursive ownership change"]
        ["doas" "privileged command execution"]
        ["pkexec" "privileged command execution"]
        ["shred" "secure file overwrite"]
        ["wipefs" "filesystem signature wipe"]
        ["blkdiscard" "block device discard"]
        ["fdisk" "disk partitioning"]
        ["parted" "disk partitioning"]
        ["docker run --privileged" "container with privileged mode"]
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
          pattern = ''(?:^|[;&|(){}\s])gh(?:\s+(?:-[^\s;&|(){}]+|--[^\s;&|(){}]+)(?:[=\s]+(?:"[^"]*"|'[^']*'|[^\s;&|(){}]+))?)*\s+api\b(?=[^;&|]*(?:/issues\b|/issues/|/pulls\b|/pulls/))(?=[^;&|]*(?:(?:-X|--method)(?:=|\s+)?(?:POST|PATCH|PUT|DELETE)\b|\s(?:-f|-F)(?:=|\s|[^\s;&|(){}])|\s(?:--field|--raw-field|--input)(?:=|\s)))'';
          regex = true;
          description = "GitHub issue or pull-request API mutation";
        }
        {
          pattern = ''(?:^|[;&|(){}\s])gh(?:\s+(?:-[^\s;&|(){}]+|--[^\s;&|(){}]+)(?:[=\s]+(?:"[^"]*"|'[^']*'|[^\s;&|(){}]+))?)*\s+api\b(?=[^;&|]*\s["']?/?graphql\b["']?)'';
          regex = true;
          description = "GitHub GraphQL API call with possible mutation";
        }
      ];
  };
}
