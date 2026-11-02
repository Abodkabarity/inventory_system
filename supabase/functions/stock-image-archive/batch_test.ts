import { archivePairs } from "./batch.ts";
function eq(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}
Deno.test("at most two products at once; each product is handled once", async () => {
  let active = 0, max = 0;
  const done: number[] = [];
  await archivePairs([1, 2, 3, 4, 5], async (item) => {
    active++;
    max = Math.max(max, active);
    await new Promise((r) => setTimeout(r, 5));
    done.push(item);
    active--;
  });
  eq(max, 2);
  eq(done.sort(), [1, 2, 3, 4, 5]);
  eq(active, 0);
});
Deno.test("rate limit waits for in-flight sibling, then stops before the next pair", async () => {
  const entered: number[] = [];
  let siblingSaved = false;
  const limit = new Error("429");
  let received: unknown;
  try {
    await archivePairs([1, 2, 3], async (item) => {
      entered.push(item);
      if (item === 1) throw limit;
      await new Promise((r) => setTimeout(r, 10));
      siblingSaved = true;
    });
  } catch (e) {
    received = e;
  }
  eq(received === limit, true);
  eq(siblingSaved, true);
  eq(entered, [1, 2]);
});
