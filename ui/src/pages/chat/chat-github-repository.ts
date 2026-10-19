import { asNullableRecord } from "@openclaw/normalization-core/record-coerce";
import MarkdownIt from "markdown-it";
import type { ApplicationGateway } from "../../app/gateway.ts";
import { parseGitHubLinkTarget } from "../../components/github-link-target.ts";
import type { MarkdownGitHubRepository } from "../../components/markdown-github-repositories.ts";
import {
  MARKDOWN_PARSE_LIMIT,
  type MarkdownGitHubContext,
} from "../../components/markdown-render-options.ts";
import { extractTextCached } from "../../lib/chat/message-extract.ts";
import { projectsForGateway } from "../../lib/projects.ts";

// Read authored links before renderer rules turn code spans and shorthand into links.
const parser = new MarkdownIt({ html: false, linkify: true });
const repositoriesByMessage = new WeakMap<object, readonly MarkdownGitHubRepository[]>();

function assistantRepositories(message: object): readonly MarkdownGitHubRepository[] {
  const cached = repositoriesByMessage.get(message);
  if (cached) {
    return cached;
  }
  const repositories: MarkdownGitHubRepository[] = [];
  const text = extractTextCached(message) ?? "";
  if (text.length <= MARKDOWN_PARSE_LIMIT && /github\.com\//i.test(text)) {
    let quoteDepth = 0;
    for (const block of parser.parse(text, {})) {
      if (block.type === "blockquote_open") {
        quoteDepth++;
      } else if (block.type === "blockquote_close") {
        quoteDepth--;
      }
      if (quoteDepth || block.type !== "inline") {
        continue;
      }
      for (const token of block.children ?? []) {
        const href = token.type === "link_open" ? token.attrGet("href") : null;
        const target = typeof href === "string" ? parseGitHubLinkTarget(href) : null;
        if (target) {
          repositories.push({ owner: target.owner.toLowerCase(), repo: target.repo.toLowerCase() });
        }
      }
    }
  }
  repositoriesByMessage.set(message, repositories);
  return repositories;
}

/** Loaded conversation links describe the subject; the checkout only describes where tools run. */
export function resolveChatGitHubRepository(
  messages: readonly unknown[],
  checkout: MarkdownGitHubRepository | null,
): MarkdownGitHubRepository | null {
  let repository: MarkdownGitHubRepository | undefined;
  for (const message of messages) {
    const record = asNullableRecord(message);
    if (record?.role !== "assistant") {
      continue;
    }
    for (const candidate of assistantRepositories(record)) {
      if (
        repository &&
        (repository.owner !== candidate.owner || repository.repo !== candidate.repo)
      ) {
        // Explicit per-reference qualifiers still work; bare numbers cannot choose a repository.
        return null;
      }
      repository = candidate;
    }
  }
  return repository ?? checkout;
}

export function chatGitHubContext(
  gateway: ApplicationGateway,
  messages: readonly unknown[],
  checkout: MarkdownGitHubRepository | null,
): MarkdownGitHubContext {
  const catalog = projectsForGateway(gateway).snapshot;
  // Until catalog success, a lowercase name may be a hidden or ambiguous alias.
  const githubRepo = catalog.result ? resolveChatGitHubRepository(messages, checkout) : null;
  return {
    githubRepo,
    githubRepositories:
      catalog.result && checkout && githubRepo !== checkout
        ? [...catalog.repositories, { ...checkout, aliases: [] }]
        : catalog.repositories,
  };
}
