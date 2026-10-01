import { normalizeError } from "../_shared/errors.ts";
import { normalizeReceipt, storeReceipt } from "../_shared/receipt.ts";
import { allocationBreakdown } from "../_shared/planning.ts";
import { hasRecentOAuth } from "../_shared/oauth.ts";
import { corsFor } from "../_shared/cors.ts";

type Json = Record<string, unknown>;

Deno.serve(async (request) => {
  const corsHeaders = corsFor(request, 'x-review-item-id, x-transaction-id, x-split-bill-id, x-file-name');
  const requestId = crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return failure("VALIDATION", "Gunakan POST.", 405, requestId, corsHeaders);
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return failure("UNAUTHORIZED", "Sesi diperlukan.", 401, requestId, corsHeaders);

  try {
    const url = new URL(request.url);
    if (url.pathname.endsWith("/dashboard-full")) return Response.json(await dashboard(authorization, true), { headers: corsHeaders });
    if (url.pathname.endsWith("/dashboard")) return Response.json(await dashboard(authorization, false), { headers: corsHeaders });
    if (url.pathname.endsWith("/transactions")) {
      const body = await request.json() as { cursor?: { occurredAt?: string; id?: string } };
      return Response.json(await transactionPage(authorization, body.cursor), { headers: corsHeaders });
    }
    if (url.pathname.endsWith("/report")) {
      const body = await request.json() as { startDate?: string; endDate?: string };
      return Response.json(await report(authorization, body.startDate, body.endDate), { headers: corsHeaders });
    }
    if (url.pathname.endsWith("/attachment")) return Response.json(await uploadAttachment(request, authorization), { status: 201, headers: corsHeaders });
    const body = await request.json() as { operation?: string; payload?: Json };
    if (!body.operation || !body.payload) return failure("VALIDATION", "Operasi atau payload tidak valid.", 422, requestId, corsHeaders);
    await action(body.operation, body.payload, authorization);
    return Response.json({ ok: true, request_id: requestId }, { headers: corsHeaders });
  } catch (cause) {
    const error = normalizeError(cause, requestId);
    return Response.json(error.body, { status: error.status, headers: corsHeaders });
  }
});

