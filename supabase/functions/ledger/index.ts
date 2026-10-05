import { normalizeError } from "../_shared/errors.ts";
import { corsFor } from "../_shared/cors.ts";

const RPC_BY_OPERATION: Record<string, string> = {
  edit_financial_account: "api_edit_financial_account",
  delete_financial_record: "api_delete_financial_record",
  calculate_item_split: "api_calculate_item_split",
  save_item_split_bill: "api_save_item_split_bill",
  save_goal: "api_save_goal",
  delete_goal: "api_delete_goal",
  calculate_split: "api_calculate_split",
  create_account: "api_create_account",
  create_category: "api_create_category",
  create_transaction: "api_create_transaction",
  update_transaction: "api_update_transaction",
  delete_transaction: "api_delete_transaction",
  restore_transaction: "api_restore_transaction",
  create_transfer: "api_create_transfer",
  update_transfer: "api_update_transfer",
  delete_transfer: "api_delete_transfer",
  restore_transfer: "api_restore_transfer",
  create_split_bill: "api_create_split_bill",
  create_split_bill_from_review: "api_create_split_bill_from_review",
  convert_transaction_to_split_bill: "api_convert_transaction_to_split_bill",
  update_split_bill: "api_update_split_bill",
  record_split_settlement: "api_record_split_settlement",
  reverse_split_settlement: "api_reverse_split_settlement",
  record_split_resolution: "api_record_split_resolution",
  reverse_split_resolution: "api_reverse_split_resolution",
  delete_split_bill: "api_delete_split_bill",
  restore_split_bill: "api_restore_split_bill"
};

Deno.serve(async (request) => {
  const corsHeaders = corsFor(request);
  const requestId = crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method !== "POST") return Response.json({ code: "VALIDATION", message: "Gunakan POST.", request_id: requestId, details: {} }, { status: 405, headers: corsHeaders });

  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ code: "UNAUTHORIZED", message: "Sesi diperlukan.", request_id: requestId, details: {} }, { status: 401, headers: corsHeaders });
  }

  try {
    const body = await request.json() as { operation?: string; payload?: Record<string, unknown> };
    const rpc = body.operation ? RPC_BY_OPERATION[body.operation] : undefined;
    if (!rpc || !body.payload || typeof body.payload !== "object") {
      return Response.json({ code: "VALIDATION", message: "Operasi atau payload tidak valid.", request_id: requestId, details: {} }, { status: 422, headers: corsHeaders });
    }
    const moneyFields = body.operation === "save_goal" ? ["p_target", "p_saved"] : body.operation === "save_item_split_bill" ? ["p_total"] : [];
    if (moneyFields.some((field) => typeof body.payload?.[field] !== "string")) {
      return Response.json({ code: "VALIDATION", message: "Nominal JSON harus string Rupiah.", request_id: requestId, details: {} }, { status: 422, headers: corsHeaders });
    }

    const baseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!baseUrl || !anonKey) throw new Error("server_configuration");
    const upstream = await fetch(`${baseUrl}/rest/v1/rpc/${rpc}`, {
      method: "POST",
      headers: {
        authorization,
        apikey: anonKey,
        "content-type": "application/json",
        "x-request-id": requestId
      },
      body: JSON.stringify(body.payload)
    });
    const result = await upstream.json();
    if (!upstream.ok) {
      const error = normalizeError(result, requestId);
      return Response.json(error.body, { status: error.status, headers: corsHeaders });
    }
    return Response.json(result, { status: 200, headers: corsHeaders });
  } catch (cause) {
    const error = normalizeError(cause, requestId);
    return Response.json(error.body, { status: error.status, headers: corsHeaders });
  }
});
