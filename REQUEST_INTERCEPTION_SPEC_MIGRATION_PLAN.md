# Request Interception Spec Migration Plan

このドキュメントは、Puppeteer (TypeScript) のリクエストインターセプションテストをpuppeteer-rubyに移植するための計画書です。

## 移植元ファイル

- https://github.com/puppeteer/puppeteer/blob/main/test/src/requestinterception.spec.ts
- https://github.com/puppeteer/puppeteer/blob/main/test/src/requestinterception-experimental.spec.ts

## 現状の把握

### 実装済み機能 (`lib/puppeteer/http_request.rb`)

以下の機能はpuppeteer-rubyで実装済み:

- `page.request_interception=` - リクエストインターセプションの有効化/無効化
- `request.continue` - リクエストの継続（URL/method/headers/post_data変更可）
- `request.respond` - モックレスポンスの返却
- `request.abort` - リクエストの中止（エラーコード指定可）
- Cooperative Interception Mode（priority指定による優先度付きインターセプション）
- `request.intercept_resolution_state` - 現在の解決状態の取得
- `request.intercept_resolution_handled?` - ハンドル済みかどうかの確認

### 既存テスト (`spec/integration/request_interception_spec.rb`)

現在実装されているテスト:

1. `should intercept` - 基本的なインターセプション
2. `should indicate already-handled if an intercept has been handled` - ハンドル済みの確認
3. `should allow mocking multiple headers with same key` - 複数ヘッダーのモック

また、Cooperative Interception Modeの動作確認例が4つ含まれている。

## テスト移植マッピング

### 1. Page.setRequestInterception グループ

| # | TypeScript テスト名 | Ruby実装状況 | 優先度 | 備考 |
|---|---------------------|-------------|--------|------|
| 1 | should intercept | ✅ 実装済み | - | |
| 2 | should work when POST is redirected with 302 | ❌ 未実装 | High | POSTリダイレクトのテスト |
| 3 | should work with keep alive redirects | ❌ 未実装 | Low | fetch keepaliveテスト |
| 4 | should work when header manipulation headers with redirect | ❌ 未実装 | Medium | ヘッダー操作+リダイレクト |
| 5 | should be able to remove headers | ❌ 未実装 | High | ヘッダー削除テスト |
| 6 | should contain referer header | ❌ 未実装 | Medium | Refererヘッダー確認 |
| 7 | should not allow mutating request headers | ❌ 未実装 | Low | ヘッダー直接変更の禁止 |
| 8 | should work with requests without networkId | ❌ 未実装 | Low | CDP特殊ケース |
| 9 | should properly return navigation response when URL has cookies | ❌ 未実装 | Medium | Cookie付きナビゲーション |
| 10 | should stop intercepting | ❌ 未実装 | High | インターセプション無効化 |
| 11 | should show custom HTTP headers | ❌ 未実装 | High | カスタムヘッダー表示 |
| 12 | should work with redirect inside sync XHR | ❌ 未実装 | Medium | 同期XHR+リダイレクト |
| 13 | should work with custom referer headers | ❌ 未実装 | Medium | カスタムReferer |
| 14 | should be abortable | ❌ 未実装 | High | リクエスト中止テスト |
| 15 | should be abortable with custom error codes | ❌ 未実装 | Medium | カスタムエラーコード |
| 16 | should send referer | ❌ 未実装 | Medium | Referer送信確認 |
| 17 | should fail navigation when aborting main resource | ❌ 未実装 | High | メインリソース中止 |
| 18 | should work with redirects | ❌ 未実装 | High | リダイレクトチェーン |
| 19 | should work with redirects for subresources | ❌ 未実装 | Medium | サブリソースリダイレクト |
| 20 | should be able to abort redirects | ❌ 未実装 | Medium | リダイレクト中止 |
| 21 | should work with equal requests | ❌ 未実装 | Low | 同一リクエストの処理 |
| 22 | should navigate to dataURL and fire dataURL requests | ❌ 未実装 | Low | data:URLナビゲーション |
| 23 | should be able to fetch dataURL and fire dataURL requests | ❌ 未実装 | Low | data:URLフェッチ |
| 24 | should navigate to URL with hash and fire requests without hash | ❌ 未実装 | Medium | URLハッシュ処理 |
| 25 | should work with encoded server | ❌ 未実装 | Medium | URLエンコーディング |
| 26 | should work with badly encoded server | ❌ 未実装 | Low | 不正なエンコーディング |
| 27 | should work with missing stylesheets | ❌ 未実装 | Low | 存在しないスタイルシート |
| 28 | should not throw 'Invalid Interception Id' if request was cancelled | ❌ 未実装 | Medium | フレーム削除時のエラー処理 |
| 29 | should throw if interception is not enabled | ❌ 未実装 | High | インターセプション未有効時のエラー |
| 30 | should work with file URLs | ❌ 未実装 | Low | file://プロトコル |
| 31 | should not cache if cache disabled | ❌ 未実装 | Medium | キャッシュ無効時 |
| 32 | should cache if cache enabled | ❌ 未実装 | Medium | キャッシュ有効時 |
| 33 | should load fonts if cache enabled | ❌ 未実装 | Low | フォントキャッシュ |
| 34 | should work with worker | ❌ 未実装 | Low | Web Workerとの連携 |

