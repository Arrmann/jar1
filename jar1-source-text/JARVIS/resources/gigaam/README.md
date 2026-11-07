# Optional GigaAM v3 RNN-T INT8

GigaAM is not downloaded at first launch and its weights are not included in Setup.
Settings → Нейросети → Точное распознавание русского языка → Скачать GigaAM.
The user explicitly selects the model after downloading and validating it.

The pinned manifest contains SHA-256 and byte sizes for all files. Downloads go
to the user's Jarvis configuration directory, independently of Program Files.
The bundled Python 3.11 runtime is reused; dependencies are extracted into an
isolated directory, never installed into the system Python. A CPU inference
probe must succeed before the model becomes available. No audio is uploaded.

The runtime stays loaded while selected, uses two CPU inference threads and
unloads when a different local/cloud mode is selected. Vosk wake detection and
the existing command endpoint behavior remain in place. A failed recognition
is logged and can fall back to the existing Vosk hypothesis. The audio buffer
is capped at 30 seconds. Commands are never replayed automatically.

Model: https://github.com/salute-developers/GigaAM (MIT).
Pinned ONNX conversion: https://huggingface.co/istupakov/gigaam-v3-onnx (MIT).
Runtime: https://github.com/istupakov/onnx-asr (MIT), ONNX Runtime (MIT).
Dependency license files are retained with downloaded wheels and packages.

Do not distribute build-wheels, test audio, or downloaded model directories.