async function dashboard(authorization: string, fullTransactions: boolean) {
  await rpc("api_ensure_feature_categories", {}, authorization);
  const [accounts, categories, transactions, transfers, bills, members, settlements, resolutions, reviews, attachments, merchantRules, budgets, ledger, goals, profiles] = await Promise.all([
    rest("accounts?select=*&order=created_at.asc", authorization),
    rest("categories?select=*&order=sort_order.asc", authorization),
    fullTransactions
      ? restAll("transactions?select=*&deleted_at=is.null&order=occurred_at.desc,id.desc", authorization)
      : rest("transactions?select=*&deleted_at=is.null&order=occurred_at.desc,id.desc&limit=31", authorization),
    restAll("transfers?select=*&deleted_at=is.null&order=occurred_at.desc,id.desc", authorization),
    restAll("split_bills?select=*&deleted_at=is.null&order=occurred_at.desc,id.desc", authorization),
    restAll("split_members?select=*&order=split_bill_id.asc,sort_order.asc", authorization),
    restAll("split_settlements?select=*&order=occurred_at.asc,id.asc", authorization),
    restAll("split_resolutions?select=*&order=occurred_at.asc,id.asc", authorization),
    restAll("review_items?select=*&status=eq.pending&order=created_at.desc,id.desc", authorization),
    restAll("attachments?select=review_item_id,storage_key&review_item_id=not.is.null&order=id.asc", authorization),
    rest("merchant_rules?select=*&order=priority.desc,created_at.asc", authorization),
    restAll("budgets?select=*&order=month.desc,id.asc", authorization),
    restAll("ledger_entries?select=*&reversed_at=is.null&order=id.asc", authorization),
    restAll("savings_goal_progress?select=*&order=created_at.asc,id.asc", authorization),
    rest("profiles?select=timezone&limit=1", authorization)
  ]) as Json[][];

  const cashByAccount = new Map<string, bigint>();
  let income = 0n, expense = 0n, receivables = 0n, payables = 0n;
  for (const entry of ledger) {
    const accountId = entry.account_id as string | null;
    const cash = integer(entry.cash_amount);
    if (accountId) cashByAccount.set(accountId, (cashByAccount.get(accountId) ?? 0n) + cash);
    income += integer(entry.personal_income_amount);
    expense += integer(entry.personal_expense_amount);
    receivables += integer(entry.receivable_delta);
    payables += integer(entry.payable_delta);
  }

  const accountRows = accounts.map((row) => {
    const opening = integer(row.opening_balance);
    return {
      id: row.id, name: row.name, kind: row.kind, openingBalance: opening.toString(),
      balance: (opening + (cashByAccount.get(String(row.id)) ?? 0n)).toString(), openedAt: row.opened_at,
      archived: row.archived_at !== null, version: row.version
    };
  });
  const accountBalance = accountRows.reduce((sum, row) => sum + BigInt(row.balance), 0n);
  const settlementsByBill = group(settlements, "split_bill_id");
  const resolutionsByBill = group(resolutions, "split_bill_id");
  const membersByBill = group(members, "split_bill_id");
  const attachmentByReview = new Map(attachments.map((row) => [String(row.review_item_id), String(row.storage_key).split("/").at(-1) ?? null]));

  const billRows = bills.map((bill) => {
    const billSettlements = settlementsByBill.get(String(bill.id)) ?? [];
    const billResolutions = resolutionsByBill.get(String(bill.id)) ?? [];
    const settledByMember = sums(billSettlements.filter((row) => row.reversed_at === null), "member_id", "amount");
    const resolvedByMember = sums(billResolutions.filter((row) => row.reversed_at === null), "member_id", "amount");
    return {
      id: bill.id, title: bill.title, total: String(bill.total), categoryID: bill.category_id,
      payer: bill.payer_kind === "self" ? { selfPaid: { accountID: bill.payer_account_id } } : { other: { memberID: bill.payer_member_id } },
      occurredAt: bill.occurred_at, note: bill.note, itemSplit: bill.item_split ?? null,
      members: (membersByBill.get(String(bill.id)) ?? []).map((member) => ({
        id: member.id, displayName: member.display_name, isSelf: member.is_self, shareAmount: String(member.share_amount),
        settledAmount: (settledByMember.get(String(member.id)) ?? 0n).toString(), resolvedAmount: (resolvedByMember.get(String(member.id)) ?? 0n).toString(),
        obligationAmount: bill.payer_kind === "other" && member.id === bill.payer_member_id ? String((membersByBill.get(String(bill.id)) ?? []).find((candidate) => candidate.is_self)?.share_amount ?? "0") : null,
        sortOrder: member.sort_order
      })),
      settlements: billSettlements.map((row) => ({ id: row.id, memberID: row.member_id, direction: row.direction, accountID: row.account_id, amount: String(row.amount), occurredAt: row.occurred_at, note: row.note, reversed: row.reversed_at !== null, version: row.version })),
      resolutions: billResolutions.map((row) => ({ id: row.id, memberID: row.member_id, kind: row.kind, amount: String(row.amount), occurredAt: row.occurred_at, reason: row.reason, reversed: row.reversed_at !== null, version: row.version })),
      deleted: false, version: bill.version
    };
  });

  const visibleTransactions = fullTransactions ? transactions : transactions.slice(0, 30);
  return {
    accounts: accountRows,
    categories: categories.map((row) => ({ id: row.id, name: row.name, kind: row.kind, systemKey: row.system_key, archived: row.archived_at !== null, sortOrder: row.sort_order, version: row.version })),
    transactions: visibleTransactions.map(transactionDTO),
    transfers: transfers.map((row) => ({ id: row.id, fromAccountID: row.from_account_id, toAccountID: row.to_account_id, amount: String(row.amount), occurredAt: row.occurred_at, note: row.note, pendingSync: false, deleted: false, version: row.version })),
    splitBills: billRows,
    reviewItems: reviews.map((row) => ({ id: row.id, source: row.source, status: row.status, ...(row.extracted_fields as Json), rawReference: row.raw_reference, duplicateCandidateID: row.duplicate_of ?? row.duplicate_bill_id ?? null, attachmentName: attachmentByReview.get(String(row.id)) ?? null, createdAt: row.created_at })),
    merchantRules: merchantRules.map((row) => ({ id: row.id, matchType: row.match_type, normalizedPattern: row.normalized_pattern, categoryID: row.category_id, priority: row.priority, version: row.version })),
    goals: goals.map((row) => ({ id: row.id, name: row.name, targetAmount: String(row.target_amount), savedAmount: String(row.progress_amount), openingAmount: String(row.saved_amount), targetDate: row.target_date ? `${row.target_date}T00:00:00+07:00` : null, version: row.version })),
    budgets: budgets.map((row) => ({ id: row.id, categoryID: row.category_id, month: `${String(row.month)}T00:00:00Z`, limitAmount: String(row.limit_amount), spentAmount: budgetSpent(row, ledger, String(profiles[0]?.timezone ?? "Asia/Jakarta")).toString() })),
    overview: { accountBalance: accountBalance.toString(), receivables: receivables.toString(), payables: payables.toString(), netPosition: (accountBalance + receivables - payables).toString(), personalIncome: income.toString(), personalExpense: expense.toString() },
    nextTransactionCursor: !fullTransactions && transactions.length > 30 ? { occurredAt: visibleTransactions.at(-1)?.occurred_at, id: visibleTransactions.at(-1)?.id } : null,
    syncedAt: new Date().toISOString()
  };
}

