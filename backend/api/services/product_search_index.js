function normalizeSearchText(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\u064B-\u065F\u0670\u0640]/g, '')
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/ؤ/g, 'و')
    .replace(/ئ/g, 'ي')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/ی/g, 'ي')
    .replace(/ک/g, 'ك')
    .replace(/[٠-٩]/g, digit => String(digit.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, digit => String(digit.charCodeAt(0) - 0x06f0))
    .replace(/[^\u0600-\u06FFa-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function toStringList(value) {
  if (Array.isArray(value)) {
    return value.map(item => String(item ?? '').trim()).filter(Boolean);
  }
  if (typeof value === 'string') {
    return value.split(',').map(item => item.trim()).filter(Boolean);
  }
  if (value && typeof value === 'object') {
    return Object.values(value)
      .map(item => String(item ?? '').trim())
      .filter(Boolean);
  }
  return [];
}

function toAvailable(value) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  if (value == null) return true;
  const normalized = String(value ?? '').trim().toLowerCase();
  if (['false', '0', 'no', 'inactive', 'unavailable', 'hidden'].includes(normalized)) {
    return false;
  }
  return true;
}

function toNumberOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function buildSearchIndexRecord(productId, product) {
  const name = String(product.name ?? '').trim();
  const brand = String(product.brand ?? product.brand_name ?? '').trim();
  const category = String(product.category ?? '').trim();
  const mainCategory = String(
    product.main_category ?? product.mainCategory ?? '',
  ).trim();
  const subcategory = String(product.subcategory ?? '').trim();
  const description = String(product.description ?? '').trim();
  const keywords = toStringList(
    product.alternative_names ??
      product.alternativeNames ??
      product.search_names ??
      product.searchNames,
  );
  const merchantId = String(
    product.merchant_id ?? product.merchantId ?? '',
  ).trim();
  const merchantName = String(
    product.merchant_name ?? product.merchantName ?? '',
  ).trim();
  const document = [
    name,
    brand,
    ...keywords,
    category,
    mainCategory,
    subcategory,
    merchantName,
    description,
  ].join(' ');
  const imageUrls = toStringList(
    product.image_urls ?? product.imageUrls ?? product.images,
  );
  const imageUrl = String(
    product.image_url ??
      product.imageUrl ??
      product.image ??
      product.cover_image_url ??
      imageUrls[0] ??
      '',
  ).trim();
  const available = toAvailable(
    product.available ?? product.is_available ?? product.status,
  );

  const payload = {
    id: productId,
    name,
    alternative_names: keywords,
    brand,
    price: toNumberOrNull(product.price) ?? 0,
    category,
    main_category_id:
      product.main_category_id ?? product.mainCategoryId ?? null,
    main_category: mainCategory || null,
    subcategory_id: product.subcategory_id ?? product.subcategoryId ?? null,
    subcategory: subcategory || null,
    description,
    image_url: imageUrl,
    image_urls: imageUrls.length > 0 ? imageUrls : imageUrl ? [imageUrl] : [],
    video_url: String(product.video_url ?? product.videoUrl ?? ''),
    available,
    merchant_id: merchantId,
    merchant_name: merchantName,
    colors: toStringList(product.colors ?? product.available_colors),
    color_image_urls:
      product.color_image_urls ?? product.colorImageUrls ?? {},
    sizes: toStringList(product.sizes ?? product.available_sizes),
    has_sizes: product.has_sizes ?? product.hasSizes ?? true,
    currency_code: product.currency_code ?? product.currencyCode ?? 'SAR',
    currency_symbol: product.currency_symbol ?? product.currencySymbol ?? 'ر.س',
    currency_name:
      product.currency_name ?? product.currencyName ?? 'ريال سعودي',
    vat_rate: toNumberOrNull(product.vat_rate ?? product.vatRate) ?? 0,
    vat_rate_override: toNumberOrNull(product.vat_rate_override),
    vat_exempt: product.vat_exempt === true || product.vat_exempt === 'true',
    commission_mode_override:
      product.commission_mode_override ?? product.commissionModeOverride ?? null,
    commission_value_override: toNumberOrNull(
      product.commission_value_override ?? product.commissionValueOverride,
    ),
    discount_mode: product.discount_mode ?? product.discountMode ?? null,
    discount_value: toNumberOrNull(
      product.discount_value ?? product.discountValue,
    ),
    submitted_at:
      product.submitted_at ?? product.submittedAt ?? product.created_at ?? null,
  };

  return {
    productId,
    merchantId,
    name,
    brand,
    category,
    mainCategory,
    subcategory,
    description,
    keywords,
    normalizedName: normalizeSearchText(name),
    normalizedBrand: normalizeSearchText(brand),
    normalizedCategory: normalizeSearchText(category),
    normalizedMainCategory: normalizeSearchText(mainCategory),
    normalizedSubcategory: normalizeSearchText(subcategory),
    normalizedDescription: normalizeSearchText(description),
    normalizedKeywords: normalizeSearchText(keywords.join(' ')),
    normalizedDocument: normalizeSearchText(document),
    price: toNumberOrNull(product.price),
    available,
    createdAt: product.submitted_at ?? product.submittedAt ?? product.created_at,
    payload,
  };
}

module.exports = {
  buildSearchIndexRecord,
  normalizeSearchText,
};
