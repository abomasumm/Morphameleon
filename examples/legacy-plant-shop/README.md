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
