#!/usr/bin/env python3
"""The census of Tempo's exported functions.

Joins what each module exports (`exports.tsv`) with who calls it
(`calls_lib.tsv`, `calls_test.tsv`), counts the mentions in the guides, sorts
the documented functions into areas, and writes the census as Markdown.
`scripts/public_surface/run.sh` produces the three files and runs this.
"""
import collections
import glob
import re
import sys

work, out_path = sys.argv[1], sys.argv[2]

# The engine: documented for contributors under ExDoc's "Internals" group
# (`groups_for_modules` in mix.exs), and not the API a caller uses.
ENGINE = re.compile(
    r"^Tempo\.(Compare|Microsecond|UnitValues|Interval\.(Steps|Cycle)|Network\.Normalize"
    r"|RRule\.(Expander|Rule|Selection)|Iso8601\.Tokenizer(\.\w+)?)$"
)

SET_OPERATIONS = {
    "union", "intersection", "difference", "symmetric_difference", "complement",
    "members_outside", "members_overlapping", "members_in_exactly_one", "overlaps?",
    "disjoint?", "within?", "contains?", "equal?",
}
CERTAINTY = {
    "certainly_before?", "certainly_after?", "certainly_overlaps?", "certainly_within?",
    "possibly_before?", "possibly_after?", "possibly_overlaps?", "possibly_within?",
    "overlap_certainty", "within_certainty", "relation_certainty",
}
LENGTHS = {"at_least?", "at_most?", "exactly?", "longer_than?", "shorter_than?"}
WORKDAYS = {
    "workday?", "weekend?", "add_workdays", "count_workdays", "next_workday",
    "previous_workday", "nearest_workday", "roll_to_workday", "in_territory",
}
READING = {
    "year", "month", "day", "hour", "minute", "second", "week", "day_of_week", "day_of_year",
    "quarter_of_year", "season", "days_in_month", "leap_year?", "resolution", "duration",
    "duration!", "metadata", "put_metadata", "qualification", "anchored?", "bounded?",
    "empty?", "floating?", "zoned?",
}
# What the compiler calls of a module, which no caller names. The callbacks
# of a behaviour or a protocol are marked in `exports.tsv`.
CALLBACKS = {"__struct__", "__using__", "__impl__", "__before_compile__", "__on_definition__"}

AREAS = [
    "Construction", "Enumeration", "Selection", "Set operations", "Networks",
    "Relations and comparison", "Lengths", "Arithmetic", "Conversion and text",
    "Reading a value", "Zones and leap seconds", "Workdays", "The clock",
    "The engine, documented", "Strays",
]
PRIMARY = AREAS[:5]


