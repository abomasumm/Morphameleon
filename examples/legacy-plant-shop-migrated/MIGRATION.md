# Migration plan
<!-- Written by .agents/migrate.sh init on 2026-10-31 04:19:22. Edit freely: the planner and every worker read this file. -->

## Migration
- From: JavaScript (ES modules)
- To: TypeScript (strict) with plain DOM APIs instead of jQuery, ES modules

## Scope
In scope:
- src/
Never touch:
- existing tests
- package.json and lockfile
- build and tool config

## Behaviour that must not change
- money(12.3) returns "$12.30" and money(-12.3) returns "$-12.30" (the minus sign comes after the dollar sign)
- plural(1, "plant") returns "1 plant" and plural(2, "plant") returns "2 plants"
- byLight(PLANTS, "low") returns plants with ids snake, pothos, and zz in their original order, while byLight(PLANTS, "all") returns a copy of every plant
- createCart().add returns false for a plant with stock 0 and returns true for a plant with positive stock, adding a line with qty 1 and notifying listeners once
- createCart().add increments an existing line only while qty is below plant.stock, returns false at the stock limit, and leaves the cart unchanged
- createCart shipping returns 0 for a subtotal of 0 or at least 75 and otherwise returns 6.5, while total returns subtotal plus shipping

## Rules
- New dependencies allowed: no
- Public API changes allowed: no
- Tests: existing tests are never edited. Untested modules get characterization tests first (pin tasks).
- One module per migrate task, in the dependency order below.

## Approach
- Convert the jQuery-free modules one at a time, leaves first: src/format.js, src/catalog.js, src/cart.js
- Then replace jQuery in src/view.js and src/app.js together in one task (app delegates clicks to elements view builds), with src/main.js
- The public boundary is mount(root) from src/app: it renders into root and returns the cart
- The rendered markup must stay identical (elements, classes, data-id and data-light attributes, text, disabled states, the shipping bar width) so the page looks and behaves the same
- jquery stays in package.json
- removing the dependency is a separate change

## Done when
- no .js files left in src/
- no jquery imports anywhere in src/
- all tests, the typecheck and the vite build pass

## Commands
- test: `npm test`
- typecheck: `npm run typecheck`
- build: `npm run build`
- Baseline on 2026-10-31: green

## Modules (dependency order: migrate from the top)
| Module | Lines | Imports | Imported by | Tests | Risk |
|---|---|---|---|---|---|
| `src/cart.js` | 40 |  | 1 | none | no tests |
| `src/catalog.js` | 14 |  | 1 | none | no tests |
| `src/format.js` | 9 |  | 1 | test/format.test.js |  |
| `src/view.js` | 44 | format.js | 1 | none | no tests, critical |
| `src/app.js` | 44 | cart.js, catalog.js, view.js | 1 | none | no tests, critical |
| `src/main.js` | 2 | app.js | 0 | none | no tests |

## Existing tests (what they already cover)
- `test/format.test.js`: format; formats money with two decimals; pluralizes

## Notes from the setup model (MiniMax-M3.1-Flash)
- The cart API exposes its mutable lines array, so replacing it with a copied or immutable type would be a breaking change
- shipping, total, and toFreeShipping rely on being called as cart methods through this, so extracting their values into unbound functions would change behavior
- cart.onChange listeners receive no arguments and run only after successful add or remove mutations
- money rounds with Math.round(n * 100), which can expose binary floating-point behavior for values such as 1.005
- view.js depends on delicate jQuery chaining and returns jQuery elements rather than native DOM nodes
- Relative ES module imports omit file extensions, so the TypeScript module-resolution configuration must preserve the existing bundler behavior
