# -*- coding: utf-8 -*-
"""Extract two food photos per recipe, drop the recurring logo, name <slug>-1/<slug>-2.
Outputs media/ + image_manifest.csv. Recipe->page mapping from recipes_resolved.json."""
import json, os, csv, hashlib
import fitz
from collections import Counter

RECIPE_DIR = "/sessions/ecstatic-vigilant-mccarthy/mnt/Grams of Health - Recipe Builder/recipes"
SRC = {
 'big': os.path.join(RECIPE_DIR, "RECIPES (photo format) (44).pdf"),
 'female': os.path.join(RECIPE_DIR, "#2 PB Strength Challenge Female Nutrition Book.pdf"),
 'male': os.path.join(RECIPE_DIR, "#2 PB Strength Challenge Male Nutrition Book .pdf"),
}
OUT = 'media'
os.makedirs(OUT, exist_ok=True)

docs = {k: fitz.open(v) for k, v in SRC.items()}
R = json.load(open('recipes_resolved.json'))

# pages we care about, by source
pages_by_src = {}
for rec in R:
    pages_by_src.setdefault(rec['source'], set()).add(rec['page'])

# ---- detect recurring logo image hashes (appear on many recipe pages) ----
hash_pagecount = Counter()
img_cache = {}   # (src,xref) -> dict(image bytes, ext, w, h, hash)
def page_images(src, pno):
    doc = docs[src]; pg = doc[pno-1]
    out = []
    for x in pg.get_images(full=True):
        xref = x[0]
        try:
            d = doc.extract_image(xref)
        except Exception:
            continue
        h = hashlib.md5(d['image']).hexdigest()
        out.append({'xref':xref,'w':d['width'],'h':d['height'],'ext':d['ext'],'bytes':d['image'],'hash':h})
    return out

for src, pages in pages_by_src.items():
    for pno in pages:
        seen = set()
        for im in page_images(src, pno):
            if im['hash'] in seen: continue
            seen.add(im['hash'])
            hash_pagecount[im['hash']] += 1

LOGO_HASHES = {h for h, c in hash_pagecount.items() if c >= 15}   # recurs on >=15 pages
print('logo/recurring image hashes detected:', len(LOGO_HASHES))

# ---- per recipe: keep two largest non-logo images ----
manifest = []
for rec in R:
    src, pno, slug = rec['source'], rec['page'], rec['slug']
    imgs = [im for im in page_images(src, pno)
            if im['hash'] not in LOGO_HASHES and im['w']*im['h'] >= 150*150]
    # dedupe identical images within page; sort by area desc
    uniq = {}
    for im in imgs:
        if im['hash'] not in uniq: uniq[im['hash']] = im
    imgs = sorted(uniq.values(), key=lambda x: -(x['w']*x['h']))[:2]
    names = ['', '']
    dims = []
    for idx, im in enumerate(imgs):
        ext = im['ext'] if im['ext'] in ('jpeg','jpg','png','webp') else 'png'
        ext = 'jpg' if ext == 'jpeg' else ext
        fn = f"{slug}-{idx+1}.{ext}"
        with open(os.path.join(OUT, fn), 'wb') as fh:
            fh.write(im['bytes'])
        names[idx] = fn
        dims.append(f"{im['w']}x{im['h']}")
    manifest.append({'recipe_title':rec['title'],'slug':slug,'image_1':names[0],'image_2':names[1],
                     'source_pdf':os.path.basename(SRC[src]),'page':pno,'dimensions':';'.join(dims)})

with open('image_manifest.csv','w',newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=['recipe_title','slug','image_1','image_2','source_pdf','page','dimensions'])
    w.writeheader()
    for m in manifest: w.writerow(m)

n1 = sum(1 for m in manifest if m['image_1'])
n2 = sum(1 for m in manifest if m['image_2'])
print(f'recipes: {len(manifest)} | with image_1: {n1} | with image_2: {n2}')
print('media files:', len(os.listdir(OUT)))