async function transactionPage(authorization: string, cursor?: { occurredAt?: string; id?: string }) {
  if (!cursor?.occurredAt || !cursor.id || !/^\d{4}-\d{2}-\d{2}T/.test(cursor.occurredAt) || !/^[0-9a-f-]{36}$/i.test(cursor.id)) {
    throw { code: "VALIDATION", message: "Cursor transaksi tidak valid." };
  }
  const filter = `or=(occurred_at.lt.${encodeURIComponent(cursor.occurredAt)},and(occurred_at.eq.${encodeURIComponent(cursor.occurredAt)},id.lt.${encodeURIComponent(cursor.id)}))`;
  const result = await rest(`transactions?select=*&deleted_at=is.null&order=occurred_at.desc,id.desc&limit=31&${filter}`, authorization) as Json[];
  const items = result.slice(0, 30);
  return {
    items: items.map(transactionDTO),
    nextCursor: result.length > 30 ? { occurredAt: items.at(-1)?.occurred_at, id: items.at(-1)?.id } : null
  };
}

async function report(authorization: string, startDate?: string, endDate?: string) {
  if (!startDate || Number.isNaN(Date.parse(startDate))) throw { code: "VALIDATION", message: "Awal periode laporan tidak valid." };
  if (endDate && (Number.isNaN(Date.parse(endDate)) || Date.parse(endDate) <= Date.parse(startDate))) throw { code: "VALIDATION", message: "Akhir periode harus setelah awal periode." };
  const endFilter = endDate ? `&occurred_at=lt.${encodeURIComponent(endDate)}` : "";
  const ledger = await restAll(`ledger_entries?select=category_id,personal_income_amount,personal_expense_amount&reversed_at=is.null&occurred_at=gte.${encodeURIComponent(startDate)}${endFilter}&order=id.asc`, authorization);
  let personalIncome = 0n, personalExpense = 0n;
  const categoryTotals = new Map<string, bigint>();
  for (const row of ledger) {
    const income = integer(row.personal_income_amount), expense = integer(row.personal_expense_amount);
    personalIncome += income;
    personalExpense += expense;
    if (expense > 0n && row.category_id) categoryTotals.set(String(row.category_id), (categoryTotals.get(String(row.category_id)) ?? 0n) + expense);
  }
  const [goalTransactions, goalNames, categoryNames, budgetRows, profiles] = await Promise.all([
    restAll(`transactions?select=goal_id,category_id,amount&goal_id=not.is.null&type=eq.expense&deleted_at=is.null&occurred_at=gte.${encodeURIComponent(startDate)}${endFilter}&order=id.asc`, authorization),
    restAll("savings_goals?select=id,name&order=id.asc", authorization),
    restAll("categories?select=id,name&order=id.asc", authorization),
    restAll("budgets?select=category_id,month&order=id.asc", authorization),
    rest("profiles?select=timezone&limit=1", authorization)
  ]) as Json[][];
  const timezone = String(profiles[0]?.timezone ?? "Asia/Jakarta");
  const monthKey = (date: string) => new Intl.DateTimeFormat("sv-SE", { timeZone: timezone }).format(new Date(date)).slice(0,7);
  const firstMonth = monthKey(startDate), lastMonth = endDate ? monthKey(new Date(Date.parse(endDate)-1).toISOString()) : "9999-12";
  const allocations = allocationBreakdown(
    Array.from(categoryTotals, ([categoryID, amount]) => ({ categoryID, amount: amount.toString() })),
    goalTransactions.map(row => ({ categoryID: String(row.category_id), goalID: String(row.goal_id), amount: String(row.amount) })),
    goalNames.map(row => ({ id: String(row.id), name: String(row.name) })),
    categoryNames.map(row => ({ id: String(row.id), name: String(row.name) })),
    new Set(budgetRows.filter(row => String(row.month).slice(0,7) >= firstMonth && String(row.month).slice(0,7) <= lastMonth).map(row => String(row.category_id)))
  );
  return {
    personalIncome: personalIncome.toString(),
    personalExpense: personalExpense.toString(),
    categories: Array.from(categoryTotals, ([categoryID, amount]) => ({ categoryID, amount: amount.toString() })),
    allocations
  };
}

