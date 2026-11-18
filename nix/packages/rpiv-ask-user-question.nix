{ fetchurl, runCommand }:
let
  version = "2.15.0";
  tarball = name: hash: fetchurl {
    inherit hash;
    url = "https://registry.npmjs.org/@juicesharp/${name}/-/${name}-${version}.tgz";
  };
  question = tarball "rpiv-ask-user-question" "sha512-Gm6de5IZF52BaSeh9dnDqJBn821Z5XfJkCmhkCmqTzvNv3SCpSv1mA4Gj5VBcfrSe+xTtWSVQzJwIqJFQHH3Lg==";
  config = tarball "rpiv-config" "sha512-S2BAGX4dJjQ2AyNYOEjC6ha04p9f6CdEfmtxpdxzSKrfDMwqIvOjjO9HiHc1IPY7jDY1q2Q8cGCtpIZWV6Y8NQ==";
in
# Drop this package override when the upstream questionnaire passes blocked to
# ui.custom for both presentations. Pi supplies the host peers at load time.
runCommand "rpiv-ask-user-question-${version}" { } ''
  mkdir -p "$out/node_modules/@juicesharp/rpiv-config"
  tar xf ${question} -C "$out" --strip-components=1
  tar xf ${config} -C "$out/node_modules/@juicesharp/rpiv-config" --strip-components=1
  cd "$out"
  patch --fuzz=0 -p1 < ${../patches/rpiv-question-blocked.patch}
''
