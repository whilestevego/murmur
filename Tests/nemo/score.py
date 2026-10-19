#!/usr/bin/env python3
"""Scores murmur's text cleanup against NeMo's English normalization cases (make nemo).

Each case is written form ~ spoken form. murmur passes when its sounds for the written form match Kokoro's sounds for
the spoken one, so digits murmur leaves for FluidAudio to read count the same as NeMo's words. Stress marks,
punctuation and "and" are ignored: "one hundred and twenty three" and "one hundred twenty three" are both right.
deviations.txt lists the cases murmur reads differently on purpose. Exits 1 if anything else fails; SHOW=1 prints it.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MURMURD = os.path.join(HERE, '../../.build/release/murmurd')
MARK = 'Zebra'  # a word between cases, to split the output back up

def sounds(texts):
    out = subprocess.run([MURMURD, '--phonemes', f'\n{MARK}\n'.join(texts) + f'\n{MARK}'], capture_output=True, text=True, check=True).stdout
    groups, current = [], []
    for line in out.splitlines():
        if re.sub(r'[ˈˌ.,!?;:\s]', '', line) == 'zibɹə':
            groups.append(' '.join(current))
            current = []
        else:
            current.append(line)
    assert len(groups) == len(texts), 'the output no longer lines up with the cases'
    return groups

def plain(s):
    return re.sub(r'\s+', ' ', re.sub(r'\bænd\b', ' ', re.sub(r'[ˈˌ.,!?;:—…"()-]', ' ', s))).strip()

deviations = {l.split('~')[0] for l in open(os.path.join(HERE, 'deviations.txt')) if '~' in l and not l.startswith('#')}
totals = [0, 0, 0]
for name in sorted(f for f in os.listdir(HERE) if f.endswith('.txt') and f != 'deviations.txt'):
    cases = [l.rstrip('\n').split('~', 1) for l in open(os.path.join(HERE, name)) if '~' in l]
    got, want = sounds([w for w, _ in cases]), sounds([s for _, s in cases])
    counts, failed = [0, 0, 0], []
    for (written, spoken), g, w in zip(cases, got, want):
        kind = 0 if plain(g) == plain(w) else 1 if written in deviations else 2
        counts[kind] += 1
        if kind == 2:
            failed.append(f'   ✗ {written!r} → want {spoken!r}\n       got  {plain(g)}\n       want {plain(w)}')
    totals = [a + b for a, b in zip(totals, counts)]
    print(f'{name[:-4]:14} {counts[0]:3} pass  {counts[1]:2} on purpose  {counts[2]:2} fail')
    if os.environ.get('SHOW'):
        print('\n'.join(failed))
print(f'{"all":14} {totals[0]:3} pass  {totals[1]:2} on purpose  {totals[2]:2} fail  (of {sum(totals)})')
sys.exit(1 if totals[2] else 0)
