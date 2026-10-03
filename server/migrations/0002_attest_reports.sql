-- App Attest ile onaylanmış cihaz anahtarları: yalnızca gerçek Stubly uygulaması katkı ve bildirim gönderebilsin.
-- Kişi bilgisi yok; anahtar kimliği cihazdaki uygulama kurulumuna özeldir.
CREATE TABLE IF NOT EXISTS attested_keys (
  key_id TEXT PRIMARY KEY,
  public_key TEXT NOT NULL, -- SPKI, base64
  counter INTEGER NOT NULL DEFAULT 0,
  environment TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- Yanlış, uygunsuz ya da spam yer bildirimleri: kişi başına bir bildirim.
CREATE TABLE IF NOT EXISTS reports (
  place_id INTEGER NOT NULL REFERENCES places (id),
  contributor TEXT NOT NULL,
  reason TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (place_id, contributor)
);
