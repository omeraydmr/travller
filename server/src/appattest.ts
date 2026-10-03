// Apple App Attest doğrulaması: uygulamanın gerçek, değiştirilmemiş Stubly olduğunu kanıtlar.
//  1. Kayıt: cihaz bir anahtar üretir, Apple onu onaylar (attestation). Sertifika zinciri Apple App Attestation kök
//     sertifikasına kadar doğrulanır; sunucunun verdiği tek kullanımlık challenge, uygulama kimliği ve anahtar
//     kimliği karşılaştırılır; açık anahtar saklanır.
//  2. Her istek: cihaz istek gövdesini bu anahtarla imzalar (assertion); imza ve artan sayaç kontrol edilir.
// Ayrıntı: https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server

/** Apple App Attestation Root CA (P-384, 2045'e kadar). https://www.apple.com/certificateauthority/ */
export const APPLE_APP_ATTEST_ROOT =
  "MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYwJAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwKQXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNaFw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlvbiBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9ybmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYwCgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijVoyFraWVIyd/dganmrduC1bmTBGwD";

const subtle = crypto.subtle;

export function base64ToBytes(text: string): Uint8Array {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

export function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(...parts: Uint8Array[]): Promise<Uint8Array> {
  const total = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) { total.set(part, offset); offset += part.length; }
  return new Uint8Array(await subtle.digest("SHA-256", total));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

// MARK: - CBOR (yalnızca attestation/assertion nesnelerinin kullandığı türler)

type CBOR = number | Uint8Array | string | CBOR[] | Map<CBOR, CBOR>;

export function decodeCBOR(bytes: Uint8Array): CBOR {
  let offset = 0;
  function length(info: number): number {
    if (info < 24) return info;
    const size = { 24: 1, 25: 2, 26: 4 }[info as 24 | 25 | 26];
    if (!size) throw new Error("cbor length");
    let value = 0;
    for (let i = 0; i < size; i++) value = value * 256 + bytes[offset++];
    return value;
  }
  function item(): CBOR {
    const head = bytes[offset++];
    const major = head >> 5, info = head & 31;
    const n = length(info);
    switch (major) {
      case 0: return n;
      case 1: return -1 - n;
      case 2: { const v = bytes.slice(offset, offset + n); offset += n; return v; }
      case 3: { const v = new TextDecoder().decode(bytes.slice(offset, offset + n)); offset += n; return v; }
      case 4: return Array.from({ length: n }, () => item());
      case 5: { const m = new Map<CBOR, CBOR>(); for (let i = 0; i < n; i++) { const k = item(); m.set(k, item()); } return m; }
      default: throw new Error("cbor type");
    }
  }
  return item();
}

// MARK: - DER / X.509 (doğrulama için gereken alanlar)

interface Node { tag: number; start: number; header: number; length: number; bytes: Uint8Array }

function readNode(bytes: Uint8Array, start: number): Node {
  const tag = bytes[start];
  let length = bytes[start + 1], header = 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[start + 2 + i];
    header += count;
  }
  return { tag, start, header, length, bytes: bytes.slice(start, start + header + length) };
}

function children(node: Node): Node[] {
  const result: Node[] = [];
  let offset = node.header;
  while (offset < node.bytes.length) {
    const child = readNode(node.bytes, offset);
    result.push(child);
    offset += child.header + child.length;
  }
  return result;
}

const content = (node: Node) => node.bytes.slice(node.header);

function oid(node: Node): string {
  const b = content(node);
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let value = 0;
  for (const byte of b.slice(1)) {
    value = value * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) { parts.push(value); value = 0; }
  }
  return parts.join(".");
}

export interface Certificate {
  tbs: Uint8Array;
  signatureAlgorithm: string;
  signature: Uint8Array;
  spki: Uint8Array;
  curve: string;
  /** Uzantı OID → değer (OCTET STRING içi). */
  extensions: Map<string, Uint8Array>;
}

export function parseCertificate(der: Uint8Array): Certificate {
  const [tbsNode, algNode, sigNode] = children(readNode(der, 0));
  const tbsFields = children(tbsNode);
  // [0] sürüm varsa alanlar bir kayar: seri, imza alg., yayıncı, geçerlilik, konu, SPKI, ... [3] uzantılar
  const base = tbsFields[0].tag === 0xa0 ? 1 : 0;
  const spkiNode = tbsFields[base + 5];
  const curveNode = children(children(spkiNode)[0])[1];
  const extensions = new Map<string, Uint8Array>();
  const extWrapper = tbsFields.find((f) => f.tag === 0xa3);
  if (extWrapper) {
    for (const ext of children(children(extWrapper)[0])) {
      const parts = children(ext);
      extensions.set(oid(parts[0]), content(parts[parts.length - 1]));
    }
  }
  const signatureBits = content(sigNode).slice(1); // BIT STRING: ilk bayt kullanılmayan bit sayısı
  return {
    tbs: tbsNode.bytes,
    signatureAlgorithm: oid(children(algNode)[0]),
    signature: signatureBits,
    spki: spkiNode.bytes,
    curve: curveNode ? oid(curveNode) : "",
    extensions,
  };
}

