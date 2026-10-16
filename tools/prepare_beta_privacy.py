"""Render the reviewed privacy draft for local preview; never publish it."""
import argparse
import hashlib
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'docs/runbooks/privacy-policy.md'
DEFAULT = ROOT / '.local/workflow/p25-06/privacy-preview'


def render(source):
    blocks = []
    paragraphs = []

    def flush():
        if paragraphs:
            blocks.append('<p>' + html.escape(' '.join(paragraphs)) + '</p>')
            paragraphs.clear()

    for line in source.splitlines():
        if not line.strip():
            flush()
        elif line.startswith('# '):
            flush()
            blocks.append('<h1>' + html.escape(line[2:]) + '</h1>')
        elif line.startswith('## '):
            flush()
            blocks.append('<h2>' + html.escape(line[3:]) + '</h2>')
        else:
            paragraphs.append(line.strip())
    flush()
    body = '\n'.join(blocks)
    return '''<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>노래기록 · 개인정보 처리 안내 준비본</title>
<link rel="stylesheet" href="style.css"></head>
<body><main><aside>공개 전 검토용 준비본입니다. 시행일과 외부 서비스 처리 범위는 아직 확정되지 않았습니다.</aside>
''' + body + '\n</main></body></html>\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=DEFAULT)
    args = parser.parse_args()
    target = args.output.resolve()
    allowed = (ROOT / '.local/workflow').resolve()
    if not target.is_relative_to(allowed):
        parser.error('Preview output must remain under .local/workflow')
    source = SOURCE.read_text(encoding='utf-8')
    target.mkdir(parents=True, exist_ok=True)
    (target/'index.html').write_text(render(source), encoding='utf-8')
    (target/'style.css').write_text('''body{margin:0;background:#f6f7fa;color:#172033;font:16px/1.8 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:32px 20px 64px}h1{font-size:1.8rem}h2{margin-top:2rem;font-size:1.25rem}aside{padding:16px;border:1px solid #cbd5e1;background:white;border-radius:12px}p{overflow-wrap:anywhere}@media(max-width:420px){main{padding:20px 16px 40px}}\n''', encoding='utf-8')
    report = {'status':'LOCAL_PREVIEW_ONLY','published':False,
              'source':'docs/runbooks/privacy-policy.md',
              'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              'html_sha256':hashlib.sha256((target/'index.html').read_bytes()).hexdigest()}
    (target/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
