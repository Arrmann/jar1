from dataclasses import dataclass
from typing import Any, Callable, Dict, List


TYPE_MAP = {
    "string": str,
    "integer": int,
    "number": (int, float),
    "boolean": bool,
    "array": list,
    "object": dict,
}


@dataclass
class ToolSpec:
    name: str
    description: str
    parameters: Dict[str, Any]
    handler: Callable[[Dict[str, Any]], Dict[str, Any]]
    dangerous: bool = False
    category: str = "system"


class ToolRegistry:
    def __init__(self):
        self.tools: Dict[str, ToolSpec] = {}

    def register(
        self,
        name: str,
        description: str,
        parameters: Dict[str, Any],
        handler: Callable[[Dict[str, Any]], Dict[str, Any]],
        dangerous: bool = False,
        category: str = "system",
    ) -> None:
        self.tools[name] = ToolSpec(
            name=name,
            description=description,
            parameters=parameters,
            handler=handler,
            dangerous=dangerous,
            category=category,
        )

    def get(self, name: str) -> ToolSpec | None:
        return self.tools.get(name)

    def schemas(self) -> List[Dict[str, Any]]:
        return [
            {
                "name": tool.name,
                "description": tool.description,
                "parameters": tool.parameters,
            }
            for tool in self.tools.values()
        ]

    def validate_args(self, spec: ToolSpec, args: Dict[str, Any]) -> Dict[str, Any]:
        args = args or {}
        params = spec.parameters.get("properties", {})
        required = spec.parameters.get("required", [])

        for req in required:
            if req not in args or args[req] in (None, ""):
                raise ValueError(f"Не указан обязательный параметр: {req}")

        clean: Dict[str, Any] = {}

        for key, value in args.items():
            if key not in params:
                continue

            expected_type = params[key].get("type")
            py_type = TYPE_MAP.get(expected_type)

            if py_type is not None and value is not None:
                if expected_type == "integer" and isinstance(value, float) and value.is_integer():
                    value = int(value)
                elif expected_type == "number" and isinstance(value, int):
                    value = float(value)
                elif expected_type == "string" and not isinstance(value, str):
                    value = str(value)

                if not isinstance(value, py_type):
                    raise ValueError(f"Неверный тип параметра {key}: ожидался {expected_type}")

            clean[key] = value

        return clean