const CURVES: Record<string, { name: string; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const HASHES: Record<string, string> = { "1.2.840.10045.4.3.2": "SHA-256", "1.2.840.10045.4.3.3": "SHA-384" };

/** DER ECDSA imzası (SEQUENCE { r, s }) → WebCrypto'nun beklediği r||s. */
function rawSignature(der: Uint8Array, size: number): Uint8Array {
  const [r, s] = children(readNode(der, 0)).map((n) => {
    let v = content(n);
    while (v.length > size && v[0] === 0) v = v.slice(1);
    const out = new Uint8Array(size);
    out.set(v, size - v.length);
    return out;
  });
  const raw = new Uint8Array(size * 2);
  raw.set(r); raw.set(s, size);
  return raw;
}

async function importKey(spki: Uint8Array, curve: string): Promise<CryptoKey> {
  const info = CURVES[curve];
  if (!info) throw new Error("curve");
  return subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: info.name }, false, ["verify"]);
}

async function verifySignature(spki: Uint8Array, curve: string, hash: string, signatureDER: Uint8Array,
                               data: Uint8Array): Promise<boolean> {
  const key = await importKey(spki, curve);
  return subtle.verify({ name: "ECDSA", hash }, key, rawSignature(signatureDER, CURVES[curve].size), data);
}

/** child sertifikası parent'ın anahtarıyla imzalanmış mı. */
async function signedBy(child: Certificate, parent: Certificate): Promise<boolean> {
  const hash = HASHES[child.signatureAlgorithm];
  if (!hash) return false;
  return verifySignature(parent.spki, parent.curve, hash, child.signature, child.tbs);
}

/** Uncompressed EC açık anahtarı (SPKI'nin BIT STRING'i): anahtar kimliği bunun SHA-256'sıdır. */
function publicKeyPoint(spki: Uint8Array): Uint8Array {
  const bits = children(readNode(spki, 0))[1];
  return content(bits).slice(1);
}

// MARK: - Attestation

export interface AttestedKey {
  keyID: string;
  /** SPKI (base64 değil, ham bayt). */
  publicKey: Uint8Array;
  environment: "development" | "production";
}

export interface AttestationOptions {
  /** "TEAMID.bundle.id" */
  appID: string;
  rootDER?: Uint8Array;
  allowDevelopment: boolean;
}

const NONCE_OID = "1.2.840.113635.100.8.2";

export async function verifyAttestation(attestation: Uint8Array, keyIDBase64: string, challenge: Uint8Array,
                                        options: AttestationOptions): Promise<AttestedKey> {
  const object = decodeCBOR(attestation) as Map<CBOR, CBOR>;
  if (object.get("fmt") !== "apple-appattest") throw new Error("fmt");
  const statement = object.get("attStmt") as Map<CBOR, CBOR>;
  const x5c = statement.get("x5c") as Uint8Array[];
  const authData = object.get("authData") as Uint8Array;
  if (!x5c || x5c.length < 2 || !authData) throw new Error("structure");

  const leaf = parseCertificate(x5c[0]);
  const intermediate = parseCertificate(x5c[1]);
  const root = parseCertificate(options.rootDER ?? base64ToBytes(APPLE_APP_ATTEST_ROOT));
  if (!(await signedBy(leaf, intermediate)) || !(await signedBy(intermediate, root))) throw new Error("chain");

  // Nonce: SHA256(authData || SHA256(challenge)) sertifika uzantısındakiyle aynı olmalı.
  const nonce = await sha256(authData, await sha256(challenge));
  const extension = leaf.extensions.get(NONCE_OID);
  if (!extension) throw new Error("nonce missing");
  const inner = content(children(children(readNode(extension, 0))[0])[0]);
  if (!equal(inner, nonce)) throw new Error("nonce");

  const keyID = base64ToBytes(keyIDBase64);
  if (!equal(await sha256(publicKeyPoint(leaf.spki)), keyID)) throw new Error("key id");

  // authData: rpIdHash(32) flags(1) counter(4) aaguid(16) credIdLen(2) credId
  if (!equal(authData.slice(0, 32), await sha256(new TextEncoder().encode(options.appID)))) throw new Error("app id");
  const counter = new DataView(authData.buffer, authData.byteOffset).getUint32(33);
  if (counter !== 0) throw new Error("counter");
  const aaguid = new TextDecoder().decode(authData.slice(37, 53)).replace(/\0+$/, "");
  const environment = aaguid === "appattest" ? "production" : aaguid === "appattestdevelop" ? "development" : null;
  if (!environment || (environment === "development" && !options.allowDevelopment)) throw new Error("environment");
  const idLength = new DataView(authData.buffer, authData.byteOffset).getUint16(53);
  if (!equal(authData.slice(55, 55 + idLength), keyID)) throw new Error("credential id");

  return { keyID: keyIDBase64, publicKey: leaf.spki, environment };
}

// MARK: - Assertion

/** İstek gövdesinin imzası; geçerliyse yeni sayaç, değilse null. */
export async function verifyAssertion(assertion: Uint8Array, clientData: Uint8Array, publicKey: Uint8Array,
                                      previousCounter: number, appID: string): Promise<number | null> {
  const object = decodeCBOR(assertion) as Map<CBOR, CBOR>;
  const signature = object.get("signature") as Uint8Array;
  const authData = object.get("authenticatorData") as Uint8Array;
  if (!signature || !authData || authData.length < 37) return null;
  const nonce = await sha256(authData, await sha256(clientData));
  if (!(await verifySignature(publicKey, "1.2.840.10045.3.1.7", "SHA-256", signature, nonce))) return null;
  if (!equal(authData.slice(0, 32), await sha256(new TextEncoder().encode(appID)))) return null;
  const counter = new DataView(authData.buffer, authData.byteOffset).getUint32(33);
  return counter > previousCounter ? counter : null;
}