### 2. Request.continue グループ

| # | TypeScript テスト名 | Ruby実装状況 | 優先度 | 備考 |
|---|---------------------|-------------|--------|------|
| 1 | should work | ❌ 未実装 | High | 基本的なcontinue |
| 2 | should amend HTTP headers | ❌ 未実装 | High | ヘッダー変更 |
| 3 | should redirect in a way non-observable to page | ❌ 未実装 | Medium | 透過的リダイレクト |
| 4 | should amend method | ❌ 未実装 | High | HTTPメソッド変更 |
| 5 | should amend post data | ❌ 未実装 | High | POSTデータ変更 |
| 6 | should amend both post data and method on navigation | ❌ 未実装 | Medium | メソッド+POSTデータ同時変更 |

### 3. Request.respond グループ

| # | TypeScript テスト名 | Ruby実装状況 | 優先度 | 備考 |
|---|---------------------|-------------|--------|------|
| 1 | should work | ❌ 未実装 | High | 基本的なrespond |
| 2 | should be able to access the response | ❌ 未実装 | Medium | レスポンスオブジェクト取得 |
| 3 | should work with status code 422 | ❌ 未実装 | Medium | 非標準ステータスコード |
| 4 | should redirect | ❌ 未実装 | Medium | モックリダイレクト |
| 5 | should allow mocking binary responses | ❌ 未実装 | High | バイナリレスポンス |
| 6 | should stringify intercepted request response headers | ❌ 未実装 | Medium | ヘッダー文字列化 |
| 7 | should indicate already-handled if intercept has been handled | ✅ 一部実装 | - | |

### 4. Request.resourceType グループ

| # | TypeScript テスト名 | Ruby実装状況 | 優先度 | 備考 |
|---|---------------------|-------------|--------|------|
| 1 | should work for document type | ❌ 未実装 | High | ドキュメントタイプ |
| 2 | should work for stylesheets | ❌ 未実装 | High | スタイルシートタイプ |

### 5. Cooperative Request Interception (experimental)

| # | TypeScript テスト名 | Ruby実装状況 | 優先度 | 備考 |
|---|---------------------|-------------|--------|------|
| 1 | should cooperatively abort by priority | ✅ 一部実装 | - | 例として実装済み |
| 2 | should cooperatively continue by priority | ✅ 一部実装 | - | 例として実装済み |
| 3 | should cooperatively respond by priority | ✅ 一部実装 | - | 例として実装済み |

## 必要なアセットファイル

### 既存アセット（利用可能）