async function action(operation: string, payload: Json, authorization: string) {
  switch (operation) {
    case "update_account":
      await patch("accounts", String(payload.id), Number(payload.version), { name: payload.name, kind: payload.kind, opening_balance: payload.openingBalance, opened_at: payload.openedAt }, authorization); return;
    case "archive_account":
      await patch("accounts", String(payload.id), Number(payload.expected_version), { archived_at: new Date().toISOString() }, authorization); return;
    case "update_category":
      await patch("categories", String(payload.id), Number(payload.version), { name: payload.name, sort_order: payload.sortOrder }, authorization); return;
    case "archive_category":
      await patch("categories", String(payload.id), Number(payload.expected_version), { archived_at: new Date().toISOString() }, authorization); return;
    case "add_review_item": {
      const item = payload;
      let duplicateTransaction: unknown = null, duplicateBill: unknown = null;
      if (item.duplicateCandidateID) {
        const transactions = await rest(`transactions?id=eq.${encodeURIComponent(String(item.duplicateCandidateID))}&select=id&deleted_at=is.null`, authorization) as Json[];
        if (transactions.length) duplicateTransaction = item.duplicateCandidateID;
        else {
          const bills = await rest(`split_bills?id=eq.${encodeURIComponent(String(item.duplicateCandidateID))}&select=id&deleted_at=is.null`, authorization) as Json[];
          if (bills.length) duplicateBill = item.duplicateCandidateID;
        }
      }
      await rest("review_items?on_conflict=id", authorization, { method: "POST", headers: { prefer: "resolution=ignore-duplicates,return=minimal" }, body: JSON.stringify({ id: item.id, source: item.source, status: "pending", extracted_fields: { amount: item.amount, merchant: item.merchant, date: item.date, fingerprint: item.fingerprint ?? null, receiptLines: item.receiptLines ?? null, receipt: item.receipt ? storeReceipt(normalizeReceipt(item.receipt)) : null }, raw_reference: item.rawReference ?? null, duplicate_of: duplicateTransaction, duplicate_bill_id: duplicateBill }) }); return;
    }
    case "update_review_item": {
      const rows = await rest(`review_items?id=eq.${encodeURIComponent(String(payload.id))}&status=eq.pending&select=id,extracted_fields`, authorization) as Json[];
      if (!rows.length) throw new Error("Review tidak lagi menunggu pemeriksaan.");
      await rest(`review_items?id=eq.${encodeURIComponent(String(payload.id))}&status=eq.pending`, authorization, { method: "PATCH", headers: { prefer: "return=minimal" }, body: JSON.stringify({ extracted_fields: { ...(rows[0].extracted_fields as Json), amount: payload.amount, merchant: payload.merchant, date: payload.date, receipt: payload.receipt ? storeReceipt(normalizeReceipt(payload.receipt)) : null }, raw_reference: payload.rawReference ?? null }) }); return;
    }
    case "delete_review_item": await remove("review_items", String(payload.id), undefined, authorization); return;
    case "reject_review_item": await patch("review_items", String(payload.id), undefined, { status: "rejected", rejected_at: new Date().toISOString() }, authorization); return;
    case "restore_review_item": await patch("review_items", String(payload.id), undefined, { status: "pending", rejected_at: null }, authorization); return;
    case "merge_review_item": if (payload.bill_id) await rpc("api_merge_review_item_to_bill", { p_client_mutation_id: payload.id, p_review_item_id: payload.id, p_split_bill_id: payload.bill_id }, authorization); else await rpc("api_merge_review_item", { p_client_mutation_id: payload.id, p_review_item_id: payload.id, p_transaction_id: payload.transaction_id }, authorization); return;
    case "clear_review_duplicate": await patch("review_items", String(payload.id), undefined, { duplicate_of: null, duplicate_bill_id: null }, authorization); return;
    case "complete_review_item": await patch("review_items", String(payload.id), undefined, { status: "saved" }, authorization); return;
    case "save_merchant_rule": await saveMerchantRule(payload, authorization); return;
    case "delete_merchant_rule": await remove("merchant_rules", String(payload.id), Number(payload.expected_version), authorization); return;
    case "confirm_review_item": {
      const transaction = payload.transaction as Json;
      await rpc("api_confirm_review_item", { p_client_mutation_id: payload.id, p_review_item_id: payload.id, p_type: transaction.kind, p_amount: transaction.amount, p_account_id: transaction.accountID, p_category_id: transaction.categoryID, p_occurred_at: transaction.occurredAt, p_merchant: transaction.merchant ?? null, p_note: transaction.note ?? null }, authorization); return;
    }
    case "upsert_budget":
      await rest("budgets?on_conflict=user_id,category_id,month", authorization, { method: "POST", headers: { prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ category_id: payload.category_id, month: String(payload.month).slice(0, 10).replace(/-\d\d$/, "-01"), limit_amount: payload.limit_amount }) }); return;
    case "request_account_deletion": await deleteAccount(String(payload.password ?? ""), authorization, payload.expected_user_id ? String(payload.expected_user_id) : undefined); return;
    default: throw { code: "VALIDATION", message: "Operasi data tidak didukung." };
  }
}

