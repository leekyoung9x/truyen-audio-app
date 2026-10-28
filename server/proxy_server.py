"""Proxy cung origin cho Truyen Audio Web (pass 9 — TOC phan trang).

Browser chi goi cung origin (https://comic.cutes1tg.online/api/*);
Caddy strip prefix /api roi forward ve day. Proxy goi server TTS
qua HTTP noi bo nen browser khong bao gio thay mixed-content / CORS.

Routes (chap nhan ca co va khong prefix /api de robust khi wiring):
  GET  /voices/vieneu  -> GET  {VIENEU}/voices
  GET  /voices/kokoro  -> GET  {KOKORO}/voices
  POST /parse          -> url chuong (/chuong-, /chapter): forward {VIENEU}/parse
                          url trang truyen: tu boc muc luc 1 PAGE (v9, body {page})
                          body {text}: forward {VIENEU}/parse nhu cu
  GET  /toc?url=...[&page=N] -> boc 1 page muc luc trang truyen (v9)
  POST /tts            -> thu KOKORO truoc, loi thi VIENEU (v8: Kokoro primary)
                          v11: text > 4500 chu tu cat chunk (header X-Chunks)
  POST /tts_chunk        -> v11 progressive: tong hop RIENG 1 chunk
                          (body {text, chunk: idx}; header X-Chunks/X-Chunk-Idx)
  GET  /health         -> {"ok": true} (cho systemd/cron check)

v7 — ly do: server Vieneu 8001 `/parse {url-trang-truyen}` chi boc TEXT trang
gioi thieu (tra 1-2 "Phan" rac), KHONG boc muc luc HTML. Trong khi muc luc
nam ngay trong HTML (`div#chapter-list`, link `/.../chuong-XX-hash`) + phan
trang AJAX `/get/listchap/{rid}?page=N`. Proxy tu fetch + boc (chi stdlib +
httpx, khong can bs4), forward 8001 chi khi parse tung chuong cu the.

v9 — phan trang: v7 fetch tuan tu 15+ pages (~14s/page + sleep 1s = 3-4 phut)
vuot Dio timeout 30s cua app. Gio: page 1 tra ngay (<20s), bam trang nao
fetch dung 1 AJAX trang do; cache RAM + /tmp/toc_cache.json (TTL 1h) nen
truyen da boc tra ngay <1s. Tong 1 request <= 40s (duoi Dio 45s).

Chay: uvicorn proxy_server:app --host 127.0.0.1 --port 8896
"""

import asyncio
import html as _html
import ipaddress
import json
import logging
import re
import shutil
import subprocess
import time
from typing import Any, Optional
from urllib.parse import urljoin, urlsplit

import httpx
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

# Upstream TTS (noi bo, khong lo ra browser).
VIENEU_BASE = "http://144.202.5.197:8001"
KOKORO_BASE = "http://144.202.5.197:8000"

TIMEOUT_VOICES = 15.0
TIMEOUT_PARSE = 30.0
TIMEOUT_TTS = 120.0
# v8: Kokoro primary. v13: 45s (dong bo tang ngan client 45s — do that
# 2026-10-28: Kokoro 3000 chu mat 41s direct, 30s cu kill oan roi fallback
# Vieneu 84s -> client kill tiep. Vieneu fallback giu 120s (van trong tran
# 150s cua tang dai khi chuong >4500 chu).
TIMEOUT_TTS_KOKORO = 45.0
TIMEOUT_TTS_VIENEU = 120.0

# v11: chunk-split trong proxy — Web gui NGUYEN chuong dai (vd 7851 chu)
# ma khong chet: Kokoro gioi han 5000 chu/request, Vieneu 12000. Copy logic
# `KokoroProvider.splitIntoChunks` (lib/src/core/tts/kokoro_provider.dart).
TTS_CHUNK_THRESHOLD = 4500  # text dai hon -> tu cat chunk trong proxy
TTS_CHUNK_TARGET = 400  # do dai muc tieu moi chunk (giong client)
# v11.1 (do thuc te 2026-10-27): Kokoro box xu ly gan nhu single-flight
# (~2-5s/chunk tuan tu); fan-out 6 gay backlog -> timeout hang loat ->
# retry nhan doi tai (death spiral). Giam ve 2: van nhanh gap doi tuan tu
# ma an toan, chunk timeout 45s de song qua luc server ban (tranh retry
# gia khi timeout gia tao them tai).
TTS_CHUNK_PARALLEL = 2  # song song toi da (brief goi y 6, thuc te giam)
TTS_CHUNK_TIMEOUT = 45.0  # moi chunk Kokoro toi da 45s
TTS_CHUNK_RETRY = 1  # chunk loi -> retry 1 lan truoc khi fallback
# v13 (Trail of Bits): tran do dai text 1 request (chuong that <= 15000
# chu; 20000 du rong, chan abuse split hang nghin chunk nang RAM).
TTS_TEXT_MAX = 20000
TIMEOUT_TTS_TOTAL_MAX = 150.0  # tran timeout tong (brief: 20+10s/chunk, max 150)

# v7: fetch muc luc. AJAX /get/listchap/ rat cham (~14s/page, do Cloudflare
# + bot-check) -> timeout 35s/page; fetch tuan tu 1 page/lan de tranh bi
# rate-limit (site tra trang khi bi nghi bot).
TIMEOUT_TOC_PAGE = 35.0
# v7: toi da so page muc luc fetch (truyen 1k chuong ~100 chuong/page -> du).
TOC_MAX_PAGES = 20
# v7: luon fetch tuan tu (site truyen chan fetch song song).
TOC_CONCURRENCY = 1
# v9: phan trang TOC — moi request chi fetch toi da 1 URL (HTML hoac 1 AJAX).
# Tong 1 request <= 40s de khong vuot Dio timeout 45s cua app.
TIMEOUT_TOC_TOTAL = 40.0
# v9: cache RAM + persist JSON — truyen 1k+ chuong giu nguyen 1 ngay van
# duoi vai tram KB (chi title+url).
TOC_CACHE_TTL = 3600.0
TOC_CACHE_PATH = "/tmp/toc_cache.json"

UA_BROWSER = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
)

log = logging.getLogger("truyen-proxy")

app = FastAPI(title="truyen-audio-proxy", version="11")


# ---------------------------------------------------------------------------
# v11: chunk-split trong proxy.
#
# Van de (user bao 2026-10-27): chuong 7851 chu -> Web gui NGUYEN text qua
# POST /api/tts -> Kokoro 422 (>5000) -> Vieneu timeout 120s (full text) ->
# 502. Root cause: chunk-split (~400 chu, song song) chi nam o app Flutter,
# proxy khong co -> Web gui cuc to la chet.
#
# Fix: text > 4500 chu -> proxy tu cat chunk <=400 chu (copy logic Dart),
# goi Kokoro song song toi da 6, noi MP3 tra ve. Chunk loi -> retry 1 lan ->
# fallback chunk do sang Vieneu (12000 chu OK). Timeout tong = 20s +
# 10s/chunk (tran 150s). Header X-Chunks: N de debug.
# ---------------------------------------------------------------------------

_SENTENCE_RE = re.compile(r"[^.!?…\n]+[.!?…\n]+|[^.!?…\n]+$")