- `spec/assets/empty.html`
- `spec/assets/one-style.html` / `spec/assets/one-style.css`
- `spec/assets/cached/one-style.html` / `spec/assets/cached/one-style.css`
- `spec/assets/frames/*.html`
- `spec/assets/pptr.png` (画像バイナリ)
- `spec/assets/csscoverage/Dosis-Regular.ttf` (フォント)
- `spec/assets/worker/worker.html` / `spec/assets/worker/worker.js`

### 新規作成が必要なアセット

以下のファイルは移植時に作成が必要な可能性がある:

```
spec/assets/global-var.html (存在確認要)
spec/assets/json-value.html
spec/assets/simple-form.html (POSTフォーム用)
```

## テストサーバーのルート設定

テストでは `server.set_route` を使用してカスタムルートを設定する。よく使われるパターン:

### 基本的なルート設定

```ruby
server.set_route('/simple-form.html') do |request, writer|
  writer.status = 200
  writer.add_header('content-type', 'text/html')
  writer.write('<form action="/post" method="POST"><input name="field" value="value"></form>')
  writer.finish
end
```

### POSTデータ取得

```ruby
server.set_route('/post') do |request, writer|
  body = request.body
  writer.status = 200
  writer.write("Received: #{body}")
  writer.finish
end
```

### リダイレクト設定

```ruby
server.set_redirect('/redirect', '/empty.html')

# または手動で
server.set_route('/redirect') do |request, writer|
  writer.status = 302
  writer.add_header('location', '/empty.html')
  writer.finish
end
```

### リクエスト待ち

```ruby
request_record = server.wait_for_request('/post')
expect(request_record.post_body).to eq('expected data')
```

## Ruby移植時のコード変換パターン

### 1. 基本的なテスト構造

**TypeScript:**
```typescript
it('should intercept', async () => {
  const {page, server} = await getTestState();
  await page.setRequestInterception(true);
  page.on('request', request => {
    // ...
    request.continue();
  });
  const response = await page.goto(server.EMPTY_PAGE);
  expect(response!.ok()).toBe(true);
});
```

**Ruby:**
```ruby
it 'should intercept', sinatra: true do
  page.request_interception = true
  page.on('request') do |request|
    # ...
    request.continue
  end
  response = page.goto(server_empty_page)
  expect(response.ok?).to eq(true)
end
```

### 2. リクエストフィルタリング

**TypeScript:**
```typescript
page.on('request', request => {
  if (request.url().includes('favicon.ico')) {
    request.continue();
    return;
  }
  // テストロジック
  request.continue();
});
```

**Ruby:**
```ruby
page.on('request') do |request|
  if request.url.include?('favicon.ico')
    request.continue
    next
  end
  # テストロジック
  request.continue
end
```

### 3. 非同期待機パターン

**TypeScript:**
```typescript
const [serverRequest] = await Promise.all([
  server.waitForRequest('/post'),
  page.click('button'),
]);
```

**Ruby:**
```ruby
server_request_promise = async_promise { server.wait_for_request('/post') }
server_request = await_with_trigger(server_request_promise) do
  page.click('button')
end
```

または単純に:

```ruby
# 直接実行（ブロッキング）
page.click('button')
server_request = server.wait_for_request('/post', timeout: 5)
```

### 4. ヘッダー操作

**TypeScript:**
```typescript
request.continue({
  headers: {
    ...request.headers(),
    foo: 'bar',
  },
});
```

**Ruby:**
```ruby
request.continue(
  headers: request.headers.merge('foo' => 'bar')
)
```

### 5. レスポンスモック

**TypeScript:**
```typescript
request.respond({
  status: 200,
  contentType: 'text/html',
  body: '<html></html>',
});
```

**Ruby:**
```ruby
request.respond(
  status: 200,
  content_type: 'text/html',
  body: '<html></html>'
)
```

## 注意事項

### 1. favicon.icoリクエストのフィルタリング

ブラウザは自動的にfavicon.icoをリクエストするため、テストではこれをフィルタリングする必要がある:

