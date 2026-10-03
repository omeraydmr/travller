# Stubly · iOS

SwiftUI, iOS 17+. Türkiye'den yurt dışına giden gruplar için ilk sürüm.

## Kurulum

```bash
brew install xcodegen
cd ios
xcodegen generate
open Stubly.xcodeproj
```

`Stubly.xcodeproj` üretilen bir dosyadır ve repoya eklenmez; yapı `project.yml` içinde tanımlıdır.
Yeni dosya eklediğinde `xcodegen generate` komutunu tekrar çalıştır.

Debug derlemeleri staging sunucusuna, Release derlemeleri production sunucusuna bağlanır
(`Config/Debug.xcconfig`, `Config/Release.xcconfig`; anahtarlar `Config/Secrets.xcconfig`, git'e girmez).

## Dağıtım (cihaza kurulum)

```bash
cd ios
scripts/release.sh            # Release arşivi + kayıtlı cihazlara kurulabilir IPA → ios/dist/Stubly.ipa
scripts/release.sh --install  # ayrıca bağlı iPhone'a kurar ve açar
```

IPA geliştirme imzasıyla çıkar (`Config/ExportOptions.plist`, `method: debugging`); yalnızca Apple Developer
hesabında kayıtlı cihazlara kurulur. Yeni bir cihaz eklemek için cihazı Mac'e bağlayıp Xcode'da bir kez çalıştırmak
yeterli; otomatik imzalama cihazı profile ekler.

## iCloud paylaşımı (CloudKit)

Ekip paylaşımı ve eşitleme Apple'ın iCloud altyapısını kullanır; ayrı bir sunucu yoktur.
Gerçek cihazda çalıştırmak için bir kez:

1. Xcode → Stubly hedefi → *Signing & Capabilities* → kendi geliştirici ekibini seç.
2. *iCloud* yeteneğinde **CloudKit** işaretli olmalı; konteyner `iCloud.com.omeraydemir.stubly`
   (farklı bir kimlik kullanırsan `CloudConfig.containerIdentifier` ve `project.yml`'i güncelle).
3. İlk çalıştırmada CloudKit geliştirme şeması kendiliğinden oluşur (`Trip` kaydı: `payload`, `name`, `updatedAt`).
   Yayından önce CloudKit Console'da şemayı **Production**'a taşı.

Ekipteki "Sadece görür" / "Düzenleyebilir" yetkisi, paylaşım katılımcısının iCloud iznine de uygulanır
(`SharePermissions`): katılan kişi kendini ekibe eklerken iCloud kullanıcı kimliği (`Member.cloudUserID`) yazılır;
sahip yetkiyi değiştirince `CloudSync.applyPermissions` `CKShare` katılımcısını salt okunur/okuma-yazma yapar.
Kimliği bilinmeyen (elle eklenmiş) kişilerde yetki yalnızca uygulamada uygulanır.

iCloud'a giriş yapılmamış cihazda uygulama yalnızca yerel çalışır. Eşitleme iki kopyayı öğe bazında birleştirir;
silinen öğeler `tombstones` ile işaretlenir ve geri gelmez. Kapak fotoğrafı `Trip` kaydında `cover` varlığı,
makbuzlar ise seyahate bağlı `Photo` kayıtları (`name`, `kind`, `asset`) olarak eşitlenir.

Anlık güncelleme için *Push Notifications* yeteneği (`aps-environment`) ve *Background Modes → Remote notifications*
gerekir; ikisi de `project.yml`'de tanımlı. Uygulama CloudKit veritabanı aboneliklerini ilk açılışta kurar.

## İlk açılış ve hesap

İlk açılışta `OnboardingView` tanıtımı, profil oluşturmayı, kısa anketi (`TravelPreferences`) ve iCloud durumunu gösterir.
Ayrı bir kullanıcı adı/şifre yoktur: hesap, cihazdaki profil (`TripStore.me`) ile cihazın iCloud kimliğidir; iCloud
açıksa kimlik profile (`Member.cloudUserID`) yazılır ve ekip paylaşımında yetki eşlemesi bunu kullanır.
Profil > "Tanıtımı ve anketi yeniden göster" ile tekrar açılır.

## Canlı uçuş kartı (Live Activity)

`StublyWidgets` uzantısı (`Widgets/`) kilit ekranı ve Dynamic Island görünümünü çizer; ortak
`FlightActivityAttributes` tipi `Shared/` klasöründedir. Uzantının paket kimliği `com.omeraydemir.stubly.widgets`;
imzalarken uygulamayla aynı ekibi seç. Kart push'suz, planlanmış saatlerle uygulama içinden güncellenir; güncel kapı ve rötar için havayolunun uygulaması kullanılır.

Aynı uzantıda ana ekran widget'ı (`TripCountdownWidget`) da var. Uygulama özeti App Group klasörüne
(`group.com.omeraydemir.stubly`) yazar, widget oradan okur; iki hedefte de *App Groups* yeteneği açık olmalı.

## Bağlantılar

`stubly://trip/<seyahat-id>?section=money` biçimindeki adres ilgili seyahatin sekmesini açar
(`plan`, `money`, `packing`, `visa`, `crew`). Bildirimler aynı bilgiyi `userInfo` içinde taşır.

`Support/Info.plist` ve `Support/Stubly.entitlements` `xcodegen generate` ile üretilir.

## Yapı

```
ios/
├── project.yml                 XcodeGen proje tanımı
├── Packages/StublyKit       Saf Swift domain katmanı (UI yok, testli)
│   ├── Models                  Trip, Member, Stop, Expense, PackingItem…
│   ├── Settlement              Masraf bölme + borç sadeleştirme
│   ├── Budget                  Kategori bütçesi ve harcama temposu
│   ├── VisaRules               TC pasaportu için giriş kuralları + değerlendirme
│   ├── Packing                 Kural tabanlı valiz önerileri (priz tipi vb.)
│   ├── Geo                     Mesafe, yürüme süresi, rota sıralama
│   └── MoneyParser, TurkishGrammar, Countdown
└── Stubly                   Uygulama
    ├── DesignSystem            Kartpostal token'ları ve bileşenleri
    ├── Store                   TripStore (cihazda JSON)
    └── Features                Trips, TripDetail, Plan, Money, Packing, Visa, Crew
```

## Diller

Kaynak dil Türkçe, ikinci dil İngilizce. Arayüz metinleri `Stubly/Resources/Localizable.xcstrings` ve
`Widgets/Localizable.xcstrings` String Catalog'larında. Yeni metin eklerken SwiftUI'da doğrudan `Text("…")`
kullan; `String` dönen yerlerde `String(localized: "…")` yaz. Çeviriyi Xcode'da catalog üzerinden ya da
`xcodebuild -exportLocalizations` / `-importLocalizations` ile ekle.

StublyKit'in ürettiği metinler (vize notları, valiz ve gidiş öncesi önerileri, bildirim metinleri) henüz yalnızca Türkçe.

## Test

```bash
swift test --package-path ios/Packages/StublyKit
```

CI (`.github/workflows/ios.yml`) her PR'da paket testlerini çalıştırır ve uygulamayı simülatör için derler.

## Vize verisi

`VisaRules.swift` elle derlenmiş bir veri setidir. Yayından önce ve düzenli aralıklarla
[konsolosluk.gov.tr](https://www.konsolosluk.gov.tr) üzerinden doğrulanmalı; doğrulandıkça `lastReviewed` güncellenmeli.
