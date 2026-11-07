import keyring
import keyring.errors

SERVICE_NAME = "AURA_AI"


def set_secret(key: str, value: str) -> None:
    keyring.set_password(SERVICE_NAME, key, value or "")


def get_secret(key: str, default: str = "") -> str:
    try:
        value = keyring.get_password(SERVICE_NAME, key)
        return value if value is not None else default
    except keyring.errors.KeyringError:
        return default
