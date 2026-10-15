# 使い方: bundle exec ruby fastlane/scripts/upload_creative_asset.rb [png]
# App Store の製品ページヘッダーと検索結果用の共通クリエイティブアセット（16:9 5244x2950 PNG）を
# Asset Library に上げ、編集中の iOS バージョンの ja ローカライズのヘッダーと検索結果に割り当てる。
# fastlane は未対応（2.241 時点、PR #30442 が未マージ）なので App Store Connect API を直接呼ぶ。
# API キーは Fastfile と同じもの（SPEC-REVIEW J3）。
require 'spaceship'; require 'json'; require 'net/http'
j = JSON.parse(File.read(ENV["AGNORIA_ASC_API_KEY_JSON"] || File.expand_path("~/git/runrun-ios/fastlane/api_key.json")))
TOK = Spaceship::ConnectAPI::Token.create(key_id: j['key_id'], issuer_id: j['issuer_id'], key: j['key']).text
BASE = "https://api.appstoreconnect.apple.com/v1/"
def call(method, path, body = nil)
  uri = URI(BASE + path)
  req = { 'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post, 'PATCH' => Net::HTTP::Patch }[method].new(uri)
  req['Authorization'] = "Bearer #{TOK}"; req['Content-Type'] = 'application/json'
  req.body = JSON.generate(body) if body
  res = Net::HTTP.start(uri.host, 443, use_ssl: true) { |h| h.request(req) }
  data = res.body.to_s.empty? ? {} : JSON.parse(res.body)
  raise "#{method} #{path} -> #{res.code}: #{data['errors'].inspect}" unless res.code.start_with?('2')
  data
end
file = ARGV[0] || File.expand_path("../creative/universal-16x9-5244x2950.png", __dir__)
bytes = File.binread(file)
app_id = "6823061416"
# 1) 予約
img = call('POST', 'appAssetLibraryImages', { data: { type: 'appAssetLibraryImages',
  attributes: { category: 'CREATIVE_ASSETS', fileName: File.basename(file), fileSize: bytes.bytesize, referenceName: 'Agnoria 1.0 共通アセット' },
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
# 5) バージョン 1.0 の ja ローカライズに割り当て
Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(key_id: j['key_id'], issuer_id: j['issuer_id'], key: j['key'])
app = Spaceship::ConnectAPI::App.find("com.himatsubu.Agnoria")
ver = app.get_edit_app_store_version(platform: "IOS", includes: "appStoreVersionLocalizations")
loc = ver.app_store_version_localizations.find { |l| l.locale == 'ja' }
%w[PRODUCT_PAGE_HEADER_ASSET APP_STORE_SEARCH_RESULTS_ASSET].each do |pt|
  pl = call('POST', 'appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements', attributes: { placementType: pt },
    relationships: { image: { data: { type: 'appAssetLibraryImages', id: img['id'] } },
                     appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } })['data']
  puts "placement #{pt}: #{pl['id']} state=#{pl.dig('attributes','state')}"
end
