import { describe, expect, it } from "vitest";
import { resolveChatGitHubRepository } from "./chat-github-repository.ts";

const checkout = { owner: "openclaw", repo: "openclaw" };
const link = "https://github.com/acme/research/pull/126";

describe("conversation GitHub repository", () => {
  it("ignores examples, reasoning, tool output, and user content when choosing a default", () => {
    expect(
      resolveChatGitHubRepository(
        [
          { role: "user", content: link },
          { role: "toolResult", content: link },
          {
            role: "assistant",
            content: `\`${link}\`\n\n> [Example](${link})\n\n\`\`\`\n${link}\n\`\`\``,
          },
          { role: "assistant", content: `<think>${link}</think>\nPR #126` },
        ],
        checkout,
      ),
    ).toEqual(checkout);
  });

  it("leaves the default unresolved when the loaded conversation discusses multiple repositories", () => {
    expect(
      resolveChatGitHubRepository(
        [
          { role: "assistant", content: `[Research](${link})` },
          { role: "assistant", content: "https://github.com/other/project/issues/126" },
        ],
        checkout,
      ),
    ).toBeNull();
  });

  it("uses equivalent explicit links without depending on checkout metadata", () => {
    expect(
      resolveChatGitHubRepository(
        [
          { role: "assistant", content: `[Review](${link}#issuecomment-123)` },
          { role: "assistant", content: "<https://github.com/ACME/Research/issues/2>" },
        ],
        null,
      ),
    ).toEqual({ owner: "acme", repo: "research" });
  });
});