async function saveMerchantRule(payload: Json, authorization: string) {
  const pattern = normalizeMerchant(String(payload.normalizedPattern ?? ""));
  const matchType = String(payload.matchType ?? "");
  const categoryId = String(payload.categoryID ?? "");
  const priority = Number(payload.priority ?? 0);
  const version = Number(payload.version ?? 0);
  if (!pattern || pattern.length > 160 || !["exact", "contains", "prefix"].includes(matchType) || !Number.isInteger(priority) || priority < 0 || priority > 999) {
    throw { code: "VALIDATION", message: "Aturan merchant tidak valid." };
  }
  const category = await rest(`categories?id=eq.${encodeURIComponent(categoryId)}&kind=eq.expense&archived_at=is.null&select=id`, authorization) as Json[];
  if (category.length !== 1) throw { code: "VALIDATION", message: "Kategori pengeluaran tidak tersedia." };
  const values = { match_type: matchType, normalized_pattern: pattern, category_id: categoryId, priority };
  if (version > 0) await patch("merchant_rules", String(payload.id), version, values, authorization);
  else await rest("merchant_rules", authorization, { method: "POST", headers: { prefer: "return=minimal" }, body: JSON.stringify({ id: payload.id, ...values }) });
}

async function patch(table: string, id: string, version: number | undefined, values: Json, authorization: string) {
  const versionFilter = version ? `&version=eq.${version}` : "";
  const response = await rest(`${table}?id=eq.${encodeURIComponent(id)}${versionFilter}`, authorization, { method: "PATCH", headers: { prefer: "return=representation" }, body: JSON.stringify(values) }) as Json[];
  if (response.length === 0) throw { code: "CONFLICT_VERSION", message: "Data telah berubah. Muat ulang sebelum mencoba lagi." };
}

