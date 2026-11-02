/** Keep a pair within the job lease, even if one item fails or is rate limited.
 * Never release the lease while the sibling can still be writing images.
 */
export async function archivePairs<T>(
  items: T[],
  process: (item: T) => Promise<void>,
): Promise<void> {
  for (let i = 0; i < items.length; i += 2) {
    const results = await Promise.allSettled(
      items.slice(i, i + 2).map(process),
    );
    const failure = results.find((result) => result.status === "rejected");
    if (failure?.status === "rejected") throw failure.reason;
  }
}
