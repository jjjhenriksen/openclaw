import { render } from "lit";
import { t } from "../i18n/index.ts";
import { copyToClipboard } from "../lib/clipboard.ts";
import "../styles/markdown-file-hovercard.css";
import { icons } from "./icons.ts";
import { createPortaledHovercard, PortaledHovercardController } from "./portaled-hovercard.ts";
import "./tooltip.ts";

let nextCardId = 0;

/** File links keep their preview action; this card exposes the original path independently. */
export function installMarkdownFileHovercards(ownerDocument: Document) {
  let active: { anchor: HTMLAnchorElement; path: string; title: string | null } | null = null;
  let feedbackTimer: number | undefined;
  let copying = false;
  const close = () => {
    const previous = active;
    active = null;
    copying = false;
    window.clearTimeout(feedbackTimer);
    observer.disconnect();
    hovercard.reset();
    if (previous && previous.anchor.getAttribute("title") === "") {
      if (previous.title === null) {
        previous.anchor.removeAttribute("title");
      } else {
        previous.anchor.setAttribute("title", previous.title);
      }
    }
  };
  const hovercard = new PortaledHovercardController(close, 220);
  const observer = new MutationObserver(() => {
    if (active && active.anchor.dataset.filePath !== active.path) {
      close();
    }
  });
  const show = () => {
    if (!active || hovercard.card) {
      return;
    }
    const { anchor, path } = active;
    const card = createPortaledHovercard(
      `markdown-file-hovercard-${++nextCardId}`,
      "markdown-file-hovercard",
    );
    card.setAttribute("aria-label", t("chat.workspaceFiles.copyPath"));
    const text = ownerDocument.createElement("code");
    text.className = "markdown-file-hovercard__path";
    text.textContent = path;
    const button = ownerDocument.createElement("button");
    button.type = "button";
    button.className = "markdown-file-hovercard__copy";
    button.setAttribute("aria-label", t("chat.workspaceFiles.copyPath"));
    const tooltip = ownerDocument.createElement("openclaw-tooltip");
    tooltip.setAttribute("content", t("chat.workspaceFiles.copyPath"));
    const icon = ownerDocument.createElement("span");
    icon.setAttribute("aria-hidden", "true");
    render(icons.copy, icon);
    const label = ownerDocument.createElement("span");
    label.className = "markdown-file-hovercard__status sr-only";
    label.setAttribute("role", "status");
    button.append(icon);
    tooltip.append(button);
    const copyPath = async () => {
      if (copying) {
        return;
      }
      const current = () => hovercard.card === card && active?.path === path;
      copying = true;
      const copied = await copyToClipboard(path, current);
      if (!current()) {
        return;
      }
      copying = false;
      render(copied ? icons.check : icons.copy, icon);
      label.classList.toggle("sr-only", copied);
      label.textContent = t(copied ? "common.copied" : "common.copyFailed");
      hovercard.position();
      window.clearTimeout(feedbackTimer);
      feedbackTimer = window.setTimeout(() => {
        render(icons.copy, icon);
        label.classList.add("sr-only");
        label.textContent = "";
        hovercard.position();
      }, 1600);
    };
    button.addEventListener("click", () => {
      void copyPath();
    });
    card.append(text, tooltip, label);
    card.addEventListener("pointerleave", () => {
      hovercard.pointerOverCard = false;
      hovercard.scheduleClose();
    });
    card.addEventListener("keydown", hovercard.handleCardKeyDown);
    hovercard.mount(anchor, card, "vertical");
  };
  const discover = (event: Event) => {
    if (hovercard.restoringFocus || ("pointerType" in event && event.pointerType === "touch")) {
      return;
    }
    const anchor = event
      .composedPath()
      .find(
        (node): node is HTMLAnchorElement =>
          node instanceof HTMLAnchorElement && Boolean(node.dataset.filePath),
      );
    if (!anchor) {
      // The shared HTTP clipboard fallback briefly focuses a scratch textarea.
      if (event.type === "focusin" && !copying && !event.composedPath().includes(hovercard.card!)) {
        close();
      }
      return;
    }
    activate(anchor, event.type === "focusin" ? "focus" : "pointer");
  };
  const activate = (anchor: HTMLAnchorElement, input: "focus" | "pointer") => {
    if (anchor !== active?.anchor) {
      close();
      active = { anchor, path: anchor.dataset.filePath!, title: anchor.getAttribute("title") };
      anchor.setAttribute("title", "");
      hovercard.markTrigger(anchor);
      observer.observe(anchor, { attributes: true, attributeFilter: ["data-file-path"] });
    }
    hovercard.clearClose();
    if (input === "focus") {
      hovercard.focusInside = true;
      show();
    } else if (!hovercard.pointerInside) {
      hovercard.pointerInside = true;
      hovercard.scheduleOpen(150, show, anchor);
    }
  };
  const leave = (event: MouseEvent | FocusEvent) => {
    const anchor = active?.anchor;
    if (
      !anchor ||
      !event.composedPath().includes(anchor) ||
      (event.relatedTarget instanceof Node && anchor.contains(event.relatedTarget))
    ) {
      return;
    }
    if (event.type === "focusout") {
      hovercard.focusInside = false;
      hovercard.scheduleClose();
    } else {
      hovercard.schedulePointerExit();
    }
  };
  const keydown = (event: KeyboardEvent) => {
    if (!active) {
      return;
    }
    if (event.key === "Escape") {
      const origin = event.composedPath();
      if (!origin.includes(active.anchor) && !origin.includes(hovercard.card!)) {
        close();
        return;
      }
      const anchor = active.anchor;
      const restoreFocus = hovercard.card?.contains(ownerDocument.activeElement);
      event.preventDefault();
      event.stopImmediatePropagation();
      close();
      if (restoreFocus) {
        hovercard.returnFocus(anchor);
      }
    } else {
      hovercard.handleTriggerKeyDown(event);
      if (
        (event.key === "Enter" || event.key === " ") &&
        event.composedPath()[0] === active?.anchor
      ) {
        close();
      }
    }
  };
  const pointerdown = (event: Event) => {
    if (!event.composedPath().includes(hovercard.card!)) {
      close();
    }
  };
  const click = (event: Event) => {
    if (active && event.composedPath().includes(active.anchor)) {
      close();
    }
  };
  ownerDocument.addEventListener("pointerover", discover, true);
  ownerDocument.addEventListener("focusin", discover, true);
  ownerDocument.addEventListener("pointerout", leave, true);
  ownerDocument.addEventListener("focusout", leave, true);
  // Close the whole card before its nested tooltip consumes Escape.
  ownerDocument.defaultView?.addEventListener("keydown", keydown, true);
  ownerDocument.addEventListener("pointerdown", pointerdown, true);
  ownerDocument.addEventListener("click", click, true);
  const dispose = () => {
    ownerDocument.removeEventListener("pointerover", discover, true);
    ownerDocument.removeEventListener("focusin", discover, true);
    ownerDocument.removeEventListener("pointerout", leave, true);
    ownerDocument.removeEventListener("focusout", leave, true);
    ownerDocument.defaultView?.removeEventListener("keydown", keydown, true);
    ownerDocument.removeEventListener("pointerdown", pointerdown, true);
    ownerDocument.removeEventListener("click", click, true);
    close();
  };
  return { activate, dispose };
}
