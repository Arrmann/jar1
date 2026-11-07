"""Trusted built-in task skills. No downloaded code or generic action batches.

Each field goes through the controller's normal policy, cancellation and freshness
checks. Sending, deleting and shell execution are deliberately not bundled.
"""
from agent_runtime import ActionError
import re


def search_field(args, observation):
    identifier=str(args.get('id',''))
    target=observation.targets.get(identifier,{})
    text=args.get('text')
    if target.get('search') is not True or target.get('disabled'):
        raise ActionError('Навык поиска требует наблюдаемое поисковое поле')
    if not isinstance(text,str) or not text.strip() or len(text)>1000 or '\n' in text or '\r' in text:
        raise ActionError('Некорректный поисковый запрос')
    return identifier,text


def browser_first_task(task):
    """Only user-requested web tasks; existing tabs/accounts keep native access."""
    import re
    text = task.casefold()
    if re.search(r'текущ|открыт\w*\s+(?:браузер|вклад)|мо[йёю]\s+браузер|профил|авторизац|current|existing',text):
        return False
    return bool(re.search(r'https?://|\bwww\.|додо\s*пицц|dodopizza|рутуб|ру\s*туб|rutube|ютуб|youtube|википед|wikipedia|гугл|google|яндекс|в интернете|\bсайт\w*|\bбраузер\w*',text)
        or re.search(r'(фильм|видео).*(результат|поиск)',text))


def task_guidance(task):
    if not browser_first_task(task):
        return ''
    return ('Это веб-задача пользователя. Если нужный сайт уже в текущем наблюдении, продолжай в нём без повторного browser_open. '
            'Иначе открывай сайт напрямую через browser_open: не ищи установленный браузер '
            'через apps и не переключай окна перед browser_open. Если адрес сайта неясен — уточни только сайт. '
            'После уточнения сайта открывай его напрямую; не ищи уже известный сайт в Google, если пользователь отдельно этого не просил. '
            'Если Google показывает CAPTCHA или необычный трафик, не повторяй его форму. Не обходи проверку; '
            'Вызови ask: попроси пользователя пройти проверку в браузере и сказать «Джарвис, продолжай». '
            'Не завершай задачу через fail/done из-за CAPTCHA. После ответа заново прочитай страницу и продолжи исходную задачу. '
            'Для порядкового результата используй result_rank у элементов, а не считай ссылки навигации или дубликаты одного видео. '
            'При проверке учитывай result_rank в журнале исполнителя: страница видео не обязана повторять позицию из выдачи.')


def fill_fields(args, observation):
    if args.get('name') != 'fill_fields':
        raise ActionError('Неизвестный навык')
    fields = args.get('fields')
    if not isinstance(fields,list) or not 2 <= len(fields) <= 6:
        raise ActionError('fill_fields заполняет от двух до шести полей')
    prepared, seen, total = [], set(), 0
    for field in fields:
        if not isinstance(field,dict) or not isinstance(field.get('text'),str) or type(field.get('clear',False)) is not bool:
            raise ActionError('Некорректное поле навыка')
        identifier = str(field.get('id',''))
        target = observation.targets.get(identifier)
        if not target or identifier in seen or not all(k in target for k in ('name','type','rect')):
            raise ActionError('Поле отсутствует или повторяется')
        if any(previous[0] == {k:target[k] for k in ('name','type','rect')} for previous in prepared):
            raise ActionError('Поля навыка неоднозначны')
        total += len(field['text'])
        if len(field['text']) > 4000 or total > 8000:
            raise ActionError('Слишком большой ввод для навыка')
        seen.add(identifier)
        prepared.append(({k:target[k] for k in ('name','type','rect')},
            {'action':'type','args':{'id':identifier,'text':field['text'],'clear':field.get('clear',False)},
             'purpose':'Заполнить поле «'+str(target['name'])[:100]+'»','risk':'none'}))
    return prepared


def app_guidance(text, task=''):
    # Header only; no instructions or hints are taken from page/document content.
    import json
    try:
        header = json.loads(text.split('\n',1)[0])
        title = str(header.get('active_window') or header.get('title') or '').casefold()
    except (ValueError,TypeError,AttributeError):
        return ''
    if ('telegram' not in title and 'телеграм' not in title and
        any(browser in title for browser in ('chrome', 'edge', 'firefox', 'opera', 'vivaldi'))):
        if re.search(r'текущ|уже откры|открыт\w* браузер|existing|current',task,re.I):
            return 'Используй уже открытую вкладку пользователя и её элементы. Не открывай отдельный профиль браузера вместо существующего входа.'
        return ('Веб-задача: для поиска и перехода между сайтами используй browser_open, '
                'затем работай с элементами страницы. Не набирай URL в адресной строке через Windows UI Automation: '
                'это медленно и может ошибочно выглядеть как очистка данных. '
                'Обычный поиск и навигация не требуют подтверждения.')
    if 'telegram' in title or 'телеграм' in title:
        return ('Telegram: для поиска чата сразу используй поле Search/Поиск; ввод сам получает фокус. '
                'Не кликай рекламные баннеры, дату рождения, профиль и настройки. '
                'Посторонний блокирующий диалог закрой Escape/Cancel без сохранения. '
                'Если точных адресатов несколько — уточни выбор. Не выбирай глобальный канал вместо личного чата.')
    if 'notepad' in title or 'блокнот' in title:
        return ('Блокнот: используй поле документа для ввода; отдельный клик перед type не нужен. '
                'Ctrl+N нужен только для нового документа. Не закрывай существующие вкладки.')
    return ''
