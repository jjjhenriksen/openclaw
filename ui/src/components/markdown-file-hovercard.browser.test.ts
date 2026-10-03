import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { page, userEvent } from "vitest/browser";
import { toSanitizedMarkdownHtml } from "./markdown.ts";
import { installTitleTooltips } from "./tooltip-title.ts";
import "../styles/base.css";
import "../styles/chat/text.css";

let dispose: () => void;
const filePath = "/Users/example/My Project/src/application.ts";

beforeEach(() => {
  document.body.innerHTML = `<main class="chat-text" style="padding:80px 24px">${toSanitizedMarkdownHtml(
    `[application.ts](<${filePath}:42>) and \`src/next.ts\`.`,
    { fileLinks: true },
  )}</main><button id="outside">Outside</button>`;
  dispose = installTitleTooltips(document);
});
afterEach(() => {
  dispose();
  document.body.replaceChildren();
  vi.restoreAllMocks();
});
const anchor = () => document.querySelector<HTMLAnchorElement>("a[data-file-path]")!;
const card = () => document.querySelector<HTMLElement>(".markdown-file-hovercard");
const copyButton = () => page.getByRole("button", { name: "Copy path", exact: true });

describe("file path hovercard", () => {
  it("keeps the popup reachable and copies the exact path without opening the file", async () => {
    const write = vi.spyOn(navigator.clipboard, "writeText").mockResolvedValue();
    const open = vi.fn();
    anchor().addEventListener("click", open);
    await page.elementLocator(anchor()).hover();
    await expect.element(copyButton()).toBeVisible();
    await copyButton().hover();
    await copyButton().click();
    expect(write).toHaveBeenCalledWith(filePath);
    expect(open).not.toHaveBeenCalled();
    await expect.element(page.getByRole("status")).toHaveTextContent("Copied!");
    expect(card()?.textContent).toContain(filePath);
    expect(document.querySelector("openclaw-tooltip[open]")).toBeNull();
    await page.elementLocator(anchor()).click();
    expect(open).toHaveBeenCalledOnce();
    expect(card()).toBeNull();
  });

  it("supports Tab to copy, Escape back to the link, and onward keyboard navigation", async () => {
    anchor().focus();
    await expect.element(copyButton()).toBeVisible();
    await userEvent.keyboard("{Tab}");
    expect(document.activeElement).toBe(copyButton().element());
    await userEvent.keyboard("{Escape}");
    expect(document.activeElement).toBe(anchor());
    expect(card()).toBeNull();
    await userEvent.keyboard("{Tab}");
    expect(document.activeElement).toBe(document.querySelectorAll("a[data-file-path]")[1]);
  });

  it("shows a failure when both clipboard transports fail", async () => {
    vi.spyOn(navigator.clipboard, "writeText").mockRejectedValue(new Error("Denied"));
    vi.spyOn(document, "execCommand").mockReturnValue(false);
    anchor().focus();
    await copyButton().click();
    await expect.element(page.getByRole("status")).toHaveTextContent("Copy failed");
    expect(card()).not.toBeNull();
  });

  it("retires the card when its source link is removed", async () => {
    const source = anchor();
    source.focus();
    await expect.element(copyButton()).toBeVisible();
    source.remove();
    await expect.poll(card).toBeNull();
    expect(source.title).toBe(`${filePath}:42`);
  });

  it("ignores late clipboard feedback after switching to another file", async () => {
    let finish!: () => void;
    vi.spyOn(navigator.clipboard, "writeText").mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          finish = resolve;
        }),
    );
    anchor().focus();
    await copyButton().click();
    const next = document.querySelectorAll<HTMLAnchorElement>("a[data-file-path]")[1];
    next.focus();
    finish();
    await expect.element(copyButton()).toBeVisible();
    expect(card()?.textContent).toContain("src/next.ts");
    expect(card()?.textContent).not.toContain("Copied!");
  });

  it("also offers copy when the link label already contains the full path", async () => {
    anchor().textContent = filePath;
    anchor().removeAttribute("title");
    anchor().focus();
    await expect.element(copyButton()).toBeVisible();
    await userEvent.keyboard("{Escape}");
    expect(anchor().hasAttribute("title")).toBe(false);
  });

  it("lets another focused control handle Escape while a file link is hovered", async () => {
    const outside = document.querySelector<HTMLButtonElement>("#outside")!;
    const handleEscape = vi.fn();
    outside.addEventListener("keydown", handleEscape);
    outside.focus();
    await page.elementLocator(anchor()).hover();
    await expect.element(copyButton()).toBeVisible();
    await userEvent.keyboard("{Escape}");
    expect(handleEscape).toHaveBeenCalledOnce();
    expect(handleEscape.mock.calls[0][0].defaultPrevented).toBe(false);
    expect(document.activeElement).toBe(outside);
    expect(card()).toBeNull();
  });
});
