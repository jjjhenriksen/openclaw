import katex from "katex";
import type { MarkdownIt, StateBlock, StateInline } from "markdown-it";

const DISPLAY_DELIMITERS = [
  { open: "$$", close: "$$", displayMode: true },
  { open: "\\[", close: "\\]", displayMode: true },
] as const;
const INLINE_DELIMITERS = [
  { open: "\\(", close: "\\)", displayMode: false },
  { open: "$", close: "$", displayMode: false },
] as const;

function renderMath(source: string, displayMode: boolean): string {
  try {
    return katex.renderToString(source, {
      displayMode,
      output: "html",
      strict: "ignore",
      throwOnError: false,
      trust: false,
      maxExpand: 1000,
      maxSize: 10,
    });
  } catch {
    // Keep malformed or unexpectedly expensive input visible as text. The
    // renderer's normal HTML escaping and DOMPurify still protect the result.
    return "";
  }
}

function findUnescaped(source: string, needle: string, start: number): number {
  for (let index = start; index < source.length; index += 1) {
    if (source[index] !== needle[0] || !source.startsWith(needle, index)) {
      continue;
    }
    let backslashes = 0;
    for (let cursor = index - 1; cursor >= 0 && source[cursor] === "\\"; cursor -= 1) {
      backslashes += 1;
    }
    if (backslashes % 2 === 0) {
      return index;
    }
  }
  return -1;
}

function parseDisplayMath(state: StateBlock, startLine: number, endLine: number, silent: boolean) {
  const lineStart = state.bMarks[startLine] + state.tShift[startLine];
  const lineEnd = state.eMarks[startLine];
  const line = state.src.slice(lineStart, lineEnd);
  const delimiter = DISPLAY_DELIMITERS.find(({ open }) => line.startsWith(open));
  if (!delimiter) {
    return false;
  }
  const afterOpen = line.slice(delimiter.open.length);
  const sameLineClose = findUnescaped(afterOpen, delimiter.close, 0);
  let nextLine = startLine;
  let latex: string;
  if (sameLineClose >= 0) {
    latex = afterOpen.slice(0, sameLineClose).trim();
  } else {
    const lines: string[] = [afterOpen];
    let closeLine = -1;
    for (let lineIndex = startLine + 1; lineIndex < endLine; lineIndex += 1) {
      const currentStart = state.bMarks[lineIndex] + state.tShift[lineIndex];
      const current = state.src.slice(currentStart, state.eMarks[lineIndex]);
      const close = findUnescaped(current, delimiter.close, 0);
      if (close >= 0) {
        lines.push(current.slice(0, close));
        closeLine = lineIndex;
        break;
      }
      lines.push(current);
    }
    if (closeLine < 0) {
      return false;
    }
    latex = lines.join("\n").trim();
    nextLine = closeLine;
  }
  if (!latex || silent) {
    return Boolean(latex);
  }
  const token = state.push("math_block", "div", 0);
  token.block = true;
  token.content = latex;
  token.map = [startLine, nextLine + 1];
  token.meta = { displayMode: delimiter.displayMode };
  state.line = nextLine + 1;
  return true;
}

function parseInlineMath(state: StateInline, silent: boolean): boolean {
  const source = state.src.slice(state.pos);
  const delimiter = INLINE_DELIMITERS.find(({ open }) => source.startsWith(open));
  if (!delimiter || (delimiter.open === "$" && source.startsWith("$$"))) {
    return false;
  }
  const contentStart = delimiter.open.length;
  const close = findUnescaped(source, delimiter.close, contentStart);
  if (close <= contentStart) {
    return false;
  }
  if (silent) {
    return true;
  }
  const token = state.push("math_inline", "span", 0);
  token.content = source.slice(contentStart, close);
  token.meta = { displayMode: delimiter.displayMode };
  state.pos += close + delimiter.close.length;
  return true;
}

export function installMarkdownMath(markdownParser: MarkdownIt) {
  markdownParser.block.ruler.before("paragraph", "math_block", parseDisplayMath);
  markdownParser.inline.ruler.before("escape", "math_inline", parseInlineMath);
  markdownParser.renderer.rules.math_inline = (tokens, index) => {
    const token = tokens[index];
    return token ? renderMath(token.content, false) || `$${token.content}$` : "";
  };
  markdownParser.renderer.rules.math_block = (tokens, index) => {
    const token = tokens[index];
    if (!token) {
      return "";
    }
    return renderMath(token.content, true) || `$$${token.content}$$`;
  };
}
