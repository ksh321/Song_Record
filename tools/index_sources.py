"""Build a searchable, hash-linked index without modifying the six originals."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ("roles", "코드 구현 참고 사항 (1).txt", "docs/reference/코드 구현 참고 사항.txt", "자료별 적용 역할"),
    ("design", "노래기록앱_구현설계서_v1.11(1).docx", "docs/reference/노래기록앱_구현설계서_v1.11.docx", "기능·데이터·API·삭제·동기화·보관"),
    ("plan", "노래기록앱_코드구현계획서_v1.0(1).docx", "docs/노래기록앱_코드구현계획서_v1.0.docx", "작업 ID·선행 조건·완료 기준"),
    ("html", "b-playlist-ui-v1.11(1).html", "docs/reference/b-playlist-ui-v1.11.html", "화면 배치·이동·상호작용"),
    ("ui", "UI_REFERENCE(2)(1).md", "docs/reference/UI_REFERENCE.md", "공통 UI·조작 규칙"),
    ("palette", "ui_reference_palette(2)(1).json", "docs/reference/ui_reference_palette.json", "색상·글자·간격·치수"),
]
APPROVED = {
    "roles": "a9966fdc8286cc5624de4ffb5861b89bd9cc0c102afb59362be17d2234eeeb0a",
    "design": "957786385b081e52cdca2f83250b712701bcb63a73df63df47c1983a5916fe36",
    "plan": "d3da465095024712634dee18fa341ce500dabbf78a72e37b546498b2e8bfe0bd",
    "html": "3a0b44fa03b8c4adbb0bd22fef8ff728c9f96acbebabf79a59cb7a5b8dd91555",
    "ui": "b62babdba6a124277e57e57b56a605325cd961e4040c73cca8a9c03a96a53d17",
    "palette": "88ad5972f79424629b87698760ca98894c4f65fc23d9448bcec1effc4d12d83b",
}


def digest(path):
    data = path.read_bytes()
    if path.suffix != ".docx":
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def extract(path):
    if path.suffix != ".docx":
        return path.read_text(encoding="utf-8-sig")
    with ZipFile(path) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    # Paragraph order includes table cells; original XML paragraph indices are stable locators.
    return "\n".join(
        f"[p{i:05d}] " + "".join(p.itertext())
        for i, p in enumerate(root.findall(".//w:p", ns), 1)
        if "".join(p.itertext()).strip()
    ) + "\n"


def build(source):
    entries = []
    outputs = {}
    for key, external_name, relative, role in SOURCES:
        original = ROOT / relative
        sha = digest(original)
        if sha != APPROVED[key]:
            raise ValueError(f"Unapproved original change: {relative}; preserve source and review approval first")
        if source is not None:
            external = source / external_name
            if digest(external) != sha:
                raise ValueError(f"Source mismatch: {external_name}; resolve policy before regenerating")
        content = extract(original)
        name = key + (".html" if key == "html" else ".txt")
        outputs[name] = content
        entries.append({"id": key, "external_name": external_name, "original": relative,
                        "sha256": sha, "hash_basis": "raw DOCX; LF-normalized UTF-8 text", "role": role, "search_copy": name,
                        "lines": len(content.splitlines())})
    outputs["manifest.json"] = json.dumps({"schema": 1, "sources": entries}, ensure_ascii=False, indent=2) + "\n"
    plan = outputs["plan.txt"].splitlines()
    tasks = []
    for i, line in enumerate(plan, 1):
        match = re.match(r"\[p\d+\] (P\d{2}) (\d{2})  (.+)", line)
        if match:
            if i + 1 >= len(plan) or not re.match(r"\[p\d+\] 완료\s", plan[i+1]):
                raise ValueError(f"Unexpected task acceptance structure at line {i}")
            tasks.append({"id": match[1] + "-" + match[2], "line": i,
                          "title": match[3], "implementation": plan[i], "acceptance": plan[i+1]})
    if len(tasks) != 231 or len({task['id'] for task in tasks}) != 231:
        raise ValueError("Expected 231 unique tasks; review changed source structure")
    outputs["tasks.json"] = json.dumps(tasks, ensure_ascii=False, indent=2) + "\n"
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Actual external folder; compare DOCX bytes and text with LF-normalized line endings")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    out = ROOT / "docs/reference/search"
    outputs = build(args.source)
    if args.check:
        stale = [name for name, text in outputs.items() if not (out / name).is_file() or (out / name).read_text(encoding="utf-8") != text]
        if stale:
            raise SystemExit("Stale search index: " + ", ".join(stale))
    else:
        out.mkdir(parents=True, exist_ok=True)
        for name, text in outputs.items():
            (out / name).write_text(text, encoding="utf-8", newline="\n")
    print("PASS: six original hashes and search index" + ("; external source matched" if args.source else "; repository originals only"))


if __name__ == "__main__":
    main()
