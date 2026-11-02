export function mayReadImage(role: string, active: boolean | null | undefined) {
  return active !== false &&
    ["inventory", "view"].includes(role.trim().toLowerCase());
}
export function mayUploadImage(
  role: string,
  active: boolean | null | undefined,
) {
  return active !== false && role.trim().toLowerCase() === "inventory";
}
