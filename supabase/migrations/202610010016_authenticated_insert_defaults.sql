alter table public.review_items alter column user_id set default auth.uid();
alter table public.attachments alter column user_id set default auth.uid();
alter table public.merchant_rules alter column user_id set default auth.uid();
alter table public.budgets alter column user_id set default auth.uid();