def split_text_chunks(text: str, target: int = TTS_CHUNK_TARGET) -> list[str]:
    """Cat text thanh chunk ~target ky tu, uu tien cat tai dau cau.

    Port 1-1 tu `KokoroProvider.splitIntoChunks` (Dart) de client/server
    cat giong nhau: tach cau theo dau cau + xuong dong, don vao buffer den
    khi day thi cat; cau don dai hon target thi cat cung.
    """
    trimmed = (text or "").strip()
    if not trimmed:
        return []
    if len(trimmed) <= target:
        return [trimmed]
    sentences = [
        m.group(0).strip() for m in _SENTENCE_RE.finditer(trimmed)
    ]
    sentences = [s for s in sentences if s]
    if not sentences:
        return [trimmed]
    chunks: list[str] = []
    buf: list[str] = []

    def _buf_len() -> int:
        # Do dai neu ghep buffer hien tai (them 1 space giua cac cau).
        return sum(len(s) for s in buf) + max(0, len(buf) - 1)

    def _flush() -> None:
        if buf:
            chunks.append(" ".join(buf).strip())
            buf.clear()

    for sentence in sentences:
        # Cau don dai hon target: cat cung theo do dai (khong mat chu).
        if len(sentence) > target:
            _flush()
            rest = sentence.strip()
            while len(rest) > target:
                chunks.append(rest[:target].strip())
                rest = rest[target:].strip()
            if rest:
                if not buf:
                    buf.append(rest)
                else:
                    _flush()
                    buf.append(rest)
            continue
        candidate = (
            sentence if not buf else f"{' '.join(buf)} {sentence}"
        )
        if len(candidate) <= target:
            buf.clear()
            buf.append(candidate)
        else:
            _flush()
            buf.append(sentence)
    _flush()
    return [c for c in chunks if c]


def _tts_total_timeout(n_chunks: int) -> float:
    """Timeout tong v11: 20s + 10s/chunk, tran 150s (brief)."""
    return min(20.0 + 10.0 * max(1, n_chunks), TIMEOUT_TTS_TOTAL_MAX)

# v9: cache phan trang TOC {story_url: {rid, max_page, ts, pages: {N: [...]}}}.
# RAM tra ngay (<1s); persist JSON de restart proxy khong mat.
_TOC_CACHE: dict[str, dict[str, Any]] = {}


