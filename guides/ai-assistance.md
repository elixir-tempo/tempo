# Using Tempo with an AI assistant

Tempo is deceptively deep. ISO 8601-2 lets you say remarkably precise things — "June 2004, approximately", "the second Monday of every month", "some day in the 1560s", "1200 give or take 60 years" — but the syntax is obtuse, and on top of it sit enumeration, set algebra, Allen relations (crisp and graded-under-uncertainty), recurrence, dependency scheduling, and constraint networks. Even when you know exactly what you want, it isn't obvious *which layer* solves it or how to spell the value.

So the fastest way into Tempo is often to **describe your problem in plain language and let an AI assistant map it to Tempo for you.** Tempo ships a Claude *skill* that does exactly this: it picks the right layer, writes the value in correct `~o"…"` syntax, *validates and runs it*, and explains the result — as code for a developer, or as a plain-language answer for a researcher who never wants to see Elixir.

## What the skill does

Give it a sentence like any of these and it will represent and solve it:

* *"Do these two delivery windows clash?"* → Allen relations (`overlaps?`, `relation/2`).

* *"When is everyone free for an hour on Monday?"* → set algebra (`difference`, `intersection`) and bookable `slots/3`.

* *"List the second Monday of every month next year."* → recurrence (`Tempo.RRule.parse!/2`, then `Tempo.to_interval/2`).

* *"Given these radiocarbon dates ±, which finds could be contemporary?"* → relations that answer in three values (`Tempo.certainty/3`, `Tempo.certainly?/3`, `Tempo.possibly?/3`).

* *"Order these dependent tasks and find the critical path."* → the companion package `tempo_network`.

* *"These reigns and strata only have relative dates — are they consistent, and what do they pin down?"* → `tempo_network`'s constraint networks.

Because ISO 8601-2 is easy to get subtly wrong (`2004-06~-11` and `2004-?06-11` mean different things), the skill's first rule is to **never present a value it hasn't validated** — it parses every representation and echoes its meaning back with `Tempo.explain/1` before building on it.

## Installing the skill

The skill ships as a Claude Code **plugin** from the Tempo GitHub repo, so improvements reach every user without waiting on a hex release. Install it once:

```sh
/plugin marketplace add elixir-tempo/tempo
/plugin install tempo@tempo-plugins
```

Pull later updates with `/plugin marketplace update tempo-plugins`. Skills load at the start of a session, so open a fresh Claude Code session after installing.

The skill source lives at `skills/tempo/` in the repo (a `SKILL.md` plus an ISO 8601-2 cheat-sheet and a recipe catalogue). If you work from a local checkout and would rather not use the plugin, symlink it into your user skills directory instead:

```sh
mkdir -p ~/.claude/skills
ln -s "$PWD/skills/tempo" ~/.claude/skills/tempo   # from a Tempo checkout
```

A symlink tracks the checkout, so skill edits are picked up immediately — handy while developing.

## Using it

Just describe the problem. You don't need to name a function or know the syntax:

> *"I have a hearth carbon-dated to about 1200 ± 60 years and a midden to about 1240 ± 40. Could they be from the same generation?"*

The assistant will represent each as `~o"1200±60Y"` and `~o"1240±40Y"` (validating them), ask `Tempo.certainty(:overlaps, hearth, midden)`, which answers `:possible`, and say: *"They might be contemporary, but the dates aren't tight enough to be sure."* Ask it to "show the Elixir" if you want the code.

## Coming next: the Tempo MCP

The skill teaches an assistant to *write and run* Tempo inside a coding session. A companion **MCP server** (planned; see the tool spec in the repo) will expose Tempo's operations as callable tools — `parse`, `explain`, `relate`, `set`, `occurrences`, `schedule`, `network` — so an assistant can *execute* Tempo for you with no project checkout and no terminal. That's aimed squarely at researchers, historians, and archaeologists: describe a temporal question in a chat client and get a grounded answer back, in your own language, without touching code.
