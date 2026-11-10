#!/usr/bin/env python3
"""Check local Markdown links and heading anchors. Stdlib; no network requests.

Vendored upstream documentation is excluded because its links target its source
repository. URLs, mail links and generated-project example paths are not fetched.
"""
from __future__ import annotations
import argparse
import re
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit

def prose(text: str) -> str:
    return re.sub(r'(?ms)^\s*(`{3,}|~{3,})[^\n]*\n.*?^\s*\1\s*$', '', text)

def anchors(text: str) -> set[str]:
    result, counts = set(), {}
    for title in re.findall(r'(?m)^ {0,3}#{1,6}\s+(.+?)\s*#*$', prose(text)):
        title = re.sub(r'<[^>]+>', '', title).strip().lower()
        slug = ''.join(c for c in title if c in '-_ ' or unicodedata.category(c)[0] in 'LN').replace(' ', '-')
        n = counts.get(slug, 0); counts[slug] = n + 1
        result.add(slug + (f'-{n}' if n else ''))
    result.update(re.findall(r'(?:id|name)=[\"\x27]([^\"\x27]+)', text))
    return result

def check(root: Path, files: list[Path]) -> tuple[int, list[str]]:
    errors, checked, cache = [], 0, {}
    for file in files:
        text = prose(file.read_text(encoding='utf-8-sig'))
        # Inline code is prose about a link, not a clickable link.
        text = re.sub(r'`[^`\n]+`', '', text)
        refs = dict(re.findall(r'(?m)^\s*\[([^\]]+)\]:\s*<?([^\s>]+)>?', text))
        links = re.findall(r'!?\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)(?:\s+[\"\x27][^\n]*?[\"\x27])?\s*\)', text)
        links += [refs[k] for k in re.findall(r'\[[^\]\n]+\]\[([^\]]+)\]',text) if k in refs]
        for link in links:
            target = urlsplit(link.strip('<>'))
            if target.scheme or target.netloc: continue
            path = (root / unquote(target.path.lstrip('/')) if target.path.startswith('/') else file.parent / unquote(target.path)).resolve() if target.path else file
            checked += 1
            if not path.exists():
                errors.append(f'{file.relative_to(root)}: missing {link}')
            elif target.fragment and path.suffix.lower() == '.md':
                if path not in cache: cache[path] = anchors(path.read_text(encoding='utf-8-sig'))
                if unquote(target.fragment) not in cache[path]:
                    errors.append(f'{file.relative_to(root)}: missing anchor {link}')
    return checked, errors

def main() -> int:
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    args=ap.parse_args(); root=args.root.resolve()
    files=[p for p in root.rglob('*.md') if not any(x in p.parts for x in ('.git','.godot','node_modules','target','.kit')) and not p.is_relative_to(root/'skills/vendor') and '/addons/' not in p.as_posix()]
    checked,errors=check(root,files)
    for error in errors: print(error)
    print(f'DOC LINKS {"FAIL" if errors else "PASS"}: {len(files)} files, {checked} local links, {len(errors)} errors (external URLs not fetched)')
    return bool(errors)

if __name__=='__main__': raise SystemExit(main())
