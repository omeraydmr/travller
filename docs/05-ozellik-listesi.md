# 05 · Özellik listesi: ne var, ne eksik, sırada ne var

Durum: ✅ yapıldı (CI'da derleniyor, testli mantık) · 🟡 kısmen · ⬜ yok.
Gerçek cihaz (iPhone 15) testi sürüyor; iCloud paylaşım/yetki akışları iki hesapla henüz denenmedi.

## 1. Yapılanlar

| Alan | Özellik | Durum | Not |
|---|---|---|---|
| Ana ekran | Kare bilet kartlı deste, yörüngede kaydırma, arka kartlar bulanık | ✅ | Bu turda performans için yeniden düzenlendi |
| Ana ekran | Kapak fotoğrafı, fotoğraftan dinamik renk | ✅ | |
| Ana ekran | Vize / bütçe / valiz özet kutuları | ✅ | |
| Çok şehir | Seyahate 4 ek şehre kadar ekleme; ana ekranda kart genişler, koçan şehir şehir bölünür ve şehir eklenince koçanlar animasyonla birleşir | ✅ | Geçiş günü varılan şehre sayılır, planda "geçiş günü" olarak işaretlenir. Öneri, harita, otomatik plan, hava ve bildirim o günün şehrine göre; vize ülke ülke (Schengen 90/180 yalnızca Schengen günlerini sayar) |
| Yeni seyahat | Canlı bilet önizlemesi, 3B "PASSED" mühür animasyonu | ✅ | |
| Plan | Gün çipleri, harita, numaralı duraklar, sürükle-bırak, başka güne taşıma | ✅ | |
| Plan | Yer arama + harita önizleme | ✅ | |
| Plan | Uçuşlar kartı: elle ekleme/düzenleme/silme, biletten içe aktarma | ✅ | Saatler havalimanının yerel saatiyle girilir; tanınan kodda şehir ve saat dilimi kendiliğinden dolar. Uçuş silmeleri eşitlemede geri gelmez |
| Plan | Açılış saatleri (OSM), uyarı ve tek dokunuşla düzeltme | ✅ | |
| Plan | Çevrimdışı harita görüntüleri | ✅ | Yüksek çözünürlüklü kayıt; tam ekranda iki parmakla 4 kata kadar yakınlaştırma, çift dokunuş; internet varken de "göz" düğmesiyle önizleme |
| Bütçe | Masraf ekleme/düzenleme, hesap makinesi tuşları, kategoriler, donut | ✅ | |
| Bütçe | Döviz (ECB kuru), para birimi dağılımı | ✅ | |
| Bütçe | Makbuz fotoğrafı, tutar okuma (OCR), kalem kalem bölme | ✅ | |
| Bütçe | Borç sadeleştirme, transferler | ✅ | |
| Valiz | Kişiye atama, ilerleme, hava durumuna göre öneriler | ✅ | |
| Vize | Pasaport kartları, vize durumu, pasaport geçerlilik uyarısı | ✅ | Kural tablosu elle tutuluyor |
| Vize | Schengen 90/180 hesaplayıcı: kullanılan gün, 180 günlük şerit, aşım uyarısı, en geç çıkış ve en erken giriş önerisi | ✅ | |
| Ekip | iCloud ile paylaşım, eşitleme, anlık güncelleme, değişiklik bildirimi | ✅ | |
| Ekip | Kapak/makbuz fotoğrafı eşitleme | ✅ | |
| Bildirim | Valiz, uçuş, günün planı, durak hatırlatmaları; dokununca ilgili sekme | ✅ | |
| Uçuş | Kapı, koltuk ve saatler elle ya da biletten; kilit ekranında geri sayım kartı | ✅ | Canlı rötar/kapı takibi kaldırıldı: havayolunun uygulaması bunu zaten yapıyor |
| Uçuş | Kilit ekranı ve Dynamic Island canlı kartı | ✅ | Push'suz güncelleme |
| Widget | Sıradaki seyahate kalan gün, günün sıradaki durağı | ✅ | |
| İlk açılış | Tanıtım, profil ("hesap") oluşturma, 3 soruluk anket, iCloud bağlantı durumu ve hatırlatma izni | ✅ | Ayrı şifre yok: hesap = cihazdaki profil + iCloud kimliği (`Member.cloudUserID`). Anketteki ilk ilgi alanı seyahat açılınca ilk sekmeyi belirler. Profil'den yeniden gösterilebilir |
| Diğer | Hakkında, atıflar, tüm seyahatleri silme | ✅ | Uygulama boş başlar; örnek veri yok |

## 2. İlk plandan eksik kalanlar (02 · Özellik Seti'ne göre)

| Özellik | Durum | Not |
|---|---|---|
| Anılar: fotoğrafları tarih/konuma göre toplama, öbekleme, haritada gösterme | ✅ | Yeni "Anılar" sekmesi: anlar, durakla eşleme, harita, kartpostal paylaşma; tamamen cihazda |
| Fotoğrafları tam ekran açma; ortak albüm (karşılıklı onay) | ✅ | Anılardaki fotoğraflar tam ekran, kaydırarak ve yakınlaştırarak açılır. Ortak albüm en az iki kişi onay verince açılır, yalnızca onay verenler görür; seyahat günlerindeki fotoğraflar (ekran görüntüleri hariç) 2048 px, konum bilgisi olmadan iCloud ile paylaşılır. Onay geri çekilince kişinin fotoğrafları kalkar |
| Konaklama (otel) kayıtları | ✅ | Plan sekmesinde kart; gün planı ve harita otelden başlar; giriş/çıkış bildirimi; konaklamasız gece uyarısı |
| Rezervasyon içe aktarma (PDF, ekran görüntüsü, Wallet biniş kartı) | ✅ | PDF ve ekran görüntüsünden uçuş + otel; Wallet `.pkpass` biniş kartından uçuş, saat ve koltuk (anlamsal etiketler, yoksa kart alanları). Hepsi cihazda |
| Duraklar arası ulaşım satırı (yürüme/tram/taksi süreleri) | ✅ | Apple Haritalar'dan yürüme ve toplu taşıma süresi; otelden ilk durağa da |
| Rota optimizasyonu | ✅ | Önce açılış saatleri ve durağa verilmiş saatler (kapalıyken/geç varılan durak en aza), sonra en kısa yürüyüş; sabah oteli başlangıç. Saatler değiştirilmez, yalnızca sıra |
| "Fikirler" havuzu (güne atanmamış yerler) | ✅ | Plan sekmesinde; "Güne ekle", duraktan "Fikirlere taşı" |
| Yer önerileri ve otomatik rota | ✅ | Fikirler kartında "Yer öner": Wikipedia konuma göre arama, son 30 günde en çok okunan yerler (kale, müze, seyir noktası, semt). "Otomatik rota": fikirleri yakınlığa, açılış saatlerine, otele ve varış/dönüş uçuşlarına göre günlere dağıtır, sıralar ve saat verir; önizleme, sığmayanlar listesi ve geri al |
| Şehir seçimi ve şehirle sınırlı yer arama | ✅ | Yeni seyahatte şehir serbest metin değil: seçili ülkenin şehirleri Apple Haritalar'dan aranır (otomatik tamamlama ülke bölgesiyle sınırlı), konum kaydedilir. Durak eklemede ve "Yer öner"deki arama çubuğunda sonuçlar şehir çevresi ve ülkeyle sınırlanır, sorguya benzerlik + merkeze yakınlıkla sıralanır, mesafe gösterilir; Türkçe yazım (ı, "kulesi", "manastır") İngilizce karşılıklarıyla da aranır |
| Pasaport türüne göre vize | ✅ | Umuma mahsus (bordo), hususi (yeşil), hizmet (gri), diplomatik (siyah): kişi ve ilk kurulum ekranında seçilir, pasaport kartı türün renginde. Kurallar Dışişleri Bakanlığı listesinden türe göre (ör. yeşil/gri/diplomatik Schengen'de 90/180 vizesiz, İngiltere/ABD/Kanada hepsine vizeli, Karadağ bordoya 30 gün, Bulgaristan gri/diplomatiğe 30 gün); Schengen 90/180 hesabı her türde çalışır; valiz ve yola çıkış listesi ekipteki türlere bakar |
| Topluluk öneri havuzu ("Gezginler seçti") | ✅ | Seyahat bitince Anılar'da onay kartı: yerlere 👍/👎, istenmeyeni gizleme, fotoğrafla doğrulama. Onaylanırsa yalnızca yer adı/konumu/türü/oy ve aynı gün art arda gidilen yer çiftleri Stubly sunucusuna (Cloudflare D1, gizli) gider; kişi, tarih, not, ekip gitmez. En az 3 farklı gezginin gittiği yerler "Yer öner"de rozetle önce, "X sonrası gezginler genelde" bölümüyle çıkar. Cihaz kimliği sunucuda tuzlanıp özetlenir; günlük kota var |
| Vize başvuru takibi: randevu, belge listesi, durum | ✅ | Durum hapları, randevu tarihi ve yeri, kalıcı belge listesi; randevu öncesi bildirim; ekiple eşitlenir |
| Belge kasası (pasaport, sigorta, bilet PDF'leri) | ✅ | Vize sekmesinde; dosya/fotoğraf/kamera, önizleme, kişiye bağlama, "yalnızca bu cihazda"; diğerleri iCloud ile eşitlenir |
| Settle up: IBAN kopyala, "ödendi" işaretle, özet paylaş | ✅ | Kişi kartında IBAN (doğrulamalı), ödeme sorusunda "IBAN'ı kopyala", metin özeti paylaşma |
| Roller (düzenleyebilir / yalnızca görüntüler) | ✅ | "Sadece görür" yetkisinde seyahat salt okunur; yetkiyi yalnızca sahip değiştirir. Yetki iCloud paylaşım iznine de yansır (sunucu tarafında zorlanır); kişi davetle katılıp kendini eklediyse eşleşir. İki iCloud hesabıyla gerçek cihazda henüz denenmedi |
| Aktivite akışı ("Elif durak ekledi") | ✅ | Ekip sekmesinde "Son hareketler" (ekipten gelen değişiklikler, cihazda) |
| Profil: gezilen ülkeler | ✅ | Ana sayfada avatar → profil: kendi bilgilerin, IBAN, gezilen ülkeler (otomatik + elle), dünya yüzdesi; Hakkında buraya taşındı |

## 3. Yeni adaylar

Listedeki tüm adaylar yapıldı:

| # | Özellik | Not |
|---|---|---|
| F | Tax-free iade takibi | Bütçe sekmesinde; ülkenin KDV oranından tahmini iade, durum takibi, dönüş günü gümrük hatırlatması |
| G | Gidiş öncesi kontrol listesi | Valiz sekmesinde; harç pulu, eSIM, kartlar, sigorta, vize, check-in… son günü gelince sabah bildirimi |
| K | Acil durum kartı | Vize sekmesinde; ülkenin acil numaraları, konsolosluk çağrı merkezi, cihazda kalan sağlık bilgileri, yerel dilde alerji kartı |
| L | Paylaşılabilir seyahat özeti | Anılar sekmesinde; gün, durak, rota, harcama ve öne çıkanlar görsel olarak paylaşılır (HealthKit adım sayısı yok) |
| M | ~~Canlı kartı sunucu push'u ile güncelleme~~ | Kaldırıldı (uçuş durumu servisiyle birlikte); kart cihazda planlanmış saatlerle çalışır |
| N | İngilizce yerelleştirme | Arayüz ve StublyKit metinleri (valiz ve yola çıkış önerileri, uçuş durumu, bildirimler, açılış saatleri, vize notları) İngilizce. Öneriden gelen ve düzenlenmemiş yola çıkış maddeleri cihaz dilinde gösterilir; Dışişleri'nin Türkçe resmî vize metni yalnızca Türkçe arayüzde |

Daha önce yapılanlar (ayrıntı §1 ve §2'de): B Anılar · C Biletten doldurma (PDF, ekran görüntüsü, Wallet `.pkpass`) ·
D Schengen 90/180 · E Vize randevu ve belge takibi · H Hesaplaşma (IBAN, ödendi, özet) ·
I Konaklama ve giriş/çıkış bildirimleri · J Duraklar arası toplu taşıma süreleri.
A (cihazda test turu + TestFlight) listeden çıkarıldı: iPhone 15'te sürüyor.

## 4. Teknik borç / kalite

- Gerçek cihazda performans ölçümü (Instruments: SwiftUI, Time Profiler, Hangs).
- Uygulama hedefi için UI testleri ve ekran görüntüsü testleri yok; yalnızca StublyKit birim testleri var.
- Çökme raporlama yok.
- Vize kural tablosu (`visa_rules.tsv`, ~195 ülke) Dışişleri sayfasından üretildi; sayfa değişince yeniden üretilmeli (kaynak ve tarih uygulamada gösteriliyor).

## 5. Performans turu (bu değişiklik)

Ana ekranın kaydırırken kasmasının olası nedenleri ve yapılanlar:

| Sorun | Düzeltme |
|---|---|
| Arka plan ışığı: 440 pt daire, 100 pt bulanıklık; odak değişince 0,6 sn boyunca her karede yeniden süzülüyordu (tüm ekranlarda) | Radyal gradyan; aynı görünüm, bulanıklık yok |
| Her kart her karede baştan kuruluyordu | Kart `Equatable`; kaydırırken yalnızca konumu değişiyor |
| Kart içeriği çok katmanlı (fotoğraf, tarama deseni, metinler) ve üstüne bulanıklık + iki gölge | İçerik `drawingGroup` ile tek dokuya çiziliyor; gölge yalnızca basit şeklin gölgesi |
| Bulanıklık yarıçapı her karede değişiyordu | Yarım puanlık adımlara yuvarlandı |
| Karttaki geri sayım hapı materyal (arka plan bulanıklığı) kullanıyordu | Düz yarı saydam zemin |
| Bilet çentiği her çizimde boolean yol işlemiyle (`subtracting`) hesaplanıyordu | Yol doğrudan çiziliyor |
| Kartlar 1400 px JPEG'i ana iş parçacığında açıp her karede ölçekliyordu | ImageIO ile 900 px'e küçültülmüş, önceden çözülmüş görsel; açılışta arka planda hazırlanıyor |
| Baskın renk tam boy görüntüden hesaplanıyordu | 64 px'lik görselden |
| Yeni seyahat formunda 12 MP fotoğraf her tuş vuruşunda yeniden çiziliyordu | Önizleme küçültülüyor |
| `softShadow` gölgeyi her alt görünüme ayrı uyguluyordu (22 yerde) | Önce tek katmana birleştiriliyor |
| Her değişiklikte tüm seyahatler JSON olarak ana iş parçacığında diske yazılıyordu | 300 ms toplanıp arka planda, sırayla yazılıyor; arka plana geçerken bekleyen yazma bitiriliyor |

## 6. Genel performans turu

| Alan | Sorun | Düzeltme |
|---|---|---|
| Tüm kartlar (`tray`, `ModuleCard`, kutucuklar, hap düğmeler) | Gölge tüm içeriği tek katmana birleştirip hesaplıyordu; içinde kaydırma görünümü olan büyük kartlarda her değişiklikte büyük ekran dışı çizim | `cardBackground`: gölge yalnızca zemin şeklinden; içerik katmana birleştirilmiyor |
| Plan haritası | Canlı harita gölge için katmana birleştiriliyordu | Gölge harita altındaki şekilden |
| Plan | Seçili günün durakları, mesafe, açılış saati durumları ve önerileri gövde başına 5–10 kez yeniden hesaplanıyordu; açılış saatleri her seferinde metinden ayrıştırılıyordu | Gün planı gövde başına bir kez hesaplanıyor; açılış saati ayrıştırması önbellekli |
| Plan · gün çipleri | Her çip kendi durak sayısını tüm duraklardan süzüyordu | Sayılar bir kez sözlükte |
| Çevrimdışı harita | İnternet yokken görüntü ve kayıt tarihi her çizimde diskten okunuyordu | Bellek önbelleği |
| Bütçe | Borç sadeleştirme bir çizimde 4–5 kez, para birimi dağılımı iki kez hesaplanıyordu | Birer kez |
| Para birimi menüsü | Her satır için `NumberFormatter` kuruluyordu | Sembol önbelleği |
| Masraf ekranı | Tuş takımında her basışta tam boy makbuz fotoğrafı 44 pt'ye ölçekleniyordu | Küçük kopya |
| Bildirimler | Her düzenlemede tüm seyahat bildirimleri silinip yeniden ekleniyordu | Plan değişmediyse dokunulmuyor |
