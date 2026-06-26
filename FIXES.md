# NVD Pipeline Fixes Summary

## 問題診斷

1. **文件名不一致**: `scripts/nvd` 生成 `nvd_feeds.json.gz`，但 `publish-nvd-feeds` 期望 `merged_nvd_feeds.json.gz`
2. **文件被刪除**: `scripts/nvd` 的 `clean_up()` 刪除了 `feeds/` 目錄，但 workflow 需要 commit 它
3. **環境變量未傳遞**: wrapper 腳本沒有正確 export 環境變量
4. **Gzip 壓縮缺失**: 原本的 `pack` 腳本沒有壓縮輸出

## 修復內容

### 1. scripts/nvd
- ✅ 統一輸出文件名為 `merged_nvd_feeds.json.gz`（可通過 `OUTPUT_FILE` 環境變量覆蓋）
- ✅ 修改 `clean_up()` 只刪除臨時目錄，保留 `feeds/` 目錄
- ✅ 直接生成 gzip 壓縮的 JSON

### 2. scripts/pack
- ✅ 使用 pipe 到 gzip，直接輸出 `.json.gz`
- ✅ 更新所有變量引用指向 `.json.gz` 文件

### 3. scripts/publish-nvd-feeds
- ✅ 更新 `TARGET_FILE` 預設值為 `merged_nvd_feeds.json.gz`
- ✅ 更新 `FILE_MEDIA_TYPE` 為 `application/gzip`
- ✅ 明確 export 所有環境變量
- ✅ 使用 `"$SCRIPT_DIR/publish-oci-artifact"` 而非 `bash`

### 4. scripts/sign-nvd-feeds & scripts/verify-nvd-feeds
- ✅ 明確 export 環境變量
- ✅ 更新文件引用為 `.json.gz`

### 5. .github/workflows/nvd.yaml
- ✅ 更新 commit 文件列表：`feeds/` + `merged_nvd_feeds.json.gz*` + `nvd-feeds.oci-ref`

### 6. 新增測試腳本
- ✅ `scripts/test-local.sh` - 本地測試整個流程

## 預期流程

```bash
# 1. Download & Merge
scripts/nvd
  → 下載 feeds/nvdcve-2.0-*.json.gz
  → 合併成 merged_nvd_feeds.json.gz

# 2. Publish to OCI
scripts/publish-nvd-feeds
  → 上傳 merged_nvd_feeds.json.gz
  → 生成 nvd-feeds.oci-ref (包含 digest)

# 3. Sign
scripts/sign-nvd-feeds
  → 簽名 OCI artifact

# 4. Commit
git add feeds/ merged_nvd_feeds.json.gz* nvd-feeds.oci-ref
```

## 測試方法

```bash
# 本地測試（只下載 2002 年）
./scripts/test-local.sh

# 完整測試
START_YEAR=2002 END_YEAR=2026 bash scripts/nvd
```

## OCI Ref 格式

生成的 `nvd-feeds.oci-ref` 內容：
```
ghcr.io/{owner}/{repo}/nvd-feeds@sha256:{digest}
```

例如：
```
ghcr.io/pohanhuang/nvd-vuls/nvd-feeds@sha256:abc123def456...
```
