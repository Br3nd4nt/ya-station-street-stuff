from pathlib import Path

lines = Path("maind.strings").read_text(errors="replace").splitlines()
terms = [
    "Start listening ButtonCapabilityCondition",
    "VoiceServiceState::onStartDataInput",
    "Handling button event:",
    "onButtonPressed",
    "ButtonActionLocked",
    "button_event_resolver.cpp",
    "DevInputButtons.OpenNodeFailed",
]

for term in terms:
    matches = [i for i, line in enumerate(lines) if term.lower() in line.lower()]
    print(f"\n{'=' * 70}\n{term}: {len(matches)} matches")
    for i in matches[:3]:
        start, end = max(0, i - 4), min(len(lines), i + 5)
        for j in range(start, end):
            print(f"{j + 1}: {lines[j]}")
