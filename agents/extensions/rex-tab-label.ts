import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);

export default function rexTabLabel(pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    if (!process.env.REX_SESSION || !process.env.REX_BLOCK) return;

    const helper = join(homedir(), ".local", "bin", "rex-label-window");
    void execFileAsync(helper, [ctx.cwd], {
      env: process.env,
      timeout: 5000,
    }).catch(() => {
      // Tab labeling is best-effort and must never block Pi startup.
    });
  });
}
