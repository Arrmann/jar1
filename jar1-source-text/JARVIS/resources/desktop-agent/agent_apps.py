"""Read-only installed-app catalog. Never invent executable paths or shell commands."""
import hashlib
import json
import os
import re
from pathlib import Path

from agent_runtime import ActionError


def normalize(name):
    name = re.sub(r'[^\w]+', ' ', str(name).casefold()).strip()
    aliases = {'телеграм': 'telegram', 'телеграмм': 'telegram', 'telegram desktop': 'telegram',
               'блокнот': 'notepad', 'калькулятор': 'calculator', 'calc': 'calculator',
               'проводник': 'explorer', 'гугл хром': 'google chrome', 'хром': 'google chrome',
               'chrome': 'google chrome', 'эдж': 'microsoft edge', 'edge': 'microsoft edge'}
    return aliases.get(name, name)


class AppCatalog:
    def __init__(self, entries=None):
        self.entries = entries

    def _scan(self):
        if self.entries is not None:
            return
        import winreg
        from win32com.client import Dispatch
        entries = []
        def add(name, target, source):
            if not name or not target:
                return
            target = str(target)
            key = normalize(name)
            if any(normalize(e['name']) == key for e in entries):
                return
            entries.append({'id': 'app-' + hashlib.sha256(target.casefold().encode()).hexdigest()[:12],
                            'name': str(name)[:120], 'target': target, 'source': source})
        windows = Path(os.environ.get('WINDIR', r'C:\Windows'))
        for name, path in [('Блокнот', windows/'System32/notepad.exe'),
                           ('Калькулятор', windows/'System32/calc.exe'), ('Проводник', windows/'explorer.exe')]:
            if path.is_file():
                add(name, path, 'Windows')
        try:
            folder = Dispatch('Shell.Application').NameSpace('shell:AppsFolder')
            for item in folder.Items():
                target = str(item.Path)
                if Path(target).is_file() and Path(target).suffix.lower() in ('.exe', '.lnk'):
                    add(item.Name, target, 'Установленные приложения')
                elif re.fullmatch(r'[\w.{}!-]+', target) and '!' in target:
                    add(item.Name, 'shell:AppsFolder\\' + target, 'Microsoft Store')
        except Exception:
            pass
        for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
            for view in (winreg.KEY_WOW64_64KEY, winreg.KEY_WOW64_32KEY):
                try:
                    with winreg.OpenKey(hive, r'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths', 0, winreg.KEY_READ | view) as root:
                        for index in range(winreg.QueryInfoKey(root)[0]):
                            try:
                                name = winreg.EnumKey(root, index)
                                with winreg.OpenKey(root, name) as key:
                                    path = Path(os.path.expandvars(winreg.QueryValue(key, None)).strip('"'))
                                if path.is_file() and path.suffix.lower() == '.exe':
                                    add(path.stem, path, 'App Paths')
                            except OSError:
                                continue
                except OSError:
                    continue
        roots = [(Path(os.environ.get('APPDATA', ''))/'Microsoft/Windows/Start Menu/Programs'),
                 (Path(os.environ.get('PROGRAMDATA', ''))/'Microsoft/Windows/Start Menu/Programs'),
                 Path.home()/'Desktop', Path(os.environ.get('PUBLIC', r'C:\Users\Public'))/'Desktop']
        for root in roots:
            if root.is_dir():
                for path in root.rglob('*.lnk'):
                    if not re.search(r'uninstall|удаление|деинстал', path.stem, re.I):
                        add(path.stem, path, 'Ярлык')
        self.entries = entries

    def search(self, query=''):
        self._scan()
        key = normalize(query)
        entries = [e for e in self.entries if not key or key in normalize(e['name'])]
        return [{'id':e['id'], 'name':e['name'], 'source':e.get('source', '')} for e in entries[:35]]

    def resolve(self, name):
        self._scan()
        text = str(name).strip()
        key = normalize(text)
        matches = [e for e in self.entries if e['id'] == text or normalize(e['name']) == key]
        if len(matches) == 1:
            return matches[0]['target']
        if len(matches) > 1:
            raise ActionError('Найдено несколько приложений. Покажи варианты через apps и уточни выбор')
        path = Path(text)
        if path.is_absolute() and not text.startswith(('\\\\', '//')) and path.suffix.lower() in ('.exe', '.lnk') and path.is_file():
            return str(path)
        choices = self.search(name)
        raise ActionError('Приложение не найдено однозначно. Используй apps, предложи варианты или спроси путь. ' + json.dumps(choices, ensure_ascii=False))
