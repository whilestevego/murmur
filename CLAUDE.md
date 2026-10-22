# murmur

Swift text-to-speech for the terminal:

- `murmur` is the client.
- `murmurd` is a daemon that runs Kokoro on the Neural Engine through FluidAudio.
- `MurmurCore` is the library they share.

Run `make test`, `make lint` and `make format`. Text normalization is scored with `make nemo`, which needs the model
installed.

CI runs on every pull request. It runs the lint, a release build, the tests and `make nemo`, and runs the tests again
under the thread and address sanitizers. Compiler warnings fail the build and the tests.

## Comments

These rules apply to every comment in the repository:

- Swift doc comments (`///`) and inline comments (`//`)
- Objective-C headers
- Makefile help text
- Python

They're strict. Follow them in every comment you write. When you change code, also rewrite any comment near it that
breaks them.

### Writing

- Write in full sentences. Start with a capital letter, and end with a period.
- Put one idea in each sentence. Don't join clauses with colons, semicolons or dashes to fit more into a line. If a
  comment needs two ideas, write two sentences.
- Don't use arrows (`→`) or other shorthand in prose. Give examples as sentences, such as
  `For example, "1994" is read as "19 94".`
- Use plain, standard words, such as "directory" (not "folder"), "returns" and "fails". Avoid idioms, wordplay and
  unusual words such as "afresh".
- Don't address the reader as "you". A comment describes the code, not the reader.
- Use American English.

### What to say

- Say why, not what. A comment that repeats the code or the name in words is noise. Delete it.
- Doc comments describe the declaration's contract: what it does, what it returns, when it fails, units, valid ranges,
  what `nil` means, and side effects.
- Don't describe callers, tests or other call sites, such as "murmur prints this" or "the tests point it at a temp
  directory". Call sites change, and then the comment is wrong.
- Don't narrate history or changes, such as "now", "used to", "no longer", PR numbers or bug reports. That belongs in
  commit messages.
- Don't write filler to satisfy a linter. If a required doc comment has nothing more to say than the name, describe
  the contract anyway, such as the units, the default or what `nil` means.

### Doc comments (`///`)

Follow Apple's [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and DocC markup:

- Start with a single-sentence summary, followed by a blank `///` line before any more detail.
- Begin function and method summaries with a verb in the third person: "Returns…", "Writes…", "Splits…".
- Begin initializer summaries with "Creates…".
- Write a noun phrase for properties, constants, types and enum cases: "The directory that holds…".
- Write Boolean properties as "A Boolean value that indicates whether…".
- On every `public` or `package` function and initializer, add `- Parameter name:` (or `- Parameters:` for more than
  one) for each parameter, `- Returns:` for a non-`Void` result, and `- Throws:` for a function that throws. Skip the
  `- Returns:` line only if the summary already says exactly what's returned and when.
- Link other symbols with DocC's double backticks, as in the example below. Put code, paths and literal text in single
  backticks.

For example:

```swift
/// Returns the cached samples for a phrase.
///
/// Reading an entry marks it as recently used, so it's evicted last.
///
/// - Parameter key: The phrase's cache key, from ``cacheKey(_:voice:speed:)``.
/// - Returns: The samples, or `nil` if the phrase isn't cached.
```

### Inline comments (`//`)

- Put the comment on its own line above the code it explains. End-of-line comments are only for a few words, such as
  `// Empty.`
- Use `// MARK: - Title` to divide a long file into sections.
- Mark a deliberate shortcut that has a known limit with `// ponytail:`, then the limit and how to remove it, in full
  sentences. Use `//`, not `///`, because the marker isn't documentation.
- Every `// swift-format-ignore:` line must be followed by a comment explaining why the rule doesn't apply there.
