#!/usr/bin/env python3
"""Bind the RAGFlow tenant to stdapi.ai, without any click-through setup.

RAGFlow stores model credentials in its own tables, not in service_conf.yaml:
since the model-provider refactor, "user_default_llm" only names models, so a
provider and an instance have to be created through the REST API before any
model resolves. This script does that once per task start, over the loopback
interface it shares with the RAGFlow container, and is idempotent.

Every value it needs arrives as an environment variable; secrets arrive as ECS
secrets resolved from SSM parameters.
"""

import base64
import json
import os
import sys
import time
from pathlib import Path

import requests
from Cryptodome.Cipher import PKCS1_v1_5
from Cryptodome.PublicKey import RSA

API = "http://127.0.0.1:80/api/v1"

#: RAGFlow's own login key, shipped in the image and read by its "crypt" helper.
PUBLIC_KEY_PATH = "/ragflow/conf/public.pem"

#: Provider whose client posts unmodified OpenAI chat, embedding and rerank requests.
PROVIDER = "OpenAI-API-Compatible"

#: Instance holding the models served over the OpenAI-compatible routes.
CHAT_INSTANCE = "stdapi-ai"

#: Embeddings share those routes, in their own instance: each holds one model.
EMBEDDING_INSTANCE = "stdapi-ai-embed"

#: Reranking lives on the Cohere-compatible routes, so it needs its own base URL.
RERANK_INSTANCE = "stdapi-ai-rerank"

#: Total time allowed for RAGFlow to report every backing service healthy.
HEALTH_TIMEOUT_SECONDS = 900

#: Total time allowed for the stdapi.ai gateway to answer the provider probe.
PROVIDER_TIMEOUT_SECONDS = 900

_session = requests.Session()
_credentials: tuple[str, str] = ("", "")


def encrypt_password(password: str) -> str:
    """Return the password in the form /auth/login expects: RSA over base64.

    This is the transform api/utils/crypt.py performs. It is reimplemented here
    rather than imported, because importing anything from the RAGFlow package
    loads its settings module, which needs the rendered service_conf.yaml this
    container never produces.
    """
    key = RSA.importKey(Path(PUBLIC_KEY_PATH).read_text(), "Welcome")
    cipher = PKCS1_v1_5.new(key)
    encoded = base64.b64encode(password.encode("utf-8"))
    return base64.b64encode(cipher.encrypt(encoded)).decode("utf-8")


def env(name: str) -> str:
    """Return a required environment variable, or exit with a clear message."""
    value = os.environ.get(name)
    if not value:
        sys.exit(f"bootstrap: {name} is not set")
    return value


def wait_healthy() -> None:
    """Block until RAGFlow reports database, cache, document engine and storage up."""
    deadline = time.time() + HEALTH_TIMEOUT_SECONDS
    last = ""
    while time.time() < deadline:
        try:
            response = requests.get(f"{API}/system/healthz", timeout=30)
            if response.status_code == 200:
                print(f"bootstrap: RAGFlow healthy: {response.text.strip()}", flush=True)
                return
            last = f"HTTP {response.status_code}: {response.text.strip()}"
        except requests.RequestException as error:
            last = str(error)
        print(f"bootstrap: waiting for RAGFlow ({last})", flush=True)
        time.sleep(10)
    sys.exit(f"bootstrap: RAGFlow never became healthy: {last}")


def login() -> None:
    """Authenticate the superuser and keep the token on the session.

    RAGFlow issues one access token per user, so a concurrent login elsewhere
    invalidates this one; call() logs in again when that happens.
    """
    email, password = _credentials
    payload = {"email": email, "password": encrypt_password(password)}
    response = _session.post(f"{API}/auth/login", json=payload, timeout=60)
    body = response.json()
    if body.get("code") != 0:
        sys.exit(f"bootstrap: login failed: {body.get('message')}")
    token = response.headers.get("Authorization")
    if not token:
        sys.exit("bootstrap: login succeeded but returned no Authorization header")
    _session.headers["Authorization"] = token


def call(method: str, path: str, body: dict | None = None) -> dict:
    """Send an authenticated request and return the decoded RAGFlow envelope."""
    for attempt in range(2):
        response = _session.request(method, f"{API}{path}", json=body, timeout=180)
        if response.status_code == 401 and attempt == 0:
            login()
            continue
        try:
            return response.json()
        except ValueError:
            sys.exit(f"bootstrap: {method} {path} returned non-JSON: {response.text[:500]}")
    return {}