def _toc_cache_load() -> None:
    try:
        with open(TOC_CACHE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return
    if isinstance(data, dict):
        now = time.monotonic()
        for k, v in data.items():
            if isinstance(v, dict) and now - float(v.get("ts", 0)) < TOC_CACHE_TTL:
                _TOC_CACHE[k] = v


def _toc_cache_save() -> None:
    try:
        with open(TOC_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(_TOC_CACHE, f, ensure_ascii=False)
    except OSError as e:
        log.warning("toc cache save loi: %s", e)


_toc_cache_load()

# CORS mo (proxy + Caddy cung origin nen that ra khong can,
# nhung giu de test truc tiep / phong thu).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_client: Optional[httpx.AsyncClient] = None


def _norm(path: str) -> str:
    """Chap nhan ca '/api/x' va '/x' (Caddy da strip, test truc tiep thi chua)."""
    if path == "/api" or path.startswith("/api/"):
        return path[4:] or "/"
    return path


def _client_or_new() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(follow_redirects=True)
    return _client


async def _pipe_json(
    method: str, url: str, body: Any = None, timeout: float = 30.0
) -> Response:
    """Forward request, tra JSON (voices/parse) ve nguyen trang."""
    client = _client_or_new()
    try:
        r = await client.request(method, url, json=body, timeout=timeout)
    except httpx.TimeoutException as e:
        log.warning("upstream timeout %s: %s", url, e)
        return JSONResponse({"error": f"upstream timeout: {url}"}, status_code=504)
    except httpx.HTTPError as e:
        log.warning("upstream loi %s: %s", url, e)
        return JSONResponse({"error": f"upstream loi: {e}"}, status_code=502)
    return Response(
        content=r.content,
        status_code=r.status_code,
        media_type=r.headers.get("content-type", "application/json"),
    )


# ---------------------------------------------------------------------------
# v7: boc muc luc (TOC) trang truyen — khong dung 8001 (no chi boc text).
# ---------------------------------------------------------------------------

# Dau hieu URL la chuong cu the (parse noi dung) thay vi trang truyen (TOC).
_CHAPTER_MARKERS = ("/chuong-", "/chapter")

# Link chuong trong HTML (ca HTML trang lan JSON data cua AJAX — deu dung
# quote don, nhung regex chap nhan ca 2 loai quote cho chac).
_CHAPTER_LINK_RE = re.compile(
    r"<a\s+[^>]*href=['\"]([^'\"]+)['\"][^>]*>([^<]*)</a>",
    re.IGNORECASE,
)
# Book id so cho AJAX phan trang: var rid = '109629';
_RID_RE = re.compile(r"var\s+rid\s*=\s*['\"](\d+)['\"]")
# Nut phan trang: page(109629,2) ... page(109629,15) ("Cuoi").
_PAGE_FN_RE = re.compile(r"page\(\s*(\d+)\s*,\s*(\d+)\s*\)")


def _is_chapter_url(url: str) -> bool:
    """URL tro thang 1 chuong (forward 8001) hay trang truyen (boc TOC)."""
    u = url.lower()
    return any(m in u for m in _CHAPTER_MARKERS)


def _host_bi_chan(host: str) -> bool:
    """Chan fetch toi host noi bo / metadata (giam SSRF khi fetch TOC)."""
    h = (host or "").lower()
    if h in ("localhost", "metadata.google.internal"):
        return True
    try:
        ip = ipaddress.ip_address(h.strip("[]"))
    except ValueError:
        return h.startswith("metadata.")
    return (
        ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_private
        or ip.is_reserved
        or ip.is_unspecified  # v13 (Trail of Bits): chan 0.0.0.0/:: len them
    )


def _toc_parser_name(host: str) -> Optional[str]:
    """Dispatcher theo domain (v7 chi metruyenchu chay, site khac bao ro)."""
    h = (host or "").lower()
    if (
        h.endswith("metruyenchu.com.vn")
        or h.endswith("metruyenchu.vn")
        or h.endswith("metruyenchuvn.com")
    ):
        return "metruyenchu"
    return None


_SO_CHUONG_RE = re.compile(r"[Cc]h..ng\s+(\d+)")


def _so_chuong(pair: tuple[str, str]) -> tuple[int, str]:
    """Key sort: (so chuong, title) — khong parse duoc -> xep cuoi."""
    m = _SO_CHUONG_RE.search(pair[0] or "")
    return (int(m.group(1)), pair[0]) if m else (10**9, pair[0])


def _tach_links(html_text: str, base_url: str) -> list[tuple[str, str]]:
    """Boc (title, url-tuyet-doi) cac link chuong, dedupe giu thu tu."""
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for m in _CHAPTER_LINK_RE.finditer(html_text or ""):
        href = (m.group(1) or "").strip()
        hl = href.lower()
        if "/chuong-" not in hl and "/chapter" not in hl:
            continue
        full = urljoin(base_url, href)
        if full in seen:
            continue
        seen.add(full)
        title = re.sub(r"\s+", " ", _html.unescape(m.group(2) or "")).strip()
        out.append((title or full, full))
    return out


async def _fetch_text(
    client: httpx.AsyncClient,
    url: str,
    *,
    referer: Optional[str] = None,
    ajax: bool = False,
) -> Optional[str]:
    """GET HTML voi UA browser (site truyen chan bot tran)."""
    headers = {"User-Agent": UA_BROWSER}
    if referer:
        headers["Referer"] = referer
    if ajax:
        headers["X-Requested-With"] = "XMLHttpRequest"
    try:
        r = await client.get(url, headers=headers, timeout=TIMEOUT_TOC_PAGE)
    except httpx.HTTPError as e:
        log.warning("toc fetch loi %s: %s", url, e)
        return None
    if r.status_code != 200:
        log.warning("toc fetch %s status=%s", url, r.status_code)
        return None
    return r.text


def _meta_metruyenchu(first_html: str) -> tuple[Optional[str], int]:
    """Boc rid + max_page tu HTML trang truyen (khong fetch them)."""
    rid_m = _RID_RE.search(first_html or "")
    if not rid_m:
        return None, 1  # khong co rid -> truyen 1 page duy nhat
    rid = rid_m.group(1)
    pages = sorted(
        {
            int(pg)
            for bid, pg in _PAGE_FN_RE.findall(first_html)
            if bid == rid and pg.isdigit()
        }
    )
    return rid, min(max(pages or [1]), TOC_MAX_PAGES)


async def _toc_ajax_page(
    client: httpx.AsyncClient,
    origin: str,
    story_url: str,
    rid: str,
    page: int,
) -> list[tuple[str, str]]:
    """Fetch DUNG 1 page AJAX /get/listchap/{rid}?page=N (v9: khong crawl)."""
    txt = await _fetch_text(
        client,
        f"{origin}/get/listchap/{rid}?page={page}",
        referer=story_url,
        ajax=True,
    )
    if not txt:
        return []
    try:
        data = json.loads(txt).get("data") or ""
    except (ValueError, AttributeError):
        return []
    if not isinstance(data, str):
        return []
    # _tach_links da dedupe trong page; page vuot qua thuc te tra ve rong
    # hoac lap page cu (site wrap) -> goi ham tra ve nhu site tra, ke ca rong.
    return _tach_links(data, story_url)


def _toc_trang_phan_hoi(
    story_url: str,
    pairs: list[tuple[str, str]],
    *,
    page: int,
    max_page: int,
    rid: Optional[str],
) -> Response:
    """Dong goi response 1 page TOC + metadata phan trang (v9)."""
    pairs.sort(key=_so_chuong)
    estimate = max(len(pairs), max_page * 100) if rid else len(pairs)
    log.info("toc %s page %s/%s: %d chuong", story_url, page, max_page, len(pairs))
    return JSONResponse(
        {
            "chapters": [{"title": t, "url": u, "len": 0} for t, u in pairs],
            "total": estimate,
            "total_estimate": estimate,
            "page": page,
            "max_page": max_page,
            "rid": rid,
            "story_url": story_url,
            "texts": [],
        }
    )


async def _boc_toc_1_page(
    client: httpx.AsyncClient,
    story_url: str,
    host: str,
    page: int,
) -> Response:
    """Fetch toi da 1 URL (HTML page 1 hoac 1 AJAX) roi tra ngay (v9)."""
    now = time.monotonic()
    entry = _TOC_CACHE.get(story_url)
    if entry is not None and now - float(entry.get("ts", 0)) >= TOC_CACHE_TTL:
        entry = None
        _TOC_CACHE.pop(story_url, None)
    if entry is not None:
        pages = entry.get("pages") or {}
        hit = pages.get(str(page))
        if isinstance(hit, list) and hit:
            pairs = [(str(t), str(u)) for t, u in hit if isinstance(u, str)]
            if pairs:
                return _toc_trang_phan_hoi(
                    story_url,
                    pairs,
                    page=page,
                    max_page=int(entry.get("max_page", 1)),
                    rid=entry.get("rid"),
                )

    parts = urlsplit(story_url)
    origin = f"{parts.scheme}://{parts.netloc}"
    rid: Optional[str] = entry.get("rid") if entry else None
    max_page: int = int(entry.get("max_page", 1)) if entry else 1
    first_html: Optional[str] = None

    if entry is None:
        # Chua co cache -> fetch HTML 1 lan de boc page 1 + rid/max_page.
        first_html = await _fetch_text(client, story_url)
        if first_html is None:
            return JSONResponse(
                {"error": f"khong tai duoc trang truyen: {story_url}"},
                status_code=502,
            )
        rid, max_page = _meta_metruyenchu(first_html)
        entry = {
            "rid": rid,
            "max_page": max_page,
            "ts": now,
            "pages": {},
        }
        _TOC_CACHE[story_url] = entry

    page = min(max(1, page), max_page)
    cached_pages = entry.get("pages")
    if not isinstance(cached_pages, dict):
        cached_pages = {}
        entry["pages"] = cached_pages
    if page == 1:
        if first_html is None:
            first_html = await _fetch_text(client, story_url)
            if first_html is None:
                return JSONResponse(
                    {"error": f"khong tai duoc trang truyen: {story_url}"},
                    status_code=502,
                )
            # Lam moi rid/max_page phong khi truyen ra them chuong.
            rid, max_page = _meta_metruyenchu(first_html)
            entry["rid"] = rid
            entry["max_page"] = max_page
        pairs = _tach_links(first_html, story_url)
    else:
        if not rid:
            return JSONResponse(
                {"error": "truyen nay chi co 1 trang muc luc"},
                status_code=422,
            )
        pairs = await _toc_ajax_page(client, origin, story_url, rid, page)

    if not pairs:
        return JSONResponse(
            {
                "error": (
                    f"khong lay duoc muc luc trang {page} "
                    "(site cham hoac het trang, hay thu lai)"
                )
            },
            status_code=502,
        )
    entry["ts"] = time.monotonic()
    cached_pages[str(page)] = [[t, u] for t, u in pairs]
    _toc_cache_save()
    return _toc_trang_phan_hoi(
        story_url, pairs, page=page, max_page=max_page, rid=rid
    )


async def _boc_toc(story_url: str, page: int = 1) -> Response:
    """Boc muc luc 1 trang truyen, tra NGAY 1 page (v9 phan trang).

    - page=1: fetch HTML 1 lan -> links page 1 + rid/max_page (<20s).
    - page>1: fetch dung 1 AJAX /get/listchap/{rid}?page=N.
    - Tong 1 request <= TIMEOUT_TOC_TOTAL (40s); qua han -> 504 ro rang.
    """
    try:
        parts = urlsplit(story_url)
    except ValueError:
        return JSONResponse({"error": "URL truyen khong hop le"}, status_code=400)
    host = parts.hostname or ""
    if parts.scheme not in ("http", "https") or not host:
        return JSONResponse(
            {"error": "URL truyen phai bat dau bang http:// hoac https://"},
            status_code=400,
        )
    if _host_bi_chan(host):
        return JSONResponse(
            {"error": "URL tro toi host noi bo, khong duoc phep fetch"},
            status_code=403,
        )
    site = _toc_parser_name(host)
    if site is None:
        return JSONResponse(
            {
                "error": (
                    f"chua ho tro boc muc luc site {host} "
                    "(moi ho tro metruyenchu; hay paste URL chuong "
                    "cu the de parse truc tiep)"
                )
            },
            status_code=422,
        )
    client = _client_or_new()
    try:
        return await asyncio.wait_for(
            _boc_toc_1_page(client, story_url, host, page),
            timeout=TIMEOUT_TOC_TOTAL,
        )
    except asyncio.TimeoutError:
        log.warning("toc timeout tong %ss: %s (page %s)", TIMEOUT_TOC_TOTAL, story_url, page)
        return JSONResponse(
            {
                "error": (
                    "site truyen phan hoi qua cham (>40s), "
                    "hay thu lai sau it phut"
                )
            },
            status_code=504,
        )


@app.get("/health")
async def health() -> dict:
    return {"ok": True, "vieneu": VIENEU_BASE, "kokoro": KOKORO_BASE}


async def _voices_vieneu() -> Response:
    return await _pipe_json("GET", f"{VIENEU_BASE}/voices", timeout=TIMEOUT_VOICES)


async def _voices_kokoro() -> Response:
    return await _pipe_json("GET", f"{KOKORO_BASE}/voices", timeout=TIMEOUT_VOICES)


# ---------------------------------------------------------------------------
# v14 helpers: boc SACH noi dung chuong — cat menu/nut rac.
#
# Van de (Lead QA live B2.5, 2026-10-28): server 8001 boc text CA TRANG
# (menu DANH SACH/THE LOAI + nut "Chuong truoc/tiep" + "Tai Ebook") nen
# TTS doc rac. Noi dung sach nam trong `div.vung-doc#vungdoc`, nhung can
# cat nut dieu huong dau/cuoi.
#
# Ranh gioi da xac minh bang curl + boc `div#vungdoc` (2026-10-28):
#   div#vungdoc > div.truyen ... [NOI DUNG SACH] ... div.chapter_wrap.control-last
# Rac can loai: 2x div.chapter_control, button#download-book,
# link "Chuong truoc/tiep", "Tai Ebook", "Cai dat giao dien".
# ---------------------------------------------------------------------------

# Cum tu rac xuat hien trong nut/link dieu huong (dong < 60 ky tu moi loc).
_RAC_CHUONG = (
    "Chương trước",
    "Chương tiếp",
    "《 Chương",
    "Chương 》",
    "Tải Ebook",
    "Cài đặt giao diện",
    "Danh sách chương",
)

# Regex cat khoi chapter_control / download-book truoc khi strip tags.
_CHAPTER_CONTROL_RE = re.compile(
    r'<div[^>]*class\s*=\s*["\'][^"\']*chapter_control[^"\']*["\'][^>]*>'
    r".*?</div>",
    re.IGNORECASE | re.DOTALL,
)
_DOWNLOAD_BOOK_RE = re.compile(
    r'<button[^>]*id\s*=\s*["\']download-book["\'].*?</button>',
    re.IGNORECASE | re.DOTALL,
)
_VUNGDOC_RE = re.compile(
    r'<div[^>]*\bid\s*=\s*["\']vungdoc["\'][^>]*>', re.IGNORECASE
)
_VUNGDOC_CLASS_RE = re.compile(
    r'<div[^>]*\bclass\s*=\s*["\'][^"\']*vung-doc[^"\']*["\'][^>]*>',
    re.IGNORECASE,
)
_TITLE_CHUONG_RE = re.compile(
    r'<h2[^>]*class\s*=\s*["\'][^"\']*current-chapter[^"\']*["\'][^>]*>'
    r"(.*?)</h2>",
    re.IGNORECASE | re.DOTALL,
)


def _strip_tags_ve_text(html_doan: str) -> str:
    """Strip tags -> text sach (unescape entities, chuan hoa newline)."""
    s = _CHAPTER_CONTROL_RE.sub(" ", html_doan)
    s = _DOWNLOAD_BOOK_RE.sub(" ", s)
    s = re.sub(r"<script.*?</script>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<style.*?</style>", " ", s, flags=re.I | re.S)
    s = re.sub(r"<br\s*/?>", "\n", s, flags=re.I)
    s = re.sub(r"</p\s*>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", " ", s)
    s = _html.unescape(s)
    s = re.sub(r"[ \t\xa0]+", " ", s)
    s = re.sub(r"\n\s*\n\s*\n+", "\n\n", s).strip()
    lines = [ln.strip() for ln in s.split("\n")]
    # Loc dong rac con sot (nut/link dieu huong, dong qua ngan).
    sach = [
        ln
        for ln in lines
        if ln and not any(r in ln and len(ln) < 60 for r in _RAC_CHUONG)
    ]
    return "\n".join(sach)


def _sach_noi_dung_chuong(html_trang: str) -> tuple[str, str]:
    """Boc (title, text-sach) tu HTML trang chuong metruyenchu.

    - Tim `div#vungdoc` (fallback `div.vung-doc`); khong thay -> ("","").
    - Title tu `h2.current-chapter` (fallback `h1`).
    - Noi dung tu `div.truyen` den truoc `control-last` (cat nut 2 dau);
      fallback: toan bo div#vungdoc da loai chapter_control/download-book.
    - Tra ("","") neu khong boc duoc gi de caller forward 8001 nhu cu.
    """
    m = _VUNGDOC_RE.search(html_trang or "")
    if not m:
        m = _VUNGDOC_CLASS_RE.search(html_trang or "")
    if not m:
        return "", ""
    seg = html_trang[m.end() : m.end() + 60000]
    title = ""
    tm = _TITLE_CHUONG_RE.search(seg)
    if not tm:
        tm = re.search(r"<h1[^>]*>(.*?)</h1>", seg, re.I | re.S)
    if tm:
        title = re.sub(r"<[^>]+>", "", tm.group(1))
        title = re.sub(r"\s+", " ", _html.unescape(title)).strip()
    start = seg.find('div class="truyen"')
    if start < 0:
        start = seg.find('class="truyen"')
    end = seg.find("control-last")
    if start >= 0:
        gt = seg.find(">", start)
        body = seg[gt + 1 : end if end > gt else gt + 30000]
    else:
        body = seg[:30000]
    text = _strip_tags_ve_text(body)
    if not text:
        return "", ""
    full = f"{title}\n\n{text}".strip() if title else text
    return title, full


async def _parse_chuong_sach(url_chuong: str) -> Optional[tuple[str, str]]:
    """Fetch HTML chuong + boc sach. Tra (title, text) hoac None neu hong."""
    client = _client_or_new()
    html_trang = await _fetch_text(client, url_chuong, referer=url_chuong)
    if not html_trang:
        return None
    title, full = _sach_noi_dung_chuong(html_trang)
    if not full:
        return None
    return title, full


async def _parse(request: Request) -> Response:
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "body phai la JSON"}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"error": "body phai la object JSON"}, status_code=400)
    url = body.get("url")
    text = body.get("text")
    # v7: body chi co url trang truyen (khong phai url chuong, khong co text)
    # -> tu boc muc luc thay vi forward mu sang 8001 (no chi tra text gioi
    # thieu rac). URL chuong cu the (/chuong-, /chapter) van forward nhu cu
    # vi 8001 parse noi dung 1 chuong tot.
    # v9: phan trang — body co the kem "page" (default 1); chi fetch 1 page.
    if (
        isinstance(url, str)
        and url.strip()
        and (not isinstance(text, str) or not text.strip())
        and not _is_chapter_url(url.strip())
    ):
        try:
            page = int(body.get("page", 1))
        except (TypeError, ValueError):
            page = 1
        return await _boc_toc(url.strip(), page=max(1, page))
    # v14: url chuong cu the -> boc SACH div#vungdoc truoc (cat menu/nut
    # rac ma 8001 dang boc ca trang); neu boc sach that bai (site doi cau
    # truc, fetch hong) moi forward 8001 nhu cu. Header X-Clean: 1 = boc
    # sach noi bo, 0 = forward 8001 (de debug).
    if (
        isinstance(url, str)
        and url.strip()
        and (not isinstance(text, str) or not text.strip())
        and _is_chapter_url(url.strip())
    ):
        sach = await _parse_chuong_sach(url.strip())
        if sach is not None:
            title, full = sach
            return JSONResponse(
                {
                    "chapters": [{"title": title, "url": url.strip(), "len": len(full)}],
                    "texts": [full],
                },
                headers={"X-Clean": "1"},
            )
    resp = await _pipe_json(
        "POST", f"{VIENEU_BASE}/parse", body=body, timeout=TIMEOUT_PARSE
    )
    # v14: forward 8001 -> danh dau X-Clean: 0 (de app/log biet text chua sach).
    resp.headers["X-Clean"] = "0"
    return resp


