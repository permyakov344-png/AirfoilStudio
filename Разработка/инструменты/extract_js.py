#!/usr/bin/env python
# -*- coding: utf-8 -*-
r"""Достаёт главный <script> программы из index.html в отдельный .js.

Нужен, чтобы прогнать скрипт через `node --check` и поймать опечатку до
открытия браузера. Ищется ПЕРВЫЙ тег <script> без атрибута src — так же,
как это делает сборщик build_xp.js.

Использование:
    python extract_js.py ..\программа\index.html check.js
"""
import re
import sys


def extract(src_path, dst_path):
    with open(src_path, encoding="utf-8") as f:
        html = f.read()

    start = None
    for m in re.finditer(r"<script(\s[^>]*)?>", html):
        attrs = m.group(1) or ""
        if "src=" not in attrs:
            start = m.end()
            break

    if start is None:
        raise SystemExit("внутренний <script> не найден")

    end = html.find("</script>", start)
    if end < 0:
        raise SystemExit("не найден закрывающий </script>")

    js = html[start:end]
    with open(dst_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(js)
    print("js chars", len(js))
    return len(js)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    extract(argv[1], argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
