# 使い方: bundle exec ruby fastlane/scripts/upload_creative_asset.rb [png] [live|edit] [参照名] [--only header|search]
# App Store の製品ページヘッダーと検索結果用の共通クリエイティブアセット（16:9 5244x2950 PNG）を
# Asset Library に上げ、iOS バージョン（live = 配信中 / edit = 編集中。既定は edit）の ja ローカライズの
# ヘッダーと検索結果に割り当てる。同じ枠に既存の割り当てがあれば先に消す（API は CREATE / DELETE / GET_INSTANCE のみ）。
# 安全領域は Apple のテンプレートどおり中央の帯（SPEC-REVIEW M7）。
# fastlane は未対応（2.241 時点、PR #30442 が未マージ）なので App Store Connect API を直接呼ぶ。
# API キーは Fastfile と同じもの（SPEC-REVIEW J3）。
require 'spaceship'; require 'json'; require 'net/http'
j = JSON.parse(File.read(ENV["AGNORIA_ASC_API_KEY_JSON"] || File.expand_path("~/git/runrun-ios/fastlane/api_key.json")))
TOK = Spaceship::ConnectAPI::Token.create(key_id: j['key_id'], issuer_id: j['issuer_id'], key: j['key']).text
BASE = "https://api.appstoreconnect.apple.com/v1/"
def call(method, path, body = nil)
  uri = URI(BASE + path)
  req = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'PATCH' => Net::HTTP::Patch, 'DELETE' => Net::HTTP::Delete }[method].new(uri)
  req['Authorization'] = "Bearer #{TOK}"; req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }
  data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  raise "#{method} #{path} -> #{res.code}: #{data['errors'].inspect}" unless res.code.start_with?('2')
  data
end
# 使い方 2: --assign <imageId> [live|edit] で、Asset Library にある画像を割り当て直すだけ
# --only header|search で片方の枠だけに割り当てる（既定は両方）
only = nil
if (i = ARGV.index("--only"))
  only = ARGV[i + 1]; ARGV.slice!(i, 2)
end
assign_only = ARGV[0] == "--assign" ? ARGV[1] : nil
file = (assign_only ? nil : ARGV[0]) || File.expand_path("../creative/universal-16x9-5244x2950.png", __dir__)
target = (assign_only ? ARGV[2] : ARGV[1]) || "edit"
reference = ARGV[3] || ARGV[2] || "Agnoria 共通アセット"
bytes = assign_only ? "" : File.binread(file)
app_id = "6823061416"
if assign_only
  img = { 'id' => assign_only }
else
# 1) 予約
img = call('POST', 'appAssetLibraryImages', { data: { type: 'appAssetLibraryImages',
  attributes: { category: 'CREATIVE_ASSETS', fileName: File.basename(file), fileSize: bytes.bytesize, referenceName: reference },
  relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: app_id } } } } })['data']
puts "reserved image #{img['id']} state=#{img.dig('attributes','state')}"
# 2) アップロード
(img.dig('attributes', 'uploadOperations') || []).each do |op|
  uri = URI(op['url']); req = Net::HTTP::Put.new(uri)
  (op['requestHeaders'] || []).each { |h| req[h['name']] = h['value'] }
  req.body = bytes[op['offset'], op['length']]
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  raise "upload chunk failed #{res.code}" unless res.code.start_with?('2')
  print "."
end
puts " uploaded"
# 3) 完了を通知
call('PATCH', "appAssetLibraryImages/#{img['id']}", { data: { type: 'appAssetLibraryImages', id: img['id'], attributes: { uploaded: true } } })
# 4) 処理待ち
state = nil
30.times do
  state = call('GET', "appAssetLibraryImages/#{img['id']}")['data'].dig('attributes', 'state')
  puts "state=#{state}"
  break unless %w[AWAITING_UPLOAD UPLOAD_COMPLETE].include?(state)
  sleep 10
end
raise "image not ready: #{state}" if %w[AWAITING_UPLOAD UPLOAD_COMPLETE FAILED].include?(state)
end
# 5) 対象バージョンの ja ローカライズに割り当て（同じ枠の既存の割り当ては消してから）
assign = lambda do |image_id|
  Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: j['key_id'], issuer_id: j['issuer_id'], key: j['key'])
  app = Spaceship::ConnectAPI::App.find("com.himatsubu.Agnoria")
  ver = target == "live" ? app.get_live_app_store_version(platform: "IOS", includes: "appStoreVersionLocalizations") :
                           app.get_edit_app_store_version(platform: "IOS", includes: "appStoreVersionLocalizations")
  raise "version not found (#{target})" unless ver
  loc = ver.app_store_version_localizations.find { |l| l.locale == 'ja' }
  puts "target #{ver.version_string} (#{ver.app_store_state}) loc=#{loc.id}"
  existing = {}
  (call('GET', "appAssetLibraries/#{app_id}/images?filter[category]=CREATIVE_ASSETS&limit=50")['data'] || []).each do |im|
    (call('GET', "appAssetLibraryImages/#{im['id']}/placements")['data'] || []).each do |pl|
      d = call('GET', "appAssetLibraryPlacements/#{pl['id']}?include=appStoreVersionLocalization")['data']
      next unless d.dig('relationships', 'appStoreVersionLocalization', 'data', 'id') == loc.id
      existing[d.dig('attributes', 'placementType')] = pl['id']
    end
  end
  types = { "header" => %w[PRODUCT_PAGE_HEADER_ASSET], "search" => %w[APP_STORE_SEARCH_RESULTS_ASSET] }[only] ||
          %w[PRODUCT_PAGE_HEADER_ASSET APP_STORE_SEARCH_RESULTS_ASSET]
  types.each do |pt|
    if (old = existing[pt])
      call('DELETE', "appAssetLibraryPlacements/#{old}")
      puts "deleted old placement #{pt}: #{old}"
    end
    pl = call('POST', 'appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements', attributes: { placementType: pt },
      relationships: { image: { data: { type: 'appAssetLibraryImages', id: image_id } },
                       appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } })['data']
    puts "placement #{pt}: #{pl['id']} state=#{pl.dig('attributes','state')}"
  end
end
assign.call(img['id'])