def tolerated(message: str) -> bool:
    """Report whether a failure only means the object was already created."""
    lowered = (message or "").lower()
    return "already exist" in lowered or "duplicated" in lowered or "duplicate" in lowered


def ensure_provider(provider: str) -> None:
    """Register a model provider for the tenant."""
    result = call("PUT", "/providers", {"provider_name": provider})
    if result.get("code") != 0 and not tolerated(result.get("message", "")):
        sys.exit(f"bootstrap: adding provider {provider} failed: {result.get('message')}")
    print(f"bootstrap: provider {provider} registered", flush=True)


def ensure_instance(provider: str, name: str, base_url: str, api_key: str, models: list[dict]) -> None:
    """Create a provider instance, retrying while the gateway is still starting.

    Creating an instance verifies the API key by calling the model for real, so
    this only succeeds once the stdapi.ai service answers.
    """
    listed = call("GET", f"/providers/{provider}/instances")
    if name in {instance.get("instance_name") for instance in listed.get("data") or []}:
        print(f"bootstrap: instance {name} already exists", flush=True)
        return
    payload = {
        "instance_name": name,
        "api_key": api_key,
        "base_url": base_url,
        "model_info": models,
    }
    deadline = time.time() + PROVIDER_TIMEOUT_SECONDS
    while True:
        result = call("POST", f"/providers/{provider}/instances", payload)
        if result.get("code") == 0 or tolerated(result.get("message", "")):
            print(f"bootstrap: instance {name} ready", flush=True)
            return
        if time.time() >= deadline:
            sys.exit(f"bootstrap: creating instance {name} failed: {result.get('message')}")
        print(f"bootstrap: retrying instance {name}: {result.get('message')}", flush=True)
        time.sleep(15)


def set_default(provider: str, instance: str, model: str, model_type: str) -> None:
    """Bind one tenant default model to a model of a provider instance."""
    payload = {
        "model_provider": provider,
        "model_instance": instance,
        "model_name": model,
        "model_type": model_type,
    }
    result = call("PATCH", "/models/default", payload)
    if result.get("code") != 0:
        sys.exit(f"bootstrap: setting the default {model_type} model failed: {result.get('message')}")
    print(f"bootstrap: default {model_type} model set to {model}@{instance}@{provider}", flush=True)


def main() -> None:
    global _credentials

    chat_model = env("RAGFLOW_CHAT_MODEL")
    embedding_model = env("RAGFLOW_EMBEDDING_MODEL")
    rerank_model = env("RAGFLOW_RERANK_MODEL")
    api_key = env("STDAPI_API_KEY")
    openai_url = env("STDAPI_OPENAI_URL")
    _credentials = (env("DEFAULT_SUPERUSER_EMAIL"), env("DEFAULT_SUPERUSER_PASSWORD"))

    wait_healthy()
    login()

    ensure_provider(PROVIDER)
    ensure_instance(
        PROVIDER,
        CHAT_INSTANCE,
        openai_url,
        api_key,
        [{"model_name": chat_model, "model_type": ["chat"], "max_tokens": 32768}],
    )
    ensure_instance(
        PROVIDER,
        RERANK_INSTANCE,
        env("STDAPI_RERANK_URL"),
        api_key,
        [{"model_name": rerank_model, "model_type": ["rerank"], "max_tokens": 8192}],
    )

    ensure_instance(
        PROVIDER,
        EMBEDDING_INSTANCE,
        openai_url,
        api_key,
        [{"model_name": embedding_model, "model_type": ["embedding"], "max_tokens": 8192}],
    )

    set_default(PROVIDER, CHAT_INSTANCE, chat_model, "chat")
    set_default(PROVIDER, RERANK_INSTANCE, rerank_model, "rerank")
    set_default(PROVIDER, EMBEDDING_INSTANCE, embedding_model, "embedding")

    defaults = call("GET", "/models/default")
    print(f"bootstrap: tenant defaults: {json.dumps(defaults.get('data'))}", flush=True)


if __name__ == "__main__":
    main()