def area(module, name):
    if ENGINE.match(module):
        return "The engine, documented"
    if module == "Tempo":
        if name in SET_OPERATIONS:
            return "Set operations"
        if name in ("select", "select!", "at", "at!", "on", "on!", "workdays", "weekends"):
            return "Selection"
        if name in ("map", "try_map", "extend", "extend!", "extend_resolution", "at_resolution", "split"):
            return "Enumeration"
        if name.startswith(("new", "from_", "parse", "to_interval")) or name in ("now", "utc_now", "today", "utc_today"):
            return "Construction"
        if name in CERTAINTY or name in ("relation", "compare", "before?", "after?", "adjacent?"):
            return "Relations and comparison"
        if name in LENGTHS:
            return "Lengths"
        if name in ("shift", "round", "trunc"):
            return "Arithmetic"
        if name.startswith("to_") or name == "explain":
            return "Conversion and text"
        if name in READING:
            return "Reading a value"
        if name in ("in_zone", "shift_zone", "validate_zone_offset"):
            return "Zones and leap seconds"
        if name in WORKDAYS:
            return "Workdays"
    if module == "Tempo.Interval":
        if name.startswith("new"):
            return "Construction"
        if name in CERTAINTY or name in ("relation", "before?", "after?", "adjacent?", "within?"):
            return "Relations and comparison"
        if name in LENGTHS:
            return "Lengths"
        if name in ("spans_leap_second?", "leap_seconds_spanned"):
            return "Zones and leap seconds"
        return "Strays" if name == "next_unit_boundary" else "Reading a value"
    if module == "Tempo.IntervalSet":
        if name in ("new", "new!", "from_stream"):
            return "Construction"
        if name in ("members", "count", "first", "last", "walk", "map", "filter", "slots"):
            return "Enumeration"
        if name in ("coalesce", "covered", "covered?", "relation_matrix"):
            return "Set operations"
        return "Reading a value"
    if module == "Tempo.RecurrenceSet":
        if name in ("members", "filter"):
            return "Enumeration"
        return "Reading a value" if name == "metadata" else "Construction"
    if module == "Tempo.Duration":
        return "Construction" if name.startswith("new") else "Arithmetic"
    if module in ("Tempo.RRule", "Tempo.Cron", "Tempo.ICal", "Tempo.JSCalendar"):
        return "Conversion and text" if name.startswith("to_string") else "Construction"
    if module == "Tempo.Sigils":
        return "Construction"
    if module in ("Tempo.Select", "Tempo.Event", "Tempo.Territory"):
        return "Selection"
    if module == "Tempo.Operations":
        return "Set operations"
    if module.startswith(("Tempo.Network", "Tempo.Schedule")) or module in (
        "Tempo.Interval.RelationNetwork", "Tempo.Interval.Relations"):
        return "Networks"
    if module == "Tempo.Allen":
        return "Relations and comparison"
    if module in ("Tempo.Explain", "Tempo.Format"):
        return "Conversion and text"
    if module in ("Tempo.TimeZoneDatabase", "Tempo.LeapSeconds"):
        return "Zones and leap seconds"
    if module.startswith("Tempo.Clock"):
        return "The clock"
    return "Strays"


functions, generated = [], collections.Counter()
for line in open(f"{work}/exports.tsv"):
    source, module, moduledoc, kind, name, arity, defaults, doc, crosses, callback = line.rstrip("\n").split("\t")
    # The steps NimbleParsec generates for a combinator another module calls.
    if re.search(r"__\d+$", name):
        generated[module] += 1
        continue
    functions.append(dict(
        source=source, module=module, moduledoc=moduledoc, kind=kind, name=name, arity=int(arity),
        defaults=int(defaults), doc=doc, crosses=crosses == "true",
        callback=callback == "true" or name in CALLBACKS,
        own=0, lib=0, lib_modules=set(), tests=0, guides=0))

index = collections.defaultdict(list)
for function in functions:
    for arity in range(function["arity"] - function["defaults"], function["arity"] + 1):
        index[(function["module"], function["name"], arity)].append(function)


def load(path, from_tests):
    for line in open(path):
        fields = line.rstrip("\n").split("\t")
        if len(fields) != 6:
            continue
        module, name, arity, caller, _function, site = fields
        for function in index.get((module, name, int(arity)), []):
            if from_tests or not site.startswith("lib/"):
                function["tests"] += 1
            elif caller == module:
                function["own"] += 1
            else:
                function["lib"] += 1
                function["lib_modules"].add(caller)


load(f"{work}/calls_lib.tsv", False)
load(f"{work}/calls_test.tsv", True)

prose = "".join(open(path).read() for path in glob.glob("guides/*.md") + glob.glob("livebook/*.livemd") + ["README.md"])
for function in functions:
    function["guides"] = len(re.findall(re.escape(f"{function['module']}.{function['name']}") + r"[(/]", prose))


def written(function):
    low = function["arity"] - function["defaults"]
    arity = str(function["arity"]) if function["defaults"] == 0 else f"{low}..{function['arity']}"
    return f"`{function['module']}.{function['name']}/{arity}`"


def kind_of(function):
    if function["moduledoc"] != "documented":
        return "hidden module"
    return {"documented": "documented", "hidden": "`@doc false`", "none": "no `@doc`"}[function["doc"]]


