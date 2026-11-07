"""Resolve an explicit opening step from user text, before inspecting unrelated apps."""
import re
from urllib.parse import quote


def opening_action(task):
    text=re.sub(r'^(?:(?:задание|задача|task)\s*[:,-]?\s*|выполни\s+задачу\s*)','',task.strip(),flags=re.I)
    if re.search(r'текущ|уже откры|открыт\w* браузер|existing|current',text,re.I):
        return None
    match=re.match(r'^(?:открой|запусти|open|launch)\s+(.+?)(?=\s+(?:и|затем|and|then)\s|[,;\n]|$)',text,re.I)
    if not match:
        match=re.match(r'^(?:найди|поищи|find|search)\s+(?:на|в|on)\s+(\S+)',text,re.I)
    if not match:return None
    subject=match[1].strip().rstrip('.!')
    sites=[(r'рутуб|ру\s*туб|rutube','https://rutube.ru/'),
           (r'ютуб|youtube','https://www.youtube.com/'),
           (r'википед|wikipedia','https://ru.wikipedia.org/'),
           (r'гугл|google','https://www.google.com/'),
           (r'яндекс|yandex','https://ya.ru/')]
    for pattern,url in sites:
        if re.search(pattern,subject,re.I):
            # Explicit quoted user query only. These are navigation adapters,
            # never generated code or guesses about an unmentioned task.
            query=re.search(r'[«"]([^»"\r\n]{1,500})[»"]',text)
            search=re.search(r'найди|найти|поищи|search|find',text,re.I)
            if query and search:
                if 'rutube' in url:url+='search/?query='+quote(query[1])
                elif 'youtube' in url:url+='results?search_query='+quote(query[1])
                elif 'google' in url:url+='search?q='+quote(query[1])
                elif 'wikipedia' in url:url+='w/index.php?search='+quote(query[1])
            return dict(action='browser_open',args={'url':url},risk='none',purpose='Открыть запрошенный сайт')
    url=re.fullmatch(r'https?://\S+',subject,re.I)
    if url:return dict(action='browser_open',args={'url':subject},risk='none',purpose='Открыть запрошенный адрес')
    if len(subject)>70 or re.search(r'сайт|страниц|браузер|https?://',subject,re.I):return None
    return dict(action='launch',args={'name':subject},risk='none',purpose='Открыть '+subject)
