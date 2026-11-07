"""Cancellable bounded JSON HTTP transport; no request retries or tools."""
import queue
import threading
import time


class PooledOpener:
    """urllib-compatible facade over a bounded persistent HTTP pool, no retries.

    Lazy import keeps browser/native startup independent of provider SDKs.
    Redirects are disabled so credentials cannot follow a changed endpoint.
    """
    def __init__(self, url):
        self.url = url
        self.client = None
        self.lock = threading.Lock()

    def open(self, request, timeout=35):
        import httpx
        import urllib.error
        import urllib.parse
        with self.lock:
            if self.client is None:
                local = urllib.parse.urlsplit(self.url).hostname in ('localhost','127.0.0.1','::1')
                self.client = httpx.Client(trust_env=not local, follow_redirects=False,
                    limits=httpx.Limits(max_connections=2, max_keepalive_connections=2, keepalive_expiry=60),
                    transport=None)
            try:
                response = self.client.send(self.client.build_request(request.get_method(), request.full_url,
                    content=request.data, headers=dict(request.header_items()), timeout=timeout), stream=True)
            except httpx.HTTPError as error:
                raise OSError('model transport failed') from error
        if response.status_code >= 300:
            code = response.status_code
            response.close()
            raise urllib.error.HTTPError(request.full_url, code, 'model endpoint error', {}, None)
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): response.close()
            def read(self, limit):
                chunks, total = [], 0
                try:
                    for chunk in response.iter_bytes():
                        total += len(chunk)
                        chunks.append(chunk[:max(0, limit-(total-len(chunk)))])
                        if total >= limit: break
                except httpx.HTTPError as error:
                    raise OSError('model response failed') from error
                return b''.join(chunks)
        return Response()

    def close(self):
        if self.client is not None:
            self.client.close()
            self.client = None


def read_response(opener,request,channel,timeout=35):
    result=queue.Queue(maxsize=1)
    def read():
        try:
            with opener.open(request,timeout=timeout) as response:
                value=response.read(2_000_001)
            result.put((True,value))
        except Exception as exc:
            result.put((False,exc))
    threading.Thread(target=read,name='jarvis-model-http',daemon=True).start()
    started=time.monotonic()
    slow=False
    while True:
        channel.check()
        elapsed=time.monotonic()-started
        if elapsed>timeout:
            raise TimeoutError('model response deadline exceeded')
        if elapsed>5 and not slow:
            slow=True
            channel.output({'message':'Модель отвечает дольше пяти секунд. Действие пока не выполнялось.',
                            'slow_phase':'model','slow_seconds':round(elapsed,1)})
        try:
            ok,value=result.get(timeout=min(.1,max(.001,timeout-elapsed)))
        except queue.Empty:
            continue
        channel.check()
        if not ok:
            raise value
        return value
