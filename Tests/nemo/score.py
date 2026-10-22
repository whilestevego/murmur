#!/usr/bin/env python3
"""Scores murmur's text normalization against NeMo's English test cases.

Each case is a written form and a spoken form, separated by "~". A case passes when Kokoro's phonemes for murmur's
reading of the written form match its phonemes for the spoken form. Comparing phonemes means that digits murmur leaves
for FluidAudio to read still match NeMo's words. Stress marks, punctuation and the word "and" are ignored, so "one
hundred and twenty three" matches "one hundred twenty three".

The cases in deviations.txt are ones that murmur reads differently on purpose. The script exits with status 1 if any
other case fails. Set SHOW=1 to print the failures. Run it with make nemo.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MURMURD = os.path.join(HERE, '../../.build/release/murmurd')
# murmurd reads this file in place of the user's own pronunciations, so that the scores don't depend on them.
PRONUNCIATIONS = os.path.join(HERE, '../Fixtures/pronunciations')
assert os.path.isfile(PRONUNCIATIONS), f'{PRONUNCIATIONS} is missing'
# A word placed between cases, so that the output can be split back into cases.
MARK = 'Zebra'

def sounds(texts):
    """Returns Kokoro's phonemes for each text, in order."""
    out = subprocess.run([MURMURD, '--phonemes', f'\n{MARK}\n'.join(texts) + f'\n{MARK}'], capture_output=True, text=True, check=True,
                         env={**os.environ, 'MURMUR_PRONUNCIATIONS': PRONUNCIATIONS}).stdout
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
    """Returns phonemes without stress marks, punctuation or the word "and"."""
    return re.sub(r'\s+', ' ', re.sub(r'\bænd\b', ' ', re.sub(r'[ˈˌ.,!?;:—…"()-]', ' ', s))).strip()

deviations = {l.split('~')[0] for l in open(os.path.join(HERE, 'deviations.txt')) if '~' in l and not l.startswith('#')}
files = sorted(f for f in os.listdir(HERE) if f.endswith('.txt') and f != 'deviations.txt')
cases = {name: [l.rstrip('\n').split('~', 1) for l in open(os.path.join(HERE, name)) if '~' in l] for name in files}
# Every written and spoken form goes to murmurd in one call, because each call loads the model.
said = iter(sounds([text for name in files for case in cases[name] for text in case]))
totals = [0, 0, 0]
for name in files:
    counts, failed = [0, 0, 0], []
    for written, spoken in cases[name]:
        g, w = next(said), next(said)
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
