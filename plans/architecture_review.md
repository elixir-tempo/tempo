Your job is to review the architecture, data structures, design choices and implementation approaches for the Tempo library (~/Development/tempo/tempo). Then make recommendations and plan to re-implement Tempo using the new architecture and implementation design. You may consult the plans for the library in the plans directory, consult the Calendrical and Localize libraries and any of the research papers in the repo. You may make observations and recommendations for the Calendrical and Tempo libraries but the Localize library is widely used and should remain stable.

## The principles of this library are:
1. to represent time as intervals, not instants. 
2. To be able to invoke the the core capabilities over a resolution-independent time
3. Since all times are intervals, the primary operations are set operaations
4. Tempo is calendar independent. Using Calendrical as one source of calendars, Tempo should never have to introspect a calendar.

## The headline capabilities at the core of the library are:
1. Full ISO8601 parsing and implementation (See the standards in Tempo source tree). The existing tokenizer is considered acceptable but if a full and correct ABNF-based parser rewrite fits into the redesign, so be it.
2. Enumeration over any interval
3. Set operations between intervals
4. Projection of an interval over another (Tempo.select)
5. Predicates and comparators over the Allen Interval algebra
6. Support for anchored (time has a year so can be placed on the universal timeline) and unanchored (abstract time that needs to be anchored in order to be placed)
7. Time need to be parsed and formatted as output strings using Localize.
8. The guides represent the best illustration of the lofty intent of this library. Its my hope that if we get this right, this library can act as a model for how other language ecosystems might implement the same ideas.
9. Expressiveness is important. That we can enumerate `~o"2026"` and know what we will return a set of months is conceptually clean and clear. The model being that we enumerate at the next finest resolution. That principle of conceptual clarity we want to maintain and preserve everywhere.

## Issues with the current implementation
1. The current implementation is largely complete but I'm concered that since it grew organically, its now overly complex and the underlying principles are lost in that complexity.
2. Time, especially time as intervals and not instants, is already a complex and new idea for most people. Therefore, the code needs to be written with clarity and simplicity in mind. Especially around the core operations of enumeration, projection/selection, set operations
3. I feel like we should be able to have a single data structure to represent everything we need (a plain Tempo, an Interval, a Recurrence and a Recurrence Set). Previous efforts have not found an efficient way to collapse the data structures to a single type. But if thats possible its a good win.
4. Tempo current implementation has result in the creation of a large number of callbacks in the Calendrical behaviour. I expect these callbacks can be consolidated, simplified and made clearer

## Expectations
1. An architectural and data structure review of the current implementation
2. Recommendations on how to re-architect it, preserving the primary API as documented by the guides
3. A clearer, simpler, more readable reference implementation for parsing, enumeration, set operations, shift functions, predicates, Allen comparators
4. A simpler, cleaner set of callbacks for Calendrical to represent the requirements needed by Tempo