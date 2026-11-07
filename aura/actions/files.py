import datetime
import os
import shutil
from pathlib import Path
from typing import Any, Dict, List


TEXT_EXTENSIONS = {
    ".txt",
    ".md",
    ".py",
    ".js",
    ".ts",
    ".json",
    ".csv",
    ".log",
    ".ini",
    ".cfg",
    ".yaml",
    ".yml",
    ".xml",
    ".html",
    ".css",
}

PROTECTED_PARTS = {
    "windows",
    "program files",
    "program files (x86)",
    "system32",
    "syswow64",
    "boot",
}


def _safe_path(value: str) -> Path:
    return Path(str(value).strip()).expanduser().resolve()


def _is_protected(path: Path) -> bool:
    lower_parts = {p.lower() for p in path.parts}
    return bool(lower_parts & PROTECTED_PARTS)


def _default_root() -> Path:
    return Path.home()


def find_files(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip().lower()
    root = args.get("root") or ""
    content = str(args.get("content", "")).strip()
    limit = int(args.get("limit", 50) or 50)

    if not query and not content:
        return {"success": False, "message": "Не задан критерий поиска файлов."}

    root_path = _safe_path(root) if root else _default_root()
    if not root_path.exists():
        return {"success": False, "message": f"Путь не найден: {root_path}"}

    found: List[str] = []

    try:
        for dirpath, dirnames, filenames in os.walk(root_path):
            dirnames[:] = [
                d
                for d in dirnames
                if not d.startswith(".")
                and not d.startswith("$")
                and d.lower() not in {"windows", "system volume information", "program files", "program files (x86)"}
            ]

            for filename in filenames:
                file_path = Path(dirpath) / filename

                if query and query not in filename.lower():
                    continue

                if content:
                    if file_path.suffix.lower() not in TEXT_EXTENSIONS:
                        continue
                    try:
                        if file_path.stat().st_size > 1_000_000:
                            continue
                        text = file_path.read_text(encoding="utf-8", errors="ignore")
                        if content.lower() not in text.lower():
                            continue
                    except Exception:
                        continue

                found.append(str(file_path))
                if len(found) >= limit:
                    return {
                        "success": True,
                        "message": f"Найдено файлов: {len(found)}",
                        "files": found,
                    }
    except PermissionError:
        pass

    if found:
        return {"success": True, "message": f"Найдено файлов: {len(found)}", "files": found}

    return {"success": False, "message": "Файлы не найдены."}


def create_folder(args: Dict[str, Any]) -> Dict[str, Any]:
    path = _safe_path(str(args.get("path", "")))
    if not path:
        return {"success": False, "message": "Не указан путь папки."}

    try:
        path.mkdir(parents=True, exist_ok=True)
        return {"success": True, "message": f"Папка создана: {path}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось создать папку: {exc}"}


def create_document(args: Dict[str, Any]) -> Dict[str, Any]:
    path = _safe_path(str(args.get("path", "")))
    text = str(args.get("text", "") or "")

    if not path:
        return {"success": False, "message": "Не указан путь документа."}

    try:
        path.parent.mkdir(parents=True, exist_ok=True)

        if path.suffix.lower() == ".docx":
            try:
                from docx import Document

                doc = Document()
                for para in text.splitlines() or [""]:
                    doc.add_paragraph(para)
                doc.save(str(path))
            except Exception as exc:
                return {"success": False, "message": f"Не удалось создать DOCX: {exc}"}
        else:
            path.write_text(text, encoding="utf-8")

        return {"success": True, "message": f"Документ создан: {path}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось создать документ: {exc}"}


def read_document(args: Dict[str, Any]) -> Dict[str, Any]:
    path = _safe_path(str(args.get("path", "")))
    if not path.exists():
        return {"success": False, "message": "Файл не найден."}

    suffix = path.suffix.lower()

    try:
        if suffix == ".docx":
            from docx import Document

            doc = Document(str(path))
            text = "\n".join(p.text for p in doc.paragraphs)
        elif suffix == ".pdf":
            from pypdf import PdfReader

            reader = PdfReader(str(path))
            text = "\n".join((page.extract_text() or "") for page in reader.pages)
        else:
            text = path.read_text(encoding="utf-8", errors="ignore")

        if len(text) > 8000:
            text = text[:8000] + "\n\n[Обрезано из-за размера]"

        return {"success": True, "path": str(path), "content": text}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось прочитать документ: {exc}"}


def rename_file(args: Dict[str, Any]) -> Dict[str, Any]:
    src = _safe_path(str(args.get("source", "")))
    dst = _safe_path(str(args.get("destination", "")))

    if not src.exists():
        return {"success": False, "message": "Исходный файл не найден."}

    if dst.exists():
        return {"success": False, "message": "Целевое имя уже существует."}

    try:
        src.rename(dst)
        return {"success": True, "message": f"Переименовано: {dst}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось переименовать: {exc}"}


def move_file(args: Dict[str, Any]) -> Dict[str, Any]:
    src = _safe_path(str(args.get("source", "")))
    dst_dir = _safe_path(str(args.get("destination_folder", "")))

    if not src.exists():
        return {"success": False, "message": "Исходный файл не найден."}

    try:
        dst_dir.mkdir(parents=True, exist_ok=True)
        dst = dst_dir / src.name
        if dst.exists():
            return {"success": False, "message": "Файл уже существует в папке назначения."}

        shutil.move(str(src), str(dst))
        return {"success": True, "message": f"Перемещено: {dst}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось переместить: {exc}"}


def delete_file(args: Dict[str, Any]) -> Dict[str, Any]:
    path = _safe_path(str(args.get("path", "")))

    if not path.exists():
        return {"success": False, "message": "Путь не найден."}

    if _is_protected(path):
        return {"success": False, "message": "Удаление защищённых системных путей запрещено."}

    try:
        if path.is_dir():
            shutil.rmtree(str(path))
        else:
            path.unlink()

        return {"success": True, "message": f"Удалено: {path}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось удалить: {exc}"}


def organize_files(args: Dict[str, Any]) -> Dict[str, Any]:
    folder = _safe_path(str(args.get("folder", "")))
    mode = str(args.get("mode", "extension") or "extension").lower()

    if not folder.exists() or not folder.is_dir():
        return {"success": False, "message": "Папка не найдена."}

    if _is_protected(folder):
        return {"success": False, "message": "Организация защищённых системных папок запрещена."}

    moved = 0

    try:
        for item in folder.iterdir():
            if not item.is_file():
                continue

            if mode == "date":
                dt = datetime.datetime.fromtimestamp(item.stat().st_mtime)
                target_dir = folder / dt.strftime("%Y-%m")
            else:
                ext = item.suffix.lower().strip(".") or "без_расширения"
                target_dir = folder / ext

            target_dir.mkdir(parents=True, exist_ok=True)
            target = target_dir / item.name

            if target.exists():
                target = target_dir / f"{item.stem}_{datetime.datetime.now().strftime('%Y%m%d%H%M%S')}{item.suffix}"

            shutil.move(str(item), str(target))
            moved += 1

        return {"success": True, "message": f"Файлов организовано: {moved}"}
    except Exception as exc:
        return {"success": False, "message": f"Не удалось организовать файлы: {exc}"}