def _toc_page_cua(request: Request) -> int:
    """Doc ?page=N (default 1, clamp >=1) cho GET /toc."""
    try:
        return max(1, int((request.query_params.get("page") or "1").strip()))
    except (TypeError, ValueError):
        return 1


async def _toc(request: Request) -> Response:
    """GET /toc?url=<trang-truyen>[&page=N] — boc 1 page muc luc (v9)."""
    url = (request.query_params.get("url") or "").strip()
    if not url:
        return JSONResponse({"error": "thieu query param 'url'"}, status_code=400)
    return await _boc_toc(url, page=_toc_page_cua(request))


async def _tts(request: Request) -> Response:
    """Thu Kokoro truoc, loi/timeout thi Vieneu (v8: Kokoro primary).

    Body vao: {"text","voice",...} + tuy chon:
      - "provider": "vieneu" | "kokoro" | "auto" (mac dinh auto).
      - "vieneu_voice": voice dung khi fallback chunk sang Vieneu
        (mac dinh 'Trúc Ly'); "kokoro_voice": nguoc lai ('diem_trinh').

    v11 — chunk-split trong proxy: text > 4500 chu thi TU cat chunk ~400
    chu (split_text_chunks, port tu KokoroProvider Dart), goi Kokoro song
    song toi da 6, noi MP3 tra ve + header X-Chunks. Chunk loi -> retry 1
    lan -> fallback chunk do sang provider con lai (Vieneu chunk duoc
    transcode WAV->MP3 bang ffmpeg de noi dong nhat). Timeout tong =
    20s + 10s/chunk (tran 150s). Text ngan giu nguyen single-shot (v8).
    """
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "body phai la JSON"}, status_code=400)
    if not isinstance(body, dict) or not str(body.get("text", "")).strip():
        return JSONResponse({"error": "thieu 'text'"}, status_code=400)

    text = str(body["text"]).strip()
    if len(text) > TTS_TEXT_MAX:
        return JSONResponse(
            {"error": f"text dai {len(text)} ky tu, vuot qua {TTS_TEXT_MAX}"},
            status_code=413,
        )
    voice = str(body.get("voice", "")).strip()
    speed = body.get("speed", 1.0)
    try:
        speed = float(speed)
    except (TypeError, ValueError):
        speed = 1.0
    speed = min(1.5, max(0.5, speed))
    fmt = str(body.get("format", "mp3") or "mp3")
    hint = str(body.get("provider", "auto") or "auto").strip().lower()
    # v11: voice rieng cho tung provider khi fallback theo chunk (client
    # gui kem de giu dung giong doc du fallback doi provider giua chung).
    vieneu_voice = str(body.get("vieneu_voice", "") or "").strip() or voice
    kokoro_voice = str(body.get("kokoro_voice", "") or "").strip() or voice

    # v11: text dai -> chunk-split trong proxy (fix chuong 7851 chu chet
    # ca 2 upstream). Giu "provider" hint: vieneu-only thi cat chunk
    # Vieneu (12000 chu/chunk, khong can cat), kokoro-only/auto thi
    # Kokoro + fallback Vieneu theo tung chunk.
    if len(text) > TTS_CHUNK_THRESHOLD and hint in ("auto", "kokoro"):
        return await _tts_chunked(
            text,
            kokoro_voice=kokoro_voice or "diem_trinh",
            vieneu_voice=vieneu_voice or "Trúc Ly",
            speed=speed,
            provider=hint,
        )

    client = _client_or_new()
    tried: list[str] = []

    async def _call_vieneu() -> Response | None:
        tried.append("vieneu")
        try:
            r = await client.post(
                f"{VIENEU_BASE}/tts",
                json={"text": text, "voice": voice},
                timeout=TIMEOUT_TTS_VIENEU,
            )
            if 200 <= r.status_code < 300 and r.content:
                return Response(content=r.content, media_type="audio/wav")
            log.warning("vieneu /tts status=%s", r.status_code)
        except httpx.HTTPError as e:
            log.warning("vieneu /tts loi (%s)", e)
        return None

    async def _call_kokoro_soft() -> Response | None:
        """Thu Kokoro, that bai -> tra None de caller fallback (auto mode)."""
        tried.append("kokoro")
        try:
            r = await client.post(
                f"{KOKORO_BASE}/tts",
                json={"text": text, "voice": voice, "speed": speed, "format": fmt},
                timeout=TIMEOUT_TTS_KOKORO,
            )
        except httpx.HTTPError as e:
            log.warning("kokoro /tts loi (%s)", e)
            return None
        if not (200 <= r.status_code < 300 and r.content):
            log.warning("kokoro /tts status=%s", r.status_code)
            return None
        return Response(
            content=r.content,
            media_type=r.headers.get("content-type", "audio/mpeg"),
        )

    async def _call_kokoro_strict() -> Response | JSONResponse:
        """Chi goi Kokoro (hint=kokoro): that bai -> bao loi ro, khong fallback."""
        tried.append("kokoro")
        try:
            r = await client.post(
                f"{KOKORO_BASE}/tts",
                json={"text": text, "voice": voice, "speed": speed, "format": fmt},
                timeout=TIMEOUT_TTS_KOKORO,
            )
        except httpx.TimeoutException:
            return JSONResponse(
                {"error": f"TTS upstream timeout (da thu: {tried})"},
                status_code=504,
            )
        except httpx.HTTPError as e:
            return JSONResponse({"error": f"TTS upstream loi: {e}"}, status_code=502)
        if not (200 <= r.status_code < 300 and r.content):
            return JSONResponse(
                {"error": f"kokoro /tts status={r.status_code}"}, status_code=502
            )
        return Response(
            content=r.content,
            media_type=r.headers.get("content-type", "audio/mpeg"),
        )

    if hint == "vieneu":
        return await _call_vieneu() or JSONResponse(
            {"error": "vieneu /tts that bai"}, status_code=502
        )
    if hint == "kokoro":
        return await _call_kokoro_strict()
    # v8 auto (mac dinh + bat ky hint la nao khac): Kokoro truoc (30s),
    # loi/timeout thi Vieneu (120s). Text NGAN: khong chunk o proxy —
    # client tu cat (native direct-IP) hoac text du ngan de goi 1 shot.
    return await _call_kokoro_soft() or await _call_vieneu() or JSONResponse(
        {"error": f"TTS ca 2 upstream that bai (da thu: {tried})"},
        status_code=502,
    )


