create extension if not exists pg_trgm;

create table if not exists product_search_documents (
  product_id text primary key,
  merchant_id text not null default '',
  name text not null default '',
  brand text not null default '',
  category text not null default '',
  main_category text not null default '',
  subcategory text not null default '',
  description text not null default '',
  keywords text[] not null default '{}',
  normalized_name text not null default '',
  normalized_brand text not null default '',
  normalized_category text not null default '',
  normalized_main_category text not null default '',
  normalized_subcategory text not null default '',
  normalized_description text not null default '',
  normalized_keywords text not null default '',
  normalized_document text not null default '',
  price numeric(12,2),
  available boolean not null default true,
  created_at timestamptz,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create index if not exists idx_product_search_name_trgm
  on product_search_documents using gin (normalized_name gin_trgm_ops);
create index if not exists idx_product_search_brand_trgm
  on product_search_documents using gin (normalized_brand gin_trgm_ops);
create index if not exists idx_product_search_keywords_trgm
  on product_search_documents using gin (normalized_keywords gin_trgm_ops);
create index if not exists idx_product_search_description_trgm
  on product_search_documents using gin (normalized_description gin_trgm_ops);
create index if not exists idx_product_search_document_trgm
  on product_search_documents using gin (normalized_document gin_trgm_ops);
create index if not exists idx_product_search_category
  on product_search_documents(
    normalized_category,
    normalized_main_category,
    normalized_subcategory
  );
create index if not exists idx_product_search_brand
  on product_search_documents(normalized_brand);
create index if not exists idx_product_search_availability_price
  on product_search_documents(available, price);
