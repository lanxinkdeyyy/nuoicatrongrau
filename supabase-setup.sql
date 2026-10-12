-- Game "Nuôi Cá Trồng Rau"
-- Chạy trong Supabase: Dashboard → SQL Editor → New query → dán toàn bộ → Run
-- Chạy lại nhiều lần cũng không sao. Chỉ tạo/sửa bảng ncr_docs, không đụng dữ liệu web học tiếng Trung.

create table if not exists public.ncr_docs (
  path text primary key,
  col text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create index if not exists ncr_docs_col_idx on public.ncr_docs (col);

-- Chỉ người đã đăng nhập (bằng Gmail) mới đọc và ghi được dữ liệu game
alter table public.ncr_docs enable row level security;
drop policy if exists "ncr_read" on public.ncr_docs;
drop policy if exists "ncr_insert" on public.ncr_docs;
drop policy if exists "ncr_update" on public.ncr_docs;
drop policy if exists "ncr_delete" on public.ncr_docs;
create policy "ncr_read"   on public.ncr_docs for select to authenticated using (true);
create policy "ncr_insert" on public.ncr_docs for insert to authenticated with check (true);
create policy "ncr_update" on public.ncr_docs for update to authenticated using (true) with check (true);
create policy "ncr_delete" on public.ncr_docs for delete to authenticated using (true);

-- Gộp dữ liệu ngay trên máy chủ để hai người chơi cùng lúc không ghi đè lên nhau
create or replace function public.ncr_jsonb_merge(a jsonb, b jsonb)
returns jsonb language plpgsql immutable as $$
declare k text; r jsonb;
begin
  if a is null or b is null or jsonb_typeof(a) <> 'object' or jsonb_typeof(b) <> 'object' then
    return b;
  end if;
  r := a;
  for k in select jsonb_object_keys(b) loop
    r := jsonb_set(r, array[k], public.ncr_jsonb_merge(r -> k, b -> k), true);
  end loop;
  return r;
end $$;

create or replace function public.ncr_update(p text, patch jsonb)
returns boolean language plpgsql security invoker as $$
begin
  update public.ncr_docs set data = public.ncr_jsonb_merge(data, patch), updated_at = now() where path = p;
  return found;
end $$;
revoke execute on function public.ncr_update(text, jsonb) from public, anon;
grant execute on function public.ncr_update(text, jsonb) to authenticated;
grant execute on function public.ncr_jsonb_merge(jsonb, jsonb) to authenticated;

-- Bật cập nhật trực tiếp (realtime) để hai người thấy thay đổi của nhau ngay
do $$ begin
  alter publication supabase_realtime add table public.ncr_docs;
exception when duplicate_object then null; end $$;
