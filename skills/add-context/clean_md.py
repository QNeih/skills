"""Clean a Markdown export: drop backslash escapes and HTML entities, turn <br> into line breaks.

Usage: python3 -I clean_md.py <in.md>   (prints the cleaned text)
Fenced code blocks and inline code stay as they are.
"""
import html
import re
import sys

ESCAPE = re.compile(r"\\([\\`*_{}\[\]()#+\-.!|<>~=])")
BR = re.compile(r"<br\s*/?>", re.IGNORECASE)
INLINE_CODE = re.compile(r"(`+)(.+?)\1")


def clean_text(text):
    text = BR.sub("\n", text)
    return html.unescape(ESCAPE.sub(r"\1", text))


def clean_line(line):
    out, pos = [], 0
    for m in INLINE_CODE.finditer(line):
        out.append(clean_text(line[pos:m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(clean_text(line[pos:]))
    return "".join(out)


def clean(text):
    lines, fence = [], None
    for line in text.splitlines(keepends=True):
        marker = re.match(r"\s*(```|~~~)", line)
        if fence:
            if marker and marker.group(1) == fence:
                fence = None
            lines.append(line)
        elif marker:
            fence = marker.group(1)
            lines.append(line)
        else:
            lines.append(clean_line(line))
    return "".join(lines)


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        sys.stdout.write(clean(f.read()))
