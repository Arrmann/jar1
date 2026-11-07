import re
import webbrowser
from typing import Any, Dict
from urllib.parse import quote_plus

import requests
from bs4 import BeautifulSoup


HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
}


def _normalize_url(url: str) -> str:
    url = url.strip()
    if not url:
        return ""
    if not url.startswith("http://") and not url.startswith("https://"):
        url = "https://" + url
    return url


def open_url(args: Dict[str, Any]) -> Dict[str, Any]:
    url = _normalize_url(str(args.get("url", "")))
    if not url:
        return {"success": False, "message": "Не указан URL."}

    webbrowser.open(url)
    return {"success": True, "message": f"Открыт URL: {url}"}


def search_web(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip()
    engine = str(args.get("engine", "google") or "google").lower()

    if not query:
        return {"success": False, "message": "Не задан поисковый запрос."}

    urls = {
        "google": "https://www.google.com/search?q=",
        "bing": "https://www.bing.com/search?q=",
        "duckduckgo": "https://duckduckgo.com/?q=",
        "yandex": "https://yandex.ru/search/?text=",
    }

    base = urls.get(engine, urls["google"])
    url = base + quote_plus(query)
    webbrowser.open(url)

    return {"success": True, "message": f"Поиск открыт: {query}"}


def youtube_search(args: Dict[str, Any]) -> Dict[str, Any]:
    query = str(args.get("query", "")).strip()
    if not query:
        return {"success": False, "message": "Не задан запрос для YouTube."}

    url = "https://www.youtube.com/results?search_query=" + quote_plus(query)
    webbrowser.open(url)
    return {"success": True, "message": f"YouTube поиск открыт: {query}"}


def read_url(args: Dict[str, Any]) -> Dict[str, Any]:
    url = _normalize_url(str(args.get("url", "")))
    if not url:
        return {"success": False, "message": "Не указан URL."}

    try:
        resp = requests.get(url, headers=HEADERS, timeout=20)
        resp.raise_for_status()
    except requests.RequestException as exc:
        return {"success": False, "message": f"Ошибка загрузки страницы: {exc}"}

    soup = BeautifulSoup(resp.text, "html.parser")

    for tag in soup(["script", "style", "noscript", "header", "footer", "nav", "aside"]):
        tag.decompose()

    text = soup.get_text(" ", strip=True)
    text = re.sub(r"\s+", " ", text)

    if len(text) > 12000:
        text = text[:12000] + " ... [обрезано]"

    return {"success": True, "url": url, "content": text}