# ---------------------------------------------------------------------------
# v11 helpers: chunked TTS (Kokoro song song + fallback Vieneu theo chunk).
# ---------------------------------------------------------------------------

_FFMPEG = shutil.which("ffmpeg")


def _wav_sang_mp3(wav_bytes: bytes) -> Optional[bytes]:
    """Transcode WAV (Vieneu) -> MP3 de noi voi chunk Kokoro.

    Dung ffmpeg CLI (co san tren VPS). Loi/thieu ffmpeg -> None (caller bo
    chunk hoac bao 502 tuy truong hop).
    """
    if not _FFMPEG:
        log.warning("ffmpeg khong co san, khong transcode duoc WAV->MP3")
        return None
    try:
        p = subprocess.run(
            [_FFMPEG, "-v", "error", "-i", "pipe:0",
             "-codec:a", "libmp3lame", "-q:a", "4", "-f", "mp3", "pipe:1"],
            input=wav_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as e:
        log.warning("ffmpeg loi: %s", e)
        return None
    if p.returncode != 0 or not p.stdout:
        log.warning("ffmpeg transcode that bai (rc=%s)", p.returncode)
        return None
    return p.stdout


async def _kokoro_mot_chunk(
    client: httpx.AsyncClient,
    chunk: str,
    voice: str,
    speed: float,
) -> Optional[bytes]:
    """Goi 1 chunk sang Kokoro, retry 1 lan. Tra bytes MP3 hoac None."""
    for attempt in range(TTS_CHUNK_RETRY + 1):
        try:
            r = await client.post(
                f"{KOKORO_BASE}/tts",
                json={"text": chunk, "voice": voice,
                      "speed": speed, "format": "mp3"},
                timeout=TTS_CHUNK_TIMEOUT,
            )
        except httpx.HTTPError as e:
            log.warning("kokoro chunk loi (lan %d): %s", attempt + 1, e)
            continue
        if 200 <= r.status_code < 300 and r.content:
            return bytes(r.content)
        log.warning("kokoro chunk status=%s (lan %d)", r.status_code, attempt + 1)
    return None


async def _vieneu_mot_chunk(
    client: httpx.AsyncClient,
    chunk: str,
    voice: str,
) -> Optional[bytes]:
    """Fallback 1 chunk sang Vieneu, transcode WAV->MP3. Tra bytes hoac None."""
    try:
        r = await client.post(
            f"{VIENEU_BASE}/tts",
            json={"text": chunk, "voice": voice},
            timeout=TIMEOUT_TTS_VIENEU,
        )
    except httpx.HTTPError as e:
        log.warning("vieneu chunk fallback loi: %s", e)
        return None
    if not (200 <= r.status_code < 300 and r.content):
        log.warning("vieneu chunk fallback status=%s", r.status_code)
        return None
    body = bytes(r.content)
    # Vieneu tra WAV (RIFF/WAVE) -> transcode sang MP3 de noi voi chunk Kokoro.
    if len(body) >= 4 and body[0:4] == b"RIFF":
        mp3 = await asyncio.to_thread(_wav_sang_mp3, body)
        if mp3 is None:
            return None
        return mp3
    return body


async def _tts_chunked(
    text: str,
    *,
    kokoro_voice: str,
    vieneu_voice: str,
    speed: float,
    provider: str,
) -> Response:
    """Text dai: cat chunk, Kokoro song song + fallback Vieneu theo chunk.

    - `provider="kokoro"`: chi Kokoro (retry 1 lan), chunk van loi -> 502
      ro chunk index (giu semantics hint cu: khong "cuop" sang Vieneu).
    - `provider="auto"`: chunk Kokoro loi -> fallback chunk do sang Vieneu.
    - Timeout tong = 20s + 10s/chunk (tran 150s). Header X-Chunks: N.
    """
    chunks = split_text_chunks(text)
    if len(chunks) <= 1:
        # Cat khong ra nhieu chunk (vd 1 cau dai lien nhau): gui single-shot
        # qua Kokoro (<=5000 chu van OK) hoac Vieneu neu qua dai.
        chunks = [text] if len(text) <= 5000 else split_text_chunks(
            text, target=11000
        )
    n = len(chunks)
    log.info("tts chunked: %d chu -> %d chunks", len(text), n)
    client = _client_or_new()
    sem = asyncio.Semaphore(TTS_CHUNK_PARALLEL)

    async def _mot(i: int) -> tuple[int, Optional[bytes]]:
        async with sem:
            data = await _kokoro_mot_chunk(
                client, chunks[i], kokoro_voice, speed
            )
            if data is None and provider == "auto":
                log.info("chunk %d/%d fallback Vieneu", i + 1, n)
                data = await _vieneu_mot_chunk(
                    client, chunks[i], vieneu_voice
                )
            return i, data

    total_timeout = _tts_total_timeout(n)
    try:
        results = await asyncio.wait_for(
            asyncio.gather(*(_mot(i) for i in range(n))),
            timeout=total_timeout,
        )
    except asyncio.TimeoutError:
        log.warning("tts chunked timeout tong %ss (%d chunks)", total_timeout, n)
        return JSONResponse(
            {"error": f"TTS chunked timeout tong {total_timeout:.0f}s, thu lai"},
            status_code=504,
        )
    parts: list[Optional[bytes]] = [None] * n
    for i, data in results:
        parts[i] = data
    hong = [i for i, p in enumerate(parts) if not p]
    if hong:
        log.warning("tts chunked hong %d/%d chunks (idx=%s)", len(hong), n, hong)
        return JSONResponse(
            {"error": f"TTS chunked that bai {len(hong)}/{n} chunks"},
            status_code=502,
        )
    out = b"".join(p for p in parts if p)
    return Response(
        content=out,
        media_type="audio/mpeg",
        headers={"X-Chunks": str(n)},
    )


async def _tts_chunk_mot(request: Request) -> Response:
    """v11 progressive: tra RIENG 1 chunk de app phat ngay, khong doi full.

    Body: {"text","chunk": idx, "voice", "speed", "format", "provider",
           "vieneu_voice", "kokoro_voice"} — cat giong _tts_chunked (cung
    target 400) roi tong hop DUNG 1 chunk idx. Tra audio/* + headers
    X-Chunks (tong so chunk) + X-Chunk-Idx. Chunk loi -> fallback nhu
    _tts_chunked (auto) hoac 502 ro idx (kokoro-only).
    """
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "body phai la JSON"}, status_code=400)
    if not isinstance(body, dict) or not str(body.get("text", "")).strip():
        return JSONResponse({"error": "thieu 'text'"}, status_code=400)
    text = str(body["text"]).strip()
    if len(text) > TTS_TEXT_MAX:
        return JSONResponse(
            {"error": f"text dai {len(text)} ky tu, vuot qua {TTS_TEXT_MAX}"},
            status_code=413,
        )
    try:
        idx = int(body.get("chunk", 0))
    except (TypeError, ValueError):
        return JSONResponse({"error": "'chunk' phai la so"}, status_code=400)
    voice = str(body.get("voice", "")).strip()
    speed = body.get("speed", 1.0)
    try:
        speed = float(speed)
    except (TypeError, ValueError):
        speed = 1.0
    speed = min(1.5, max(0.5, speed))
    hint = str(body.get("provider", "auto") or "auto").strip().lower()
    vieneu_voice = str(body.get("vieneu_voice", "") or "").strip() or voice
    kokoro_voice = str(body.get("kokoro_voice", "") or "").strip() or voice

    # Text ngan: chi co chunk 0 (single-shot, dung lai logic cu).
    if len(text) <= TTS_CHUNK_THRESHOLD:
        if idx != 0:
            return JSONResponse(
                {"error": "text ngan chi co chunk 0"}, status_code=422
            )
        chunks = [text]
    else:
        chunks = split_text_chunks(text)
        if len(chunks) <= 1:
            chunks = [text] if len(text) <= 5000 else split_text_chunks(
                text, target=11000
            )
    if idx < 0 or idx >= len(chunks):
        return JSONResponse(
            {"error": f"chunk {idx} ngoai pham vi (0..{len(chunks) - 1})"},
            status_code=422,
        )
    if hint == "vieneu":
        # Vieneu-only: text ngan single-shot, dai thi chunk Vieneu truc tiep.
        client = _client_or_new()
        data = await _vieneu_mot_chunk(
            client, chunks[idx], vieneu_voice or "Trúc Ly"
        )
        if data is None:
            return JSONResponse(
                {"error": f"vieneu chunk {idx} that bai"}, status_code=502
            )
        return Response(
            content=data,
            media_type="audio/mpeg",
            headers={"X-Chunks": str(len(chunks)), "X-Chunk-Idx": str(idx)},
        )
    client = _client_or_new()
    data = await _kokoro_mot_chunk(
        client, chunks[idx], kokoro_voice or "diem_trinh", speed
    )
    if data is None and hint == "auto":
        data = await _vieneu_mot_chunk(
            client, chunks[idx], vieneu_voice or "Trúc Ly"
        )
    if data is None:
        return JSONResponse(
            {"error": f"chunk {idx}/{len(chunks)} that bai"}, status_code=502
        )
    return Response(
        content=data,
        media_type="audio/mpeg",
        headers={"X-Chunks": str(len(chunks)), "X-Chunk-Idx": str(idx)},
    )


