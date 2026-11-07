"""Exact, deliberately narrow task contracts derived only from the user's text.

Unknown/multi-step/clarified tasks keep the semantic verifier. A successful click
is never by itself a task outcome, nor is an arbitrary model-supplied assertion.
"""
import hashlib
import json
import re
from urllib.parse import parse_qs, urlsplit


def exact_contract(task, clarifications):
    if clarifications:
        return None
    task = task.strip().rstrip('.!')
    match = re.fullmatch(r'(?:открой|open)\s+(?:(?:сайт|страницу)\s+)?(https?://\S+)', task, re.I)
    if match:
        return ('url', match[1])
    match = re.fullmatch(r'(?:найди|поищи)\s+на\s+(?:этом|текущем)\s+сайте\s+[«"]([^«»"\r\n]{1,500})[»"]', task, re.I)
    if match:
        return ('search', match[1])
    match = re.fullmatch(r'(?:напиши|введи)\s+(?:текст\s+)?[«"]([^«»"\r\n]{1,1000})[»"]', task, re.I)
    return ('text', match[1]) if match else None


def verify_contract(contract, obs, receipts):
    if contract is None:
        return None
    kind, expected = contract
    if kind == 'search':
        try:
            header = json.loads(obs.text)
            query = parse_qs(urlsplit(header.get('url','')).query)
        except (ValueError, TypeError):
            return None
        if (not receipts or receipts[-1].get('action') != 'shortcut'
                or header.get('ready_state') not in ('interactive','complete')
                or re.search(r'captcha|капч|unusual traffic|access denied', obs.text, re.I)):
            return None
        if any(query.get(key)==[expected] for key in ('q','query','search_query','search','text')):
            return {'verified':True,'reason':'Поисковый запрос подтверждён в адресе готовой страницы','source':'exact_search_query'}
        return None
    if kind == 'url':
        try:
            header = json.loads(obs.text)
        except (ValueError, TypeError):
            return None
        # Exact URL only. Redirects, login and CAPTCHA must be evaluated normally.
        if (header.get('url') == expected and header.get('ready_state') in ('interactive','complete')
                and header.get('title') and not re.search(r'captcha|капч|unusual traffic|access denied', obs.text, re.I)):
            return {'verified':True, 'reason':'Нужный адрес открыт, документ готов', 'source':'exact_url'}
        return None
    if kind == 'text':
        digest = hashlib.sha256(expected.encode()).hexdigest()
        for receipt in reversed(receipts):
            if receipt.get('action') != 'type':
                continue
            if (receipt.get('document') != obs.document or receipt.get('window') != obs.window
                    or receipt.get('text_hash') != digest):
                return None
            target = (obs.catalog or obs.targets).get(receipt.get('target_id'), {})
            if target.get('_value_hash') == digest and target.get('focused') is True:
                return {'verified':True, 'reason':'Точный текст подтверждён в активном поле', 'source':'exact_field_value'}
            return None
    return None


def direct_action(contract, obs, search_memory):
    if contract is None:
        return None
    kind, expected = contract
    if kind == 'url':
        return dict(action='browser_open',args={'url':expected},risk='none',purpose='Открыть запрошенный адрес')
    if kind == 'search':
        identifier = search_memory.resolve(obs)
        if identifier:
            return dict(action='skill',args={'name':'search','id':identifier,'text':expected},risk='none',purpose='Выполнить поиск на текущем сайте')
    return None
