import type { HumanMention } from "@openclaw/gateway-protocol";
import type { Env } from "markdown-it";
import type {
  MarkdownGitHubRepository,
  MarkdownGitHubRepositoryAliases,
} from "./markdown-github-repositories.ts";

export type MarkdownHumanMentionToken = { marker: string; profileId: string; label: string };

// Larger message-mode inputs use the literal-text fallback instead of Markdown parsing.
export const MARKDOWN_PARSE_LIMIT = 40_000;

export type MarkdownRenderOptions = {
  assistantTranscriptRoleHeaders?: boolean;
  codeBlockChrome?: "copy" | "none";
  codeBlockInteraction?: "interactive" | "static";
  fileLinks?: boolean;
  githubRepo?: MarkdownGitHubRepository | null;
  githubRepositories?: readonly MarkdownGitHubRepositoryAliases[];
  humanMentions?: readonly HumanMention[];
  interactiveImages?: boolean;
  linkFavicons?: boolean;
  progressBars?: boolean;
  mode?: "document" | "message";
  remoteImages?: boolean;
  sessionLinks?: boolean;
  tableInteractions?: "enabled" | "none";
};

export type MarkdownGitHubContext = Pick<
  MarkdownRenderOptions,
  "githubRepo" | "githubRepositories"
>;

// The math plugin carries admission through MarkdownIt's shared render environment.
declare module "markdown-it" {
  interface Env {
    mathExpressions?: number;
  }
}

export type MarkdownRenderEnv = Required<MarkdownRenderOptions> &
  Pick<Env, "mathExpressions"> & {
    streamingOpenFence?: boolean;
    humanMentionTokens?: readonly MarkdownHumanMentionToken[];
  };

export function normalizeMarkdownRenderOptions(
  options: MarkdownRenderOptions = {},
): MarkdownRenderEnv {
  return {
    assistantTranscriptRoleHeaders: options.assistantTranscriptRoleHeaders ?? false,
    codeBlockChrome: options.codeBlockChrome ?? "copy",
    codeBlockInteraction: options.codeBlockInteraction ?? "static",
    fileLinks: options.fileLinks ?? false,
    githubRepo: options.githubRepo ?? null,
    humanMentions: options.humanMentions ?? [],
    githubRepositories: options.githubRepositories ?? [],
    interactiveImages: options.interactiveImages ?? false,
    linkFavicons: options.linkFavicons ?? false,
    progressBars: options.progressBars ?? false,
    mode: options.mode ?? "message",
    remoteImages: options.remoteImages ?? options.mode === "document",
    sessionLinks: options.sessionLinks ?? false,
    tableInteractions: options.tableInteractions ?? "none",
  };
}