# ---------------------------------------------------------------------------
# v14: queue convert NEN full truyen.
#
# Van de (user bao 2026-10-28): moi convert khi bam tung chuong (prefetch
# 2 chuong ke), khong convert full truyen. Fix: worker nen fetch text sach
# tung chuong -> goi TTS chunk -> cache RAM theo url chuong; app poll
# `GET /api/queue/{id}` 5s/lan hien progress tong (x/200 chuong).
# Chuong nao xong app tai ngay qua /tts_chunk nhu cu (cache proxy RAM).
#
# Gioi han (Trail of Bits: queue abuse): toi da 3 queue dong thoi, moi
# queue toi da 200 chuong/lan (truyen 1k chuong chia nhieu lan).
# ---------------------------------------------------------------------------

import uuid as _uuid

QUEUE_MAX_DONG_THOI = 3
QUEUE_MAX_CHUONG = 200
QUEUE_POLL_GIY = 5  # app poll moi 5s (ghi vao response de app biet)

# Cache audio nen theo url chuong {url: bytes-mp3} (app tai qua /tts_chunk
# nhu cu — van dung chung _tts_chunked/_kokoro_mot_chunk nen khong can
# luu rieng; queue chi can biet chuong nao XONG de app goi /tts_chunk).
_QUEUE: dict[str, dict[str, Any]] = {}
_QUEUE_KHOA = asyncio.Lock()

