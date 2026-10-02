import { normalizeError } from "../_shared/errors.ts";
import { corsFor } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  const corsHeaders = corsFor(request);
  const requestId = crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return errorResponse("VALIDATION", "Gunakan POST.", 405, requestId, corsHeaders);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return errorResponse("UNAUTHORIZED", "Sesi diperlukan.", 401, requestId, corsHeaders);
  try {
    const baseUrl = required("SUPABASE_URL"), anonKey = required("SUPABASE_ANON_KEY");
    const dashboardResponse = await fetch(`${baseUrl}/functions/v1/ios-data/dashboard-full`, { method: "POST", headers: { authorization, apikey: anonKey } });
    if (!dashboardResponse.ok) throw await dashboardResponse.json();
    const dashboard = await dashboardResponse.json() as Record<string, unknown>;
    for (const [table, property] of [['ai_consents','aiConsent'],['support_tickets','supportTickets']]) {
      const rows: unknown[] = [];
      for (let offset = 0;; offset += 1000) {
        const response = await fetch(`${baseUrl}/rest/v1/${table}?select=*&limit=1000&offset=${offset}&order=${table === 'ai_consents' ? 'user_id' : 'id'}.asc`, { headers: { authorization, apikey: anonKey } });
        if (!response.ok) throw await response.json();
        const page = await response.json() as unknown[];
        rows.push(...page);
        if (page.length < 1000) break;
      }
      dashboard[property] = table === 'ai_consents' ? rows[0] ?? null : rows;
    }
    const attachmentRows: { id: string; storage_key: string; mime: string; size_bytes: number; sha256: string }[] = [];
    for (let offset = 0;; offset += 1000) {
      const attachmentsResponse = await fetch(`${baseUrl}/rest/v1/attachments?select=id,storage_key,mime,size_bytes,sha256&order=id.asc&limit=1000&offset=${offset}`, { headers: { authorization, apikey: anonKey } });
      if (!attachmentsResponse.ok) throw await attachmentsResponse.json();
      const page = await attachmentsResponse.json() as typeof attachmentRows;
      attachmentRows.push(...page);
      if (attachmentRows.reduce((total, row) => total + Number(row.size_bytes), 0) > 50 * 1024 * 1024) throw { code: "QUOTA_EXCEEDED", message: "Ekspor melampaui batas respons 50 MB. Ekspor tidak selesai; hubungi dukungan." };
      if (page.length < 1000) break;
    }

    const files: { name: string; data: Uint8Array }[] = [
      { name: "data-v1.json", data: encode(JSON.stringify({ schema_version: "1.0.0", currency: "IDR", ...dashboard }, null, 2)) },
      { name: "personal_expenses.csv", data: encodeCSV(personalCSV(dashboard)) },
      { name: "cash_flow.csv", data: encodeCSV(cashCSV(dashboard)) },
      { name: "split_bills.csv", data: encodeCSV(splitBillsCSV(dashboard)) },
      { name: "split_members.csv", data: encodeCSV(splitMembersCSV(dashboard)) },
      { name: "split_settlements.csv", data: encodeCSV(splitSettlementsCSV(dashboard)) },
      { name: "split_resolutions.csv", data: encodeCSV(splitResolutionsCSV(dashboard)) }
    ];
    for (const attachment of attachmentRows) {
      const response = await fetch(`${baseUrl}/storage/v1/object/authenticated/attachments/${attachment.storage_key.split("/").map(encodeURIComponent).join("/")}`, { headers: { authorization, apikey: anonKey } });
      if (!response.ok) throw { code: "INTERNAL", message: "Satu lampiran gagal dimasukkan ke ekspor." };
      files.push({ name: `attachments/${attachment.id}.${extension(attachment.mime)}`, data: new Uint8Array(await response.arrayBuffer()) });
    }
    const manifest = files.map((file) => ({ name: file.name, size_bytes: String(file.data.length), checksum_crc32: crc32(file.data).toString(16).padStart(8, "0") }));
    files.push({ name: "manifest.json", data: encode(JSON.stringify({ schema_version: "1.0.0", created_at: new Date().toISOString(), file_count: files.length, total_size_bytes: String(files.reduce((sum, file) => sum + file.data.length, 0)), files: manifest }, null, 2)) });
    return new Response(zip(files), { status: 200, headers: { ...corsHeaders, "content-type": "application/zip", "content-disposition": "attachment; filename=danarapi-export.zip" } });
  } catch (cause) {
    const error = normalizeError(cause, requestId);
    return Response.json(error.body, { status: error.status, headers: corsHeaders });
  }
});

