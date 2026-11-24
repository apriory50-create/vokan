#!/usr/bin/env python3
"""Генерирует assets/seed.json (до 2000 слов и фраз) через любой OpenAI-совместимый API.

Запуск:
  AI_API_KEY=... AI_BASE_URL=https://api.openai.com/v1 AI_MODEL=gpt-4o-mini LEVEL=B1 python tools/gen_seed.py

Только стандартная библиотека Python. Результат проверяйте вручную.
"""
import json
import os
import re
import time
import urllib.request
from pathlib import Path

BASE = os.environ.get("AI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
KEY = os.environ["AI_API_KEY"]
MODEL = os.environ.get("AI_MODEL", "gpt-4o-mini")
OUT = Path(__file__).resolve().parent.parent / "assets" / "seed.json"
PER_THEME = 100
LEVEL = os.environ.get("LEVEL", "B1")

THEMES = [
    "частотные глаголы действия (get, take, put, bring, keep, turn, set ...)",
    "фразовые глаголы с get, go, put, take, come, look, make",
    "частотные прилагательные для описания людей, вещей и ситуаций",
    "существительные повседневной жизни (дом, еда, вещи, люди)",
    "работа, офис, бизнес, переговоры",
    "путешествия, транспорт, отели, аэропорт",
    "здоровье, тело, самочувствие, врач",
    "эмоции, характер и отношения между людьми",
    "коллокации с make, do, have, take, give",
    "связки и дискурсивные маркеры (however, in addition, as a result ...)",
    "разговорные фразы для small talk",
    "фразы для просьб, отказов, извинений, благодарности",
    "фразы для спора, аргументации и согласия",
    "идиомы средней частотности",
    "технологии, интернет, гаджеты",
    "деньги, покупки, финансы",
    "образование, учёба, экзамены",
    "общество, новости, нейтральные общественные темы",
    "природа, погода, окружающая среда",
    "мнения, планы, опыт и истории (agree, suppose, realize, experience ...)",
    "программирование и разработка ПО (deploy, bug, release, API, commit, refactor)",
    "интерфейсы приложений и сайтов (sign up, settings, dashboard, notification)",
]

PROMPT = """Ты составляешь словарь для русскоязычного ученика уровня {level} (CEFR). Все слова и фразы должны относиться к уровню {level}.
Тема: {theme}.
Верни ТОЛЬКО JSON-массив из {n} объектов, без пояснений и без markdown.
Каждый объект: {{"en": "...", "ru": "...", "example": "...", "kind": "word" или "phrase"}}
- en: лемма слова или полезная фраза/коллокация (не полное предложение).
- ru: точный краткий перевод на русский (1–4 слова).
- example: естественное английское предложение до 15 слов с этим en.
- kind: "word" для одного слова, "phrase" для фразы.
- Без повторов внутри списка.
"""


def chat(prompt: str) -> str:
    body = json.dumps({
        "model": MODEL,
        "temperature": 0.7,
        "messages": [{"role": "user", "content": prompt}],
    }).encode("utf-8")
    req = urllib.request.Request(
        f"{BASE}/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)["choices"][0]["message"]["content"]


def parse(text: str):
    text = re.sub(r"^```(?:json)?\s*|```\s*$", "", text.strip(), flags=re.M).strip()
    start, end = text.find("["), text.rfind("]")
    return json.loads(text[start:end + 1])


def main():
    seen, out = set(), []
    for theme in THEMES:
        items = None
        for attempt in range(3):
            try:
                items = parse(chat(PROMPT.format(level=LEVEL, theme=theme, n=PER_THEME)))
                break
            except Exception as e:  # noqa: BLE001
                print(f"retry {attempt + 1} for '{theme}': {e}")
                time.sleep(3)
        if items is None:
            print(f"SKIP theme: {theme}")
            continue
        for it in items:
            en = str(it.get("en", "")).strip()
            if not en or en.lower() in seen:
                continue
            seen.add(en.lower())
            out.append({
                "en": en,
                "ru": str(it.get("ru", "")).strip(),
                "example": str(it.get("example", "")).strip(),
                "cefr": LEVEL,
                "kind": it.get("kind", "word") if it.get("kind") in ("word", "phrase") else "word",
            })
        print(f"{theme}: total {len(out)}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=0), encoding="utf-8")
    print(f"saved {len(out)} entries -> {OUT}")


if __name__ == "__main__":
    main()
