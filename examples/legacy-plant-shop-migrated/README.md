# legacy-plant-shop, after the migration

This is [`../legacy-plant-shop`](../legacy-plant-shop) after one run of the migration agent: jQuery and untyped
JavaScript became **strict TypeScript with plain DOM code, no jQuery**. Run both with `npm install && npm run dev`
and compare: the page looks and behaves the same.

- Every module is `.ts`; nothing in `src/` imports jQuery.
- The original 2 tests are unchanged; 6 pin tasks added 46 characterization tests first (cart, catalog, view
  markup, `mount()` behaviour, the entry point, negative money). All 48 pass on the old code and on this one.
- After the same 7 clicks (filter, add, remove), both pages render byte-identical HTML.
- The JavaScript bundle went from 92.8 KB to 6.5 KB (33.5 KB to 2.3 KB gzipped).
- 10 tasks, about 11 minutes of model time. The plan the agent followed is [`MIGRATION.md`](MIGRATION.md).
  jQuery is still listed in `package.json` (out of scope); removing it is a separate change.

---

# legacy-plant-shop

A small shop page in **jQuery** and untyped JavaScript: plant cards with light filters, an add-to-cart flow
with stock limits, a cart with remove buttons, totals, and a free-shipping progress bar. Demo target for
the migration agent: move it to **TypeScript with plain DOM code (no jQuery)** without changing how it looks or
behaves.

Only `src/format.js` has tests. The page is mounted with `mount(root)` from `src/app`, which is the public
boundary tests use (in jsdom), so the same tests work before and after.

    npm install
    npm run dev        # view it at the printed URL
    npm test
    npm run typecheck