# Gioi han RAM queue: toi da 200 chuong x ~15000 chu (tran TTS_TEXT_MAX).
# Worker cat dung split_text_chunks (target 400) nen khong dot bien RAM.


async def _queue_synth_chuong(
    client: httpx.AsyncClient,
    full: str,
    kokoro_voice: str = "diem_trinh",
    vieneu_voice: str = "Trúc Ly",
) -> Optional[bytes]:
    """Tong hop 1 chuong sach -> MP3 (dung chung cho worker queue).

    - Text ngan (<=5000 chu, 1 chunk): 1 shot Kokoro.
    - Dai: cat chunk ~400 chu, synth SONG SONG (sem TTS_CHUNK_PARALLEL=2,
      giong _tts_chunked — Kokoro box single-flight, fan-out cao gay
      death spiral), chunk hong -> fallback Vieneu.
    - Tra bytes MP3 hoac None (caller danh dau hong, di tiep).
    """
    if len(full) > TTS_TEXT_MAX:
        full = full[:TTS_TEXT_MAX]
    chunks = split_text_chunks(full)
    if len(chunks) <= 1 and len(full) <= 5000:
        return await _kokoro_mot_chunk(client, full, kokoro_voice, 1.0)
    sem = asyncio.Semaphore(TTS_CHUNK_PARALLEL)

    async def _mot(c: str) -> Optional[bytes]:
        async with sem:
            d = await _kokoro_mot_chunk(client, c, kokoro_voice, 1.0)
            if d is None:
                d = await _vieneu_mot_chunk(client, c, vieneu_voice)
            return d

    parts = await asyncio.gather(*(_mot(c) for c in chunks))
    if any(p is None for p in parts):
        return None
    return b"".join(p for p in parts if p)


async def _queue_worker(
    qid: str,
    chapters: list[dict[str, str]],
) -> None:
    """Worker nen: fetch text sach tung chuong -> TTS chunk -> luu RAM.

    Chay nen qua asyncio.create_task; cap nhat tien do vao _QUEUE[qid].
    Loi 1 chuong -> danh dau hong, di tiep chuong sau (khong dung ca queue).
    """
    client = _client_or_new()
    async with _QUEUE_KHOA:
        q = _QUEUE.get(qid)
        if q is None:
            return
        q["status"] = "running"
    for i, ch in enumerate(chapters):
        async with _QUEUE_KHOA:
            q = _QUEUE.get(qid)
            if q is None or q.get("status") == "cancelled":
                return
        url = ch.get("url", "")
        title = ch.get("title", f"chuong {i + 1}")
        try:
            sach = await _parse_chuong_sach(url)
            if sach is None:
                raise RuntimeError("khong boc duoc text sach")
            data = await _queue_synth_chuong(client, sach[1])
            async with _QUEUE_KHOA:
                q = _QUEUE.get(qid)
                if q is None:
                    return
                if data:
                    q["audios"][url] = data
                    q["done"] += 1
                    q["chuong_xong"].append(title)
                else:
                    q["hong"].append(title)
        except Exception as e:  # noqa: BLE001 — queue khong duoc chet vi 1 chuong
            log.warning("queue %s chuong %s loi: %s", qid, title, e)
            async with _QUEUE_KHOA:
                q = _QUEUE.get(qid)
                if q is None:
                    return
                q["hong"].append(title)
        async with _QUEUE_KHOA:
            q = _QUEUE.get(qid)
            if q is None:
                return
            q["tien_do"] = q["done"] + len(q["hong"])
    async with _QUEUE_KHOA:
        q = _QUEUE.get(qid)
        if q is not None and q.get("status") == "running":
            q["status"] = "done"