```ruby
page.on('request') do |request|
  if request.url.include?('favicon.ico')
    request.continue
    next
  end
  # テストロジック
end
```

### 2. data:URLの特殊処理

`http_request.rb`の`can_be_intercepted?`メソッドにより、data:URLはインターセプトできない:

```ruby
private def can_be_intercepted?
  !@url.start_with?('data:') && !@from_memory_cache
end
```

data:URL関連のテストはこの制約を考慮する必要がある。

### 3. file://プロトコルのテスト

file://プロトコルのテストには追加の設定が必要な場合がある。ローカルファイルのパスをURLに変換するヘルパーが必要:

```ruby
def path_to_file_url(path)
  "file://#{File.expand_path(path)}"
end
```

### 4. キャッシュ関連テスト

キャッシュテストには`page.cache_enabled=`の設定が必要:

```ruby
page.cache_enabled = false  # キャッシュ無効
page.cache_enabled = true   # キャッシュ有効
```

### 5. Workerとの連携

Workerテストでは`page.workers`や`page.on('workercreated')`イベントを使用する。

## 推奨移植順序

### Phase 1: 基本機能（High Priority）

1. `Request.continue` の基本テスト群
2. `Request.respond` の基本テスト群
3. `Request.resourceType` のテスト群
4. abort関連テスト
5. エラー処理テスト

### Phase 2: リダイレクト・ヘッダー操作（Medium Priority）

1. リダイレクト関連テスト
2. ヘッダー操作テスト
3. Refererヘッダーテスト
4. Cookie関連テスト

### Phase 3: 特殊ケース（Low Priority）

1. キャッシュ関連テスト
2. data:URL / file://テスト
3. Worker連携テスト
4. エンコーディングテスト

## ファイル構成の提案

現在の`spec/integration/request_interception_spec.rb`を以下のように拡張・再構成することを推奨:

```ruby
# spec/integration/request_interception_spec.rb

require 'spec_helper'

RSpec.describe 'request interception' do
  include_context 'with test state'

  describe 'Page.setRequestInterception' do
    it 'should intercept', sinatra: true do
      # 既存テスト
    end

    it 'should work when POST is redirected with 302', sinatra: true do
      # 新規テスト
    end

    # ... その他のテスト
  end

  describe 'Request.continue' do
    it 'should work', sinatra: true do
      # 新規テスト
    end

    # ... その他のテスト
  end

  describe 'Request.respond' do
    it 'should work', sinatra: true do
      # 新規テスト
    end

    # ... その他のテスト
  end

  describe 'Request.resourceType' do
    it 'should work for document type', sinatra: true do
      # 新規テスト
    end

    # ... その他のテスト
  end
end

# Cooperative Interceptionのテストは別ファイルか同一ファイル内に配置
RSpec.describe 'cooperative request interception' do
  include_context 'with test state'

  describe 'Page.setRequestInterception' do
    it 'should cooperatively abort by priority', sinatra: true do
      # テスト
    end

    # ... その他のテスト
  end
end
```

## 実装時のチェックリスト

- [ ] テスト名はPuppeteerのオリジナルと同じにする（英語）
- [ ] `sinatra: true`メタデータを付けてサーバー機能を有効化
- [ ] favicon.icoリクエストを適切にフィルタリング
- [ ] 非同期処理は`async_promise`/`await_with_trigger`パターンを使用
- [ ] タイムアウト設定を適切に行う（デフォルト7.5秒）
- [ ] エラーメッセージの検証は正規表現マッチングを使用
- [ ] 各テストは独立して実行可能であることを確認

## 参考リンク

- [Puppeteer Request Interception Documentation](https://pptr.dev/guides/network-interception)
- [CDP Fetch Domain](https://chromedevtools.github.io/devtools-protocol/tot/Fetch/)
- 元リポジトリ: https://github.com/puppeteer/puppeteer/tree/main/test/src