async function remove(table: string, id: string, version: number | undefined, authorization: string) {
  const versionFilter = version ? `&version=eq.${version}` : "";
  const response = await rest(`${table}?id=eq.${encodeURIComponent(id)}${versionFilter}`, authorization, { method: "DELETE", headers: { prefer: "return=representation" } }) as Json[];
  if (response.length === 0) throw { code: "CONFLICT_VERSION", message: "Data telah berubah. Muat ulang sebelum mencoba lagi." };
}

async function uploadAttachment(request: Request, authorization: string) {
  const targets = [
    { id: request.headers.get("x-review-item-id"), table: "review_items", column: "review_item_id", filter: "status=eq.pending" },
    { id: request.headers.get("x-transaction-id"), table: "transactions", column: "transaction_id", filter: "deleted_at=is.null" },
    { id: request.headers.get("x-split-bill-id"), table: "split_bills", column: "split_bill_id", filter: "deleted_at=is.null" }
  ].filter(target => target.id);
  if (targets.length !== 1 || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(targets[0].id!)) throw { code: "VALIDATION", message: "Target lampiran tidak valid." };
  const target = targets[0];
  const data = new Uint8Array(await request.arrayBuffer());
  if (data.length < 1 || data.length > 5 * 1024 * 1024) throw { code: "VALIDATION", message: "Lampiran harus berukuran 1 byte sampai 5 MB." };
  const mime = detectMime(data);
  if (!mime || request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== mime) throw { code: "VALIDATION", message: "Jenis berkas tidak sesuai isi lampiran." };

  const ownerRows = await rest(`${target.table}?id=eq.${encodeURIComponent(target.id!)}&${target.filter}&select=id`, authorization) as Json[];
  if (ownerRows.length !== 1) throw { code: "NOT_FOUND", message: "Catatan tujuan lampiran tidak ditemukan." };
  const user = await currentUser(authorization);
  const attachmentId = crypto.randomUUID();
  const storageKey = `${user.id}/${attachmentId}.${extensionForMime(mime)}`;
  const baseUrl = required("SUPABASE_URL"), anonKey = required("SUPABASE_ANON_KEY");
  const objectURL = `${baseUrl}/storage/v1/object/attachments/${storageKey.split("/").map(encodeURIComponent).join("/")}`;
  const uploaded = await fetch(objectURL, { method: "POST", headers: { authorization, apikey: anonKey, "content-type": mime, "x-upsert": "false" }, body: data });
  if (!uploaded.ok) throw await uploaded.json();
  try {
    const sha256 = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", data))).map((value) => value.toString(16).padStart(2, "0")).join("");
    await rest("attachments", authorization, { method: "POST", headers: { prefer: "return=minimal" }, body: JSON.stringify({ id: attachmentId, [target.column]: target.id, storage_key: storageKey, mime, size_bytes: data.length, sha256 }) });
    return { id: attachmentId, mime, sizeBytes: String(data.length), sha256 };
  } catch (cause) {
    await fetch(objectURL, { method: "DELETE", headers: { authorization, apikey: anonKey } });
    throw cause;
  }
}

