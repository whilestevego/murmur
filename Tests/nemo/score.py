#!/usr/bin/env python3
"""Scores murmur's text normalization against NeMo's English test cases.

Each case is a written form and a spoken form, separated by "~". A case passes when Kokoro's phonemes for murmur's
reading of the written form match its phonemes for the spoken form. Comparing phonemes means that digits murmur leaves
for FluidAudio to read still match NeMo's words. Stress marks, punctuation and the word "and" are ignored, so "one
hundred and twenty three" matches "one hundred twenty three".

exceptions.toml lists the cases that aren't checked against NeMo's reading. For a choice, murmur deliberately reads the
written form differently, so the case is checked against murmur's reading instead. A gap is a case that murmur doesn't
read well yet. Gaps are counted as gaps rather than failures, and a gap that starts to match NeMo is reported so that it
can be removed. The script exits with status 1 if any other case fails. Set SHOW=1 to print the failures. Run it with
make nemo.
"""
import os, re, subprocess, sys, tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
MURMURD = os.path.join(HERE, '../../.build/release/murmurd')
# murmurd is given this file in place of the user's own pronunciations, so that the scores don't depend on them.
PRONUNCIATIONS = os.path.join(HERE, '../Fixtures/pronunciations')
assert os.path.isfile(PRONUNCIATIONS), f'{PRONUNCIATIONS} is missing'
# A word placed between cases, so that the output can be split back into cases.
MARK = 'Zebra'

def sounds(texts):
    """Returns Kokoro's phonemes for each text, in order."""
    # The "--" keeps a case that starts with a dash, such as "-3", from being read as an option.
    text = f'\n{MARK}\n'.join(texts) + f'\n{MARK}'
    out = subprocess.run([MURMURD, '--phonemes', '--pronunciations', PRONUNCIATIONS, '--', text], capture_output=True, text=True, check=True).stdout
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

def exceptions():
    """Returns murmur's reading for each choice and the reason for each gap, from exceptions.toml.

    Exits with a message if the file doesn't have the expected structure, or lists a case twice.
    """
    path = os.path.join(HERE, 'exceptions.toml')
    with open(path, 'rb') as f:
        data = tomllib.load(f)
    if unknown := set(data) - {'choice', 'gap'}:
        sys.exit(f'{path}: unknown tables {sorted(unknown)}')
    expected, gaps = {}, {}
    for kind, groups in data.items():
        for group in groups:
            if set(group) != {'reason', 'cases'} or not isinstance(group['reason'], str):
                sys.exit(f'{path}: each [[{kind}]] needs a reason and its cases, but got {sorted(group)}')
            for case in group['cases']:
                if kind == 'choice' and (not isinstance(case, dict) or set(case) != {'written', 'reading'}):
                    sys.exit(f'{path}: each case of a choice needs a written form and a reading, but got {case!r}')
                if kind == 'gap' and not isinstance(case, str):
                    sys.exit(f'{path}: each case of a gap is its written form, but got {case!r}')
                written = case['written'] if kind == 'choice' else case
                if written in expected or written in gaps:
                    sys.exit(f'{path}: {written!r} is listed twice')
                if kind == 'choice':
                    expected[written] = case['reading']
                else:
                    gaps[written] = group['reason']
    return expected, gaps

expected, gaps = exceptions()
files = sorted(f for f in os.listdir(HERE) if f.endswith('.txt'))
cases = {name: [l.rstrip('\n').split('~', 1) for l in open(os.path.join(HERE, name)) if '~' in l] for name in files}
known = {written for name in files for written, _ in cases[name]}
for written in (expected.keys() | gaps.keys()) - known:
    sys.exit(f'{written!r} is in exceptions.toml, but in none of the NeMo cases')
# A choice is checked against murmur's reading instead of NeMo's.
cases = {name: [(written, expected.get(written, spoken)) for written, spoken in cases[name]] for name in files}
# Every written and spoken form goes to murmurd in one call, because each call loads the model.
said = iter(sounds([text for name in files for case in cases[name] for text in case]))
totals, fixed = [0, 0, 0], []
for name in files:
    counts, failed = [0, 0, 0], []
    for written, spoken in cases[name]:
        g, w = next(said), next(said)
        kind = 0 if plain(g) == plain(w) else 1 if written in gaps else 2
        counts[kind] += 1
        if kind == 0 and written in gaps:
            fixed.append(written)
        if kind == 2:
            failed.append(f'   ✗ {written!r} → want {spoken!r}\n       got  {plain(g)}\n       want {plain(w)}')
    totals = [a + b for a, b in zip(totals, counts)]
    print(f'{name[:-4]:14} {counts[0]:3} pass  {counts[1]:2} gaps  {counts[2]:2} fail')
    if os.environ.get('SHOW') and failed:
        print('\n'.join(failed))
print(f'{"all":14} {totals[0]:3} pass  {totals[1]:2} gaps  {totals[2]:2} fail  (of {sum(totals)})')
for written in fixed:
    print(f'{written!r} now matches NeMo, so it can be removed from the gaps in exceptions.toml')
sys.exit(1 if totals[2] else 0)