async def _queue_tao(request: Request) -> Response:
    """POST /queue {story_url, from_page, to_page} -> {queue_id, total}."""
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "body phai la JSON"}, status_code=400)
    if not isinstance(body, dict):
        return JSONResponse({"error": "body phai la object JSON"}, status_code=400)
    story_url = str(body.get("story_url", "") or "").strip()
    if not story_url:
        return JSONResponse({"error": "thieu 'story_url'"}, status_code=400)
    try:
        parts = urlsplit(story_url)
    except ValueError:
        return JSONResponse({"error": "URL truyen khong hop le"}, status_code=400)
    host = parts.hostname or ""
    if parts.scheme not in ("http", "https") or not host:
        return JSONResponse(
            {"error": "URL truyen phai bat dau bang http:// hoac https://"},
            status_code=400,
        )
    if _host_bi_chan(host):
        return JSONResponse(
            {"error": "URL tro toi host noi bo, khong duoc phep fetch"},
            status_code=403,
        )
    if _toc_parser_name(host) is None:
        return JSONResponse(
            {"error": f"chua ho tro boc muc luc site {host}"}, status_code=422
        )
    try:
        from_page = max(1, int(body.get("from_page", 1)))
        to_page = max(1, int(body.get("to_page", 1)))
        # v14: limit so chuong toi da (nghiem thu nhanh 5 chuong dau;
        # production truyen 1k chuong chia nhieu lan, tran QUEUE_MAX_CHUONG).
        limit = int(body.get("limit", QUEUE_MAX_CHUONG))
        limit = max(1, min(limit, QUEUE_MAX_CHUONG))
    except (TypeError, ValueError):
        return JSONResponse(
            {"error": "'from_page'/'to_page'/'limit' phai la so"},
            status_code=400,
        )
    if from_page > to_page:
        from_page, to_page = to_page, from_page
    async with _QUEUE_KHOA:
        dang_chay = sum(
            1 for q in _QUEUE.values() if q.get("status") in ("queued", "running")
        )
        if dang_chay >= QUEUE_MAX_DONG_THOI:
            return JSONResponse(
                {
                    "error": (
                        f"dang co {dang_chay} queue chay "
                        f"(toi da {QUEUE_MAX_DONG_THOI}), hay doi"
                    )
                },
                status_code=429,
            )
    # Lay TOC cac page de ra danh sach chuong (tai su dung _boc_toc_1_page).
    client = _client_or_new()
    chapters: list[dict[str, str]] = []
    try:
        for page in range(from_page, to_page + 1):
            resp = await asyncio.wait_for(
                _boc_toc_1_page(client, story_url, host, page),
                timeout=TIMEOUT_TOC_TOTAL,
            )
            if resp.status_code != 200:
                break
            import json as _json

            data = _json.loads(bytes(resp.body).decode("utf-8"))
            for c in data.get("chapters", []) or []:
                chapters.append(
                    {"title": c.get("title", ""), "url": c.get("url", "")}
                )
            if len(chapters) >= limit:
                break
    except asyncio.TimeoutError:
        return JSONResponse(
            {"error": "site truyen phan hoi qua cham (>40s), hay thu lai"},
            status_code=504,
        )
    chapters = [c for c in chapters if c.get("url")][:limit]
    if not chapters:
        return JSONResponse(
            {"error": "khong lay duoc muc luc cac trang nay"}, status_code=502
        )
    qid = _uuid.uuid4().hex[:12]
    async with _QUEUE_KHOA:
        _QUEUE[qid] = {
            "status": "queued",
            "story_url": story_url,
            "from_page": from_page,
            "to_page": to_page,
            "total": len(chapters),
            "done": 0,
            "tien_do": 0,
            "chuong_xong": [],
            "hong": [],
            "audios": {},
            "tao_luc": time.time(),
        }
    asyncio.create_task(_queue_worker(qid, chapters))
    log.info("queue %s: %d chuong (%s p%d-%d)", qid, len(chapters), story_url, from_page, to_page)
    return JSONResponse(
        {
            "queue_id": qid,
            "total": len(chapters),
            "poll_seconds": QUEUE_POLL_GIY,
        }
    )


async def _queue_tien_do(request: Request) -> Response:
    """GET /queue/{qid} -> {done, total, chuong_xong, hong, status}."""
    qid = request.path_params.get("qid", "")
    async with _QUEUE_KHOA:
        q = _QUEUE.get(qid)
        if q is None:
            return JSONResponse(
                {"error": f"khong tim thay queue {qid}"}, status_code=404
            )
        return JSONResponse(
            {
                "queue_id": qid,
                "status": q["status"],
                "done": q["done"],
                "total": q["total"],
                "tien_do": q["tien_do"],
                "chuong_xong": list(q["chuong_xong"][-10:]),
                "hong": list(q["hong"]),
                "poll_seconds": QUEUE_POLL_GIY,
            }
        )


async def _queue_audio(request: Request) -> Response:
    """GET /queue/{qid}/audio?url=<url-chuong> -> audio MP3 chuong da xong."""
    qid = request.path_params.get("qid", "")
    url = (request.query_params.get("url") or "").strip()
    async with _QUEUE_KHOA:
        q = _QUEUE.get(qid)
        if q is None:
            return JSONResponse(
                {"error": f"khong tim thay queue {qid}"}, status_code=404
            )
        data = q["audios"].get(url)
        if data is None:
            return JSONResponse(
                {"error": "chuong chua xong hoac khong co trong queue"},
                status_code=404,
            )
    return Response(content=bytes(data), media_type="audio/mpeg")


# Route chinh (sau khi Caddy strip /api) + alias giu prefix (test truc tiep).
for _route, _handler, _methods in [
    ("/voices/vieneu", _voices_vieneu, ["GET"]),
    ("/voices/kokoro", _voices_kokoro, ["GET"]),
    ("/parse", _parse, ["POST"]),
    ("/toc", _toc, ["GET"]),
    ("/tts", _tts, ["POST"]),
    ("/tts_chunk", _tts_chunk_mot, ["POST"]),
    ("/queue", _queue_tao, ["POST"]),
]:
    app.add_api_route(_route, _handler, methods=_methods)  # type: ignore[arg-type]
    app.add_api_route(f"/api{_route}", _handler, methods=_methods)  # type: ignore[arg-type]

# Queue progress/audio co path param -> dang ky rieng (khong di chung loop).
app.add_api_route("/queue/{qid}", _queue_tien_do, methods=["GET"])
app.add_api_route("/api/queue/{qid}", _queue_tien_do, methods=["GET"])
app.add_api_route("/queue/{qid}/audio", _queue_audio, methods=["GET"])
app.add_api_route("/api/queue/{qid}/audio", _queue_audio, methods=["GET"])


@app.on_event("shutdown")
async def _shutdown() -> None:
    global _client
    if _client is not None and not _client.is_closed:
        await _client.aclose()
    _client = None