def use_of(function):
    outside = function["tests"] + function["guides"]
    if function["callback"]:
        return "a callback"
    if function["lib"] == 0 and function["own"] == 0 and outside == 0:
        return "no caller"
    if function["lib"] == 0 and outside == 0:
        return "its own module only"
    if function["lib"] == 0:
        return "tests or guides, and no other module"
    if outside == 0:
        return "other modules, and no test or guide"
    return "other modules, and tests or guides"


documented = [f for f in functions if kind_of(f) == "documented"]
lines = [
    "# Public surface census",
    "",
    "Generated by `zsh scripts/public_surface/run.sh`; do not edit. Every function and macro a module under `lib/` exports, how it is documented, and who calls it: its own module, other modules of the library, the tests (doctests among them), and the guides, the livebooks and the README. The evaluation that reads it is [public-surface.md](public-surface.md).",
    "",
    "## Counts",
    "",
    f"The library exports {len(functions) + sum(generated.values()):,} functions and macros. {sum(generated.values()):,} of them are the steps NimbleParsec generates for a combinator another module calls ({', '.join(f'`{m}` {n:,}' for m, n in generated.most_common())}), and are set aside. The other {len(functions)}, in {len({f['module'] for f in functions})} modules:",
    "",
    "| Documented as | Functions | No caller | Own module only | Tests or guides only | Other modules only | Other modules and tests | A callback |",
    "|---|---|---|---|---|---|---|---|",
]
uses = ["no caller", "its own module only", "tests or guides, and no other module",
        "other modules, and no test or guide", "other modules, and tests or guides", "a callback"]
for kind in ["documented", "`@doc false`", "no `@doc`", "hidden module"]:
    of_kind = [f for f in functions if kind_of(f) == kind]
    counts = collections.Counter(use_of(f) for f in of_kind)
    lines.append(f"| {kind} | {len(of_kind)} | " + " | ".join(str(counts[use]) for use in uses) + " |")

lines += ["", f"{sum(1 for f in functions if f['crosses'])} functions cross the border (`Tempo.Border`): the documented ones, and those of the protocol implementations.", "",
          "## Documented functions, by area", "",
          "| Area | Functions | Named in a guide | Called in a test | Called by another module |", "|---|---|---|---|---|"]
by_area = collections.defaultdict(list)
for function in documented:
    by_area[area(function["module"], function["name"])].append(function)
for name in AREAS:
    of_area = by_area[name]
    lines.append(f"| {name} | {len(of_area)} | {sum(1 for f in of_area if f['guides'])} | {sum(1 for f in of_area if f['tests'])} | {sum(1 for f in of_area if f['lib'])} |")
lines += ["", f"The first five areas are the primary API ({sum(len(by_area[a]) for a in PRIMARY)} functions). The columns below count mentions in the guides, calls from tests, and calls from other modules of the library."]

for name in AREAS:
    lines += ["", f"### {name}", "", "| Function | Guides | Tests | Other modules |", "|---|---|---|---|"]
    for function in sorted(by_area[name], key=lambda f: (f["module"], -f["guides"], f["name"], f["arity"])):
        lines.append(f"| {written(function)} | {function['guides']} | {function['tests']} | {function['lib']} |")

lines += ["", "## Exported and not documented", "",
          "A function here is exported and is no part of the documented API. One only its own module calls needs no export; one no caller names at all, that is no callback, is dead."]
for kind in ["`@doc false`", "no `@doc`", "hidden module"]:
    of_kind = [f for f in functions if kind_of(f) == kind and not f["callback"]]
    lines += ["", f"### {kind[0].upper() + kind[1:] if not kind.startswith('`') else kind}", "",
              "| Function | Own module | Other modules | Tests | Use |", "|---|---|---|---|---|"]
    for function in sorted(of_kind, key=lambda f: (f["module"], f["name"], f["arity"])):
        lines.append(f"| {written(function)} | {function['own']} | {function['lib']} | {function['tests']} | {use_of(function)} |")

open(out_path, "w").write("\n".join(lines) + "\n")
print(f"{len(functions)} functions, {len(documented)} documented; wrote {out_path}")
