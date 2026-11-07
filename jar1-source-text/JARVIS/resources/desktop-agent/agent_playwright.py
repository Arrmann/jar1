"""Playwright execution in Jarvis's own CDP browser, never a personal profile.

The controller still authorizes every action. Fixed element handles intentionally
bind execution to the observed DOM node rather than silently picking a replacement.
"""
from agent_runtime import ActionError


class BrowserActions:
    def __init__(self, endpoint):
        from playwright.sync_api import sync_playwright
        self.runtime = sync_playwright().start()
        try:
            self.browser = self.runtime.chromium.connect_over_cdp(endpoint, timeout=8000)
        except Exception:
            self.runtime.stop()
            raise ActionError('Не удалось подключить Playwright к браузеру Jarvis') from None
        self.page_id = None
        self.page = None

    def select_page(self, identifier):
        if self.page_id == identifier and self.page and not self.page.is_closed():
            return self.page
        for context in self.browser.contexts:
            for page in context.pages:
                session = context.new_cdp_session(page)
                try:
                    target = session.send('Target.getTargetInfo')['targetInfo']['targetId']
                finally:
                    session.detach()
                if target == identifier:
                    self.page_id, self.page = identifier, page
                    page.set_default_timeout(2500)
                    return page
        raise ActionError('Управляемая вкладка закрыта; нужно новое наблюдение')

    def target(self, identifier, selector):
        try:
            page = self.select_page(identifier)
            # selector is generated locally from an observed node, never by the model.
            handle = page.query_selector(selector)
        except ActionError:
            raise
        except Exception:
            raise ActionError('Не удалось найти элемент в управляемой вкладке') from None
        if handle is None:
            raise ActionError('Элемент страницы изменился; нужно новое наблюдение')
        return handle

    def close(self):
        # Stop the driver; ManagedBrowser owns the browser's lifetime.
        self.runtime.stop()
