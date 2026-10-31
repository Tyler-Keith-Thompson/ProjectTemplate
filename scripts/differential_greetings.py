"""Greetings against a reference written out in Python, with the `regex` package's extended
grapheme clusters (`\\X`) as the reference for Swift's Character count. Names are drawn from a
small alphabet with combining accents, emoji with skin tones and ZWJ sequences, and flags, so
punctuation can merge into the name's last character."""

import regex

MODULE = "Greetings"

ALPHABET = ["a", "B", " ", ",", "!", "é", "é", "́", "👋🏽", "👩‍💻", "🇨🇦", "‍"]


def generate(rng):
    name = "".join(rng.choice(ALPHABET) for _ in range(rng.randrange(0, 7)))
    modifiers = []
    for _ in range(rng.randrange(0, 5)):
        kind = rng.choice(["formal", "casual", "punctuated"])
        # A punctuation mark is one character; the cluster-breaking ZWJ alone is not offered.
        modifiers.append([kind, rng.choice(ALPHABET[:-1])] if kind == "punctuated" else [kind])
    return {"name": name, "modifiers": modifiers}


def reference(case):
    if not case["name"]:
        return {"threw": True}
    formal, punctuation = False, ""
    for modifier in case["modifiers"]:
        if modifier[0] == "punctuated":
            punctuation = modifier[1]
        else:
            formal = modifier[0] == "formal"
    text = ("Good day" if formal else "Hi") + ", " + case["name"] + punctuation
    return {"threw": False, "text": text, "characters": len(regex.findall(r"\X", text))}


def compare(case, mine, ref):
    if mine is None:
        return ["no answer"]
    problems = []
    for key in ("threw", "text", "characters"):
        if mine.get(key) != ref.get(key):
            problems.append(f"{key}: library {mine.get(key)!r}, reference {ref.get(key)!r}")
    return problems
