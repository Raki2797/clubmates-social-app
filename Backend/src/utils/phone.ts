export function normalizePhone(phone: string): string {
  const trimmed = phone.trim();
  if (trimmed.startsWith("+")) {
    return `+${trimmed.slice(1).replace(/\D/g, "")}`;
  }

  return `+${trimmed.replace(/\D/g, "")}`;
}

export function assertValidPhone(phone: string): void {
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    throw new Error("Phone number must be E.164 formatted, e.g. +919876543210");
  }
}
