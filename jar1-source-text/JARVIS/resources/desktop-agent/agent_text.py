"""Literal, bounded Windows text input; no SendKeys command language or clipboard."""
import ctypes
from agent_runtime import ActionError, ExecutionUncertain


def read_control_text(control):
    """Read actual editable content locally. Never dump unrelated documents."""
    try:
        value=control.GetValuePattern().Value
        if isinstance(value,str) and len(value)<=64000:
            return value
    except Exception:
        pass
    try:
        value=control.GetTextPattern().DocumentRange.GetText(64001)
        if isinstance(value,str) and len(value)<=64000:
            return value
    except Exception:
        pass
    return None


def insertion_verified(before, after, text):
    if not isinstance(before,str) or not isinstance(after,str):
        return None
    before,after,text=(value.replace('\r\n','\n') for value in (before,after,text))
    if len(after)!=len(before)+len(text):
        return False
    start=0
    while True:
        index=after.find(text,start)
        if index<0:return False
        if after[:index]+after[index+len(text):]==before:return True
        start=index+1


def literal_units(text):
    # Raw keyboard fallbacks must never synthesize Enter, Tab, or other controls.
    if any(ord(char)<32 or ord(char)==127 for char in text):
        raise ActionError('Для многострочного текста нужен безопасный ValuePattern; клавиши Enter/Tab не посылаются')
    encoded=text.encode('utf-16-le')
    return [int.from_bytes(encoded[index:index+2],'little') for index in range(0,len(encoded),2)]


def send_literal(uia,text,guard,focus):
    literal_units(text)  # Validate the whole string before sending the first chunk.
    # A single SendInput batch preserves surrogate pairs and avoids per-letter sleeps.
    # Check cancellation and focus between short chunks; never retry partial input.
    started=False
    for index in range(0,len(text),16):
        try:
            guard()
            if not focus():
                raise ActionError('Фокус поля изменился; ввод остановлен')
            events=[]
            chunk=literal_units(text[index:index+16])
            for unit in chunk:
                events.extend((uia.KeyboardInput(0,unit,0x0004),uia.KeyboardInput(0,unit,0x0006)))
            array=(uia.INPUT*len(events))(*events)
            started=True
            count=ctypes.windll.user32.SendInput(len(events),array,ctypes.sizeof(uia.INPUT))
            if count!=len(events):
                raise ExecutionUncertain('Windows приняла только часть текста; повторный ввод остановлен')
        except Exception as error:
            if started:
                raise ExecutionUncertain('Ввод мог выполниться частично. Не повторяю текст; проверь поле.') from error
            raise
