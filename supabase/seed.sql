-- Synthetic local-development data only. Never replace this with real financial records.
do $$
declare
  demo_user constant uuid := '10000000-0000-4000-8000-000000000001';
  cash_account constant uuid := '20000000-0000-4000-8000-000000000001';
  bank_account constant uuid := '20000000-0000-4000-8000-000000000002';
  food_category uuid;
  income_category uuid;
begin
  insert into auth.users(instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (
    '00000000-0000-0000-0000-000000000000', demo_user, 'authenticated', 'authenticated',
    'demo-local@danarapi.invalid', extensions.crypt('demo-local-only', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{"synthetic":true}'::jsonb, now(), now()
  ) on conflict (id) do nothing;

  select id into food_category from public.categories where user_id = demo_user and system_key = 'other_expense';
  select id into income_category from public.categories where user_id = demo_user and system_key = 'other_income';

  -- Replace the onboarding account with deterministic fixture IDs.
  delete from public.accounts
  where user_id = demo_user and lower(btrim(name)) = 'tunai' and id <> cash_account;

  insert into public.accounts(id, user_id, name, kind, opening_balance, opened_at)
  values
    (cash_account, demo_user, 'Tunai', 'cash', 500000, '2026-07-01T00:00:00Z'),
    (bank_account, demo_user, 'Bank Demo', 'bank', 2500000, '2026-07-01T00:00:00Z')
  on conflict (id) do nothing;

  insert into public.transactions(id, user_id, type, amount, account_id, category_id, occurred_at, merchant, source)
  select
    ('30000000-0000-4000-8000-' || lpad(gs::text, 12, '0'))::uuid,
    demo_user,
    case when gs % 47 = 0 then 'income' else 'expense' end,
    case when gs % 47 = 0 then 4500000 else 8000 + ((gs * 7919) % 142000) end,
    case when gs % 4 = 0 then cash_account else bank_account end,
    case when gs % 47 = 0 then income_category else food_category end,
    '2026-07-01T00:00:00Z'::timestamptz + ((gs - 1) % 92) * interval '1 day' + (gs % 10) * interval '1 hour',
    case when gs % 47 = 0 then 'Pemberi kerja sintetis' else 'Merchant sintetis ' || ((gs % 6) + 1) end,
    'demo'
  from generate_series(1, 200) gs
  on conflict (id) do nothing;

  insert into public.ledger_entries(user_id, account_id, category_id, source_kind, source_id, leg, occurred_at, cash_amount, personal_income_amount, personal_expense_amount)
  select
    t.user_id, t.account_id, t.category_id, 'transaction', t.id, 'cash', t.occurred_at,
    case when t.type = 'income' then t.amount else -t.amount end,
    case when t.type = 'income' then t.amount else 0 end,
    case when t.type = 'expense' then t.amount else 0 end
  from public.transactions t
  where t.user_id = demo_user
  on conflict (user_id, source_kind, source_id, leg) do nothing;
end;
$$;
