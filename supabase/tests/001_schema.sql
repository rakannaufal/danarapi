begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

select has_table('public', 'accounts', 'accounts exists');
select has_table('public', 'ledger_entries', 'ledger_entries exists');
select has_table('public', 'mutation_receipts', 'mutation receipts exist');
select has_view('public', 'account_balances', 'account balance projection exists');
select has_view('public', 'split_obligations', 'split obligation projection exists');
select has_function('public', 'api_create_transaction', array['uuid','text','text','uuid','uuid','timestamptz','text','text','text','uuid'], 'transaction RPC with optional goal exists');
select has_function('public', 'api_create_split_bill', array['uuid','text','text','text','uuid','uuid','uuid','timestamptz','jsonb','text'], 'split bill RPC exists');
select has_function('public', 'api_calculate_split', array['text','text','jsonb'], 'server split calculator exists');
select has_function('public', 'api_record_split_settlement', array['uuid','uuid','uuid','uuid','text','timestamptz','text'], 'settlement RPC exists');
select has_function('public', 'api_record_split_resolution', array['uuid','uuid','uuid','text','timestamptz','text'], 'resolution RPC exists');
select col_type_is('public', 'transactions', 'amount', 'idr_positive', 'transaction amount uses IDR domain');
select col_type_is('public', 'accounts', 'opening_balance', 'bigint', 'opening balance uses bigint');
select ok((select relrowsecurity from pg_class where oid = 'public.accounts'::regclass), 'accounts RLS enabled');
select ok((select not public from storage.buckets where id = 'attachments'), 'attachment bucket is private');

select * from finish();
rollback;