async function currentUser(authorization: string) {
  const response = await fetch(`${required("SUPABASE_URL")}/auth/v1/user`, { headers: { authorization, apikey: required("SUPABASE_ANON_KEY") } });
  if (!response.ok) throw { code: "UNAUTHORIZED", message: "Sesi tidak valid." };
  return await response.json() as { id: string };
}

function detectMime(data: Uint8Array) {
  if (data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff) return "image/jpeg";
  if ([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => data[index] === value)) return "image/png";
  if ([0x25, 0x50, 0x44, 0x46, 0x2d].every((value, index) => data[index] === value)) return "application/pdf";
  const brand = new TextDecoder().decode(data.slice(4, 12));
  if (brand.startsWith("ftyp") && ["heic", "heix", "hevc", "hevx", "mif1"].includes(brand.slice(4, 8))) return "image/heic";
  return null;
}

function extensionForMime(mime: string) { return ({ "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "application/pdf": "pdf" } as Record<string, string>)[mime]; }
function normalizeMerchant(value: string) { return value.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("id-ID").replace(/[^\p{L}\p{N}]+/gu, " ").trim(); }

async function deleteAccount(password: string, authorization: string, expectedUserID?: string) {
  const baseUrl = required("SUPABASE_URL"), anonKey = required("SUPABASE_ANON_KEY"), serviceKey = required("SUPABASE_SERVICE_ROLE_KEY");
  const userResponse = await fetch(`${baseUrl}/auth/v1/user`, { headers: { authorization, apikey: anonKey } });
  if (!userResponse.ok) throw { code: "UNAUTHORIZED", message: "Sesi tidak valid." };
  const user = await userResponse.json() as { id: string; email?: string };
  if (expectedUserID && user.id !== expectedUserID) throw { code: "UNAUTHORIZED", message: "Masuk kembali dengan akun yang sama." };
  if (password.length >= 8) {
    if (!user.email) throw { code: "UNAUTHORIZED", message: "Autentikasi ulang diperlukan." };
    const verify = await fetch(`${baseUrl}/auth/v1/token?grant_type=password`, { method: "POST", headers: { apikey: anonKey, "content-type": "application/json" }, body: JSON.stringify({ email: user.email, password }) });
    if (!verify.ok) throw { code: "UNAUTHORIZED", message: "Autentikasi ulang gagal." };
    const verifiedUser = await verify.json() as { user?: { id?: string } };
    if (verifiedUser.user?.id !== user.id) throw { code: "UNAUTHORIZED", message: "Identitas akun tidak cocok." };
  } else {
    let recent = false;
    try {
      const encoded = authorization.replace(/^Bearer\s+/i, "").split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      recent = hasRecentOAuth(JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length/4)*4, "="))), user.id);
    } catch { recent = false; }
    if (!recent) throw { code: "UNAUTHORIZED", message: "Konfirmasi Google atau Apple diperlukan dalam lima menit terakhir." };
  }
  const adminHeaders = { authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "content-type": "application/json" };
  const objectKeys: string[] = [];
  async function collect(prefix: string) {
    for (let offset = 0;; offset += 1000) {
      const listed = await fetch(`${baseUrl}/storage/v1/object/list/attachments`, { method: "POST", headers: adminHeaders, body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }) });
      if (!listed.ok) throw { code: "INTERNAL", message: "Daftar lampiran gagal diperiksa. Penghapusan belum selesai; coba lagi." };
      const objects = await listed.json() as { name: string; id: string | null }[];
      for (const object of objects) {
        if (!object.name || object.name.includes("/") || object.name === "..") throw { code: "INTERNAL", message: "Path lampiran tidak valid." };
        if (object.id) objectKeys.push(`${prefix.replace(/\/$/, "")}/${object.name}`);
        else await collect(`${prefix.replace(/\/$/, "")}/${object.name}`);
      }
      if (objectKeys.length > 10000) throw { code: "QUOTA_EXCEEDED", message: "Penghapusan berkas memerlukan bantuan dukungan. Akun belum dihapus." };
      if (objects.length < 1000) return;
    }
  }
  await collect(user.id);
  for (let offset = 0; offset < objectKeys.length; offset += 100) {
    const removed = await fetch(`${baseUrl}/storage/v1/object/attachments`, { method: "DELETE", headers: adminHeaders, body: JSON.stringify({ prefixes: objectKeys.slice(offset, offset + 100) }) });
    if (!removed.ok) throw { code: "INTERNAL", message: "Satu lampiran gagal dihapus. Penghapusan belum selesai; coba lagi." };
  }
  const remainingObjects = await fetch(`${baseUrl}/storage/v1/object/list/attachments`, { method: "POST", headers: adminHeaders, body: JSON.stringify({ prefix: user.id, limit: 1 }) });
  if (!remainingObjects.ok || (await remainingObjects.json() as unknown[]).length !== 0) throw { code: "INTERNAL", message: "Pembersihan lampiran belum terverifikasi. Akun belum dihapus." };
  const deleted = await fetch(`${baseUrl}/auth/v1/admin/users/${user.id}`, { method: "DELETE", headers: { authorization: `Bearer ${serviceKey}`, apikey: serviceKey } });
  if (!deleted.ok) throw { code: "INTERNAL", message: "Penghapusan akun sedang bermasalah. Coba lagi." };
  const verified = await fetch(`${baseUrl}/auth/v1/admin/users/${user.id}`, { headers: adminHeaders });
  if (verified.status !== 404) throw { code: "INTERNAL", message: "Status penghapusan identitas belum terverifikasi." };
}