type Row = Record<string, unknown>;
function rows(source: Record<string, unknown>, key: string): Row[] { const values = source[key] as Row[] ?? []; return ['transactions', 'transfers', 'splitBills'].includes(key) ? values.filter(value => !value.deleted) : values; }
export function exportCSVs(data: Row) { return { 'personal_expenses.csv': '\ufeff' + personalCSV(data), 'cash_flow.csv': '\ufeff' + cashCSV(data), 'split_bills.csv': '\ufeff' + splitBillsCSV(data), 'split_members.csv': '\ufeff' + splitMembersCSV(data), 'split_settlements.csv': '\ufeff' + splitSettlementsCSV(data), 'split_resolutions.csv': '\ufeff' + splitResolutionsCSV(data) }; }
function personalCSV(data: Row) {
  const output: unknown[][] = [["event_id", "source_bill_id", "occurred_at", "type", "amount", "category", "merchant", "is_non_cash"]];
  const categories = new Map(rows(data, "categories").map((item) => [item.id, item.name]));
  for (const item of rows(data, "transactions")) if (item.kind === "expense") output.push([item.id, "", item.occurredAt, item.kind, item.amount, categories.get(item.categoryID) ?? "", item.merchant ?? "", "false"]);
  for (const bill of rows(data, "splitBills")) {
    const members = bill.members as Row[]; const self = members.find((member) => member.isSelf);
    output.push([bill.id, bill.id, bill.occurredAt, "split_personal_share", self?.shareAmount ?? "0", categories.get(bill.categoryID) ?? "", bill.title, "false"]);
    for (const event of bill.resolutions as Row[]) if (!event.reversed && event.kind === "receivable_writeoff") output.push([event.id, bill.id, event.occurredAt, event.kind, event.amount, categories.get(bill.categoryID) ?? "", bill.title, "true"]);
  }
  return csv(output);
}
function cashCSV(data: Row) {
  const output: unknown[][] = [["event_id", "source_bill_id", "occurred_at", "type", "amount", "account", "note"]];
  const accounts = new Map(rows(data, "accounts").map((item) => [item.id, item.name]));
  for (const item of rows(data, "transactions")) output.push([item.id, "", item.occurredAt, item.kind, item.kind === "income" ? item.amount : `-${item.amount}`, accounts.get(item.accountID) ?? "", item.note ?? ""]);
  for (const item of rows(data, "transfers")) { output.push([`${item.id}-out`, "", item.occurredAt, "transfer_out", `-${item.amount}`, accounts.get(item.fromAccountID) ?? "", item.note ?? ""]); output.push([`${item.id}-in`, "", item.occurredAt, "transfer_in", item.amount, accounts.get(item.toAccountID) ?? "", item.note ?? ""]); }
  for (const bill of rows(data, "splitBills")) {
    const payer = bill.payer as Row;
    if (payer.selfPaid) output.push([bill.id, bill.id, bill.occurredAt, "split_bill_paid", `-${bill.total}`, accounts.get((payer.selfPaid as Row).accountID) ?? "", bill.title]);
    for (const event of bill.settlements as Row[]) if (!event.reversed) output.push([event.id, bill.id, event.occurredAt, `split_settlement_${event.direction}`, event.direction === "in" ? event.amount : `-${event.amount}`, accounts.get(event.accountID) ?? "", event.note ?? ""]);
  }
  return csv(output);
}
function splitBillsCSV(data: Row) { const output: unknown[][] = [["source_bill_id", "occurred_at", "title", "total", "payer", "self_share", "status", "remaining"]]; for (const bill of rows(data, "splitBills")) { const members = bill.members as Row[]; const self = members.find((member) => member.isSelf); const remaining = obligationMembers(bill).reduce((sum, member) => sum + BigInt(String(member.obligationAmount ?? member.shareAmount)) - BigInt(String(member.settledAmount)) - BigInt(String(member.resolvedAmount)), 0n); const payer = bill.payer as Row; const payerName = payer.selfPaid ? "Saya" : members.find((member) => member.id === (payer.other as Row)?.memberID)?.displayName; output.push([bill.id, bill.occurredAt, bill.title, bill.total, payerName, self?.shareAmount ?? "0", remaining === 0n ? "settled" : obligationMembers(bill).some(member => BigInt(String(member.settledAmount)) + BigInt(String(member.resolvedAmount)) > 0n) ? "partially_settled" : "unsettled", remaining.toString()]); } return csv(output); }
function splitMembersCSV(data: Row) { const output: unknown[][] = [["source_bill_id", "member_id", "display_name", "is_self", "share_amount", "settled_amount", "resolved_amount", "remaining_amount"]]; for (const bill of rows(data, "splitBills")) { const owed = obligationMembers(bill); for (const member of bill.members as Row[]) output.push([bill.id, member.id, member.displayName, member.isSelf, member.shareAmount, member.settledAmount, member.resolvedAmount, owed.includes(member) ? (BigInt(String(member.obligationAmount ?? member.shareAmount)) - BigInt(String(member.settledAmount)) - BigInt(String(member.resolvedAmount))).toString() : "0"]); } return csv(output); }
function splitSettlementsCSV(data: Row) { const output: unknown[][] = [["event_id", "source_bill_id", "member_id", "direction", "account", "amount", "occurred_at", "reversed", "note"]]; const accounts = new Map(rows(data, "accounts").map((item) => [item.id, item.name])); for (const bill of rows(data, "splitBills")) for (const event of bill.settlements as Row[]) output.push([event.id, bill.id, event.memberID, event.direction, accounts.get(event.accountID) ?? "", event.amount, event.occurredAt, event.reversed, event.note ?? ""]); return csv(output); }
function splitResolutionsCSV(data: Row) { const output: unknown[][] = [["event_id", "source_bill_id", "member_id", "kind", "amount", "occurred_at", "reversed", "reason"]]; for (const bill of rows(data, "splitBills")) for (const event of bill.resolutions as Row[]) output.push([event.id, bill.id, event.memberID, event.kind, event.amount, event.occurredAt, event.reversed, event.reason]); return csv(output); }
function obligationMembers(bill: Row): Row[] { const values = bill.members as Row[]; const payer = bill.payer as Row; return payer.selfPaid ? values.filter((item) => !item.isSelf) : values.filter((item) => item.id === (payer.other as Row).memberID); }
function csv(values: unknown[][]) { const numeric = new Set(["amount", "total", "self_share", "remaining", "share_amount", "settled_amount", "resolved_amount", "remaining_amount"]); return values.map((row, rowIndex) => row.map((value, column) => safe(value, rowIndex > 0 && numeric.has(String(values[0][column])))).join(",")).join("\r\n") + "\r\n"; }
function safe(value: unknown, numeric = false) { let text = String(value ?? ""); if (/^[=+\-@\t\r]/.test(text) && !(numeric && /^-?\d+$/.test(text))) text = `'${text}`; return `"${text.replaceAll('"', '""')}"`; }
function encode(value: string) { return new TextEncoder().encode(value); }
function encodeCSV(value: string) { return encode(`\ufeff${value}`); }
function extension(mime: string) { return ({ "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "application/pdf": "pdf" } as Record<string, string>)[mime] ?? "bin"; }
function required(name: string) { const value = Deno.env.get(name); if (!value) throw new Error(`missing_${name}`); return value; }
function errorResponse(code: string, message: string, status: number, requestId: string, headers: Record<string, string>) { return Response.json({ code, message, request_id: requestId, details: {} }, { status, headers }); }

function zip(files: { name: string; data: Uint8Array }[]) {
  const chunks: Uint8Array[] = [], central: number[] = [];
  let localSize = 0;
  for (const file of files) {
    const name = encode(file.name), offset = localSize, checksum = crc32(file.data), local: number[] = [];
    push32(local, 0x04034b50); push16(local, 20); push16(local, 0x0800); push16(local, 0); push16(local, 0); push16(local, 0); push32(local, checksum); push32(local, file.data.length); push32(local, file.data.length); push16(local, name.length); push16(local, 0);
    chunks.push(new Uint8Array(local), name, file.data); localSize += local.length + name.length + file.data.length;
    push32(central, 0x02014b50); push16(central, 20); push16(central, 20); push16(central, 0x0800); push16(central, 0); push16(central, 0); push16(central, 0); push32(central, checksum); push32(central, file.data.length); push32(central, file.data.length); push16(central, name.length); push16(central, 0); push16(central, 0); push16(central, 0); push16(central, 0); push32(central, 0); push32(central, offset); central.push(...name);
  }
  const end: number[] = []; push32(end, 0x06054b50); push16(end, 0); push16(end, 0); push16(end, files.length); push16(end, files.length); push32(end, central.length); push32(end, localSize); push16(end, 0);
  chunks.push(new Uint8Array(central), new Uint8Array(end));
  const archive = new Uint8Array(localSize + central.length + end.length);
  let cursor = 0;
  for (const chunk of chunks) { archive.set(chunk, cursor); cursor += chunk.length; }
  return archive;
}
function push16(target: number[], value: number) { target.push(value & 255, (value >>> 8) & 255); }
function push32(target: number[], value: number) { target.push(value & 255, (value >>> 8) & 255, (value >>> 16) & 255, (value >>> 24) & 255); }
function crc32(data: Uint8Array) { let crc = 0xffffffff; for (const byte of data) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc & 1) ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1; } return (crc ^ 0xffffffff) >>> 0; }