async function rest(path: string, authorization: string, init: RequestInit = {}) {
  const response = await fetch(`${required("SUPABASE_URL")}/rest/v1/${path}`, { ...init, headers: { authorization, apikey: required("SUPABASE_ANON_KEY"), "content-type": "application/json", ...(init.headers ?? {}) } });
  const text = await response.text();
  const value = text ? JSON.parse(text) : [];
  if (!response.ok) throw value;
  return value;
}

async function restAll(path: string, authorization: string) {
  const rows: Json[] = [];
  for (let offset = 0;; offset += 1000) {
    const page = await rest(`${path}&limit=1000&offset=${offset}`, authorization) as Json[];
    rows.push(...page);
    if (page.length < 1000) return rows;
  }
}

async function rpc(name: string, payload: Json, authorization: string) { return await rest(`rpc/${name}`, authorization, { method: "POST", body: JSON.stringify(payload) }); }
function integer(value: unknown): bigint { return BigInt(String(value ?? "0")); }
function group(rows: Json[], key: string) { const result = new Map<string, Json[]>(); for (const row of rows) result.set(String(row[key]), [...(result.get(String(row[key])) ?? []), row]); return result; }
function sums(rows: Json[], key: string, value: string) { const result = new Map<string, bigint>(); for (const row of rows) result.set(String(row[key]), (result.get(String(row[key])) ?? 0n) + integer(row[value])); return result; }
function budgetSpent(budget: Json, ledger: Json[], timezone: string) { const month = String(budget.month).slice(0, 7); let formatter: Intl.DateTimeFormat; try { formatter = new Intl.DateTimeFormat("sv-SE", { timeZone: timezone, year: "numeric", month: "2-digit" }); } catch { formatter = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Jakarta", year: "numeric", month: "2-digit" }); } return ledger.filter((row) => row.category_id === budget.category_id && formatter.format(new Date(String(row.occurred_at))) === month).reduce((sum, row) => sum + integer(row.personal_expense_amount), 0n); }
function transactionDTO(row: Json) { return { id: row.id, kind: row.type, amount: String(row.amount), accountID: row.account_id, categoryID: row.category_id, goalID: row.goal_id ?? null, occurredAt: row.occurred_at, merchant: row.merchant, note: row.note, source: row.source, pendingSync: false, deleted: false, version: row.version }; }
function required(name: string) { const value = Deno.env.get(name); if (!value) throw new Error(`missing_${name}`); return value; }
function failure(code: string, message: string, status: number, requestId: string, headers: Record<string, string>) { return Response.json({ code, message, request_id: requestId, details: {} }, { status, headers }); }
