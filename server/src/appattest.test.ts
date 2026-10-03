import { execSync } from "node:child_process";
import { createPrivateKey, sign as nodeSign } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { base64ToBytes, decodeCBOR, parseCertificate, verifyAssertion, verifyAttestation, APPLE_APP_ATTEST_ROOT } from "./appattest.ts";

const APP_ID = "4BAD86T55H.com.omeraydemir.stubly";

// Sınama için küçük CBOR yazıcı.
function encode(value: unknown): Uint8Array {
  const out: number[] = [];
  const head = (major: number, n: number) => {
    if (n < 24) out.push((major << 5) | n);
    else if (n < 256) out.push((major << 5) | 24, n);
    else if (n < 65536) out.push((major << 5) | 25, n >> 8, n & 255);
    else out.push((major << 5) | 26, (n >>> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255);
  };
  const write = (v: unknown): void => {
    if (typeof v === "number") head(0, v);
    else if (typeof v === "string") { const b = new TextEncoder().encode(v); head(3, b.length); out.push(...b); }
    else if (v instanceof Uint8Array) { head(2, v.length); out.push(...v); }
    else if (Array.isArray(v)) { head(4, v.length); v.forEach(write); }
    else { const entries = Object.entries(v as object); head(5, entries.length); for (const [k, x] of entries) { write(k); write(x); } }
  };
  write(value);
  return Uint8Array.from(out);
}

const sha = async (...parts: Uint8Array[]) => {
  const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0; for (const p of parts) { all.set(p, o); o += p.length; }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", all));
};
const hex = (b: Uint8Array) => Buffer.from(b).toString("hex");
const der = (pemPath: string) => new Uint8Array(Buffer.from(readFileSync(pemPath, "utf8").replace(/-----[^-]+-----|\s/g, ""), "base64"));

function authData(counter: number, aaguid: string, keyID?: Uint8Array, rpHash?: Uint8Array): Promise<Uint8Array> {
  return (async () => {
    const parts = [rpHash ?? await sha(new TextEncoder().encode(APP_ID)), Uint8Array.of(0x40),
      Uint8Array.of((counter >>> 24) & 255, (counter >> 16) & 255, (counter >> 8) & 255, counter & 255)];
    if (keyID) {
      const id = new Uint8Array(16); id.set(new TextEncoder().encode(aaguid));
      parts.push(id, Uint8Array.of(0, keyID.length), keyID);
    }
    const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
    let o = 0; for (const p of parts) { all.set(p, o); o += p.length; }
    return all;
  })();
}

/** openssl ile Apple'ınkine benzer zincir: kök (P-384) → ara (P-384) → yaprak (P-256, nonce uzantılı). */
async function fixture(aaguid = "appattestdevelop", challenge = new TextEncoder().encode("tek-kullanimlik")) {
  const dir = mkdtempSync(join(tmpdir(), "appattest-"));
  const run = (cmd: string) => execSync(cmd, { cwd: dir, stdio: "pipe" });
  run("openssl ecparam -name secp384r1 -genkey -noout -out root.key");
  run("openssl req -x509 -new -key root.key -subj /CN=Root -days 2 -out root.pem -sha384");
  run("openssl ecparam -name secp384r1 -genkey -noout -out inter.key");
  run("openssl req -new -key inter.key -subj /CN=Inter -out inter.csr");
  writeFileSync(join(dir, "ca.ext"), "basicConstraints=critical,CA:true\n");
  run("openssl x509 -req -in inter.csr -CA root.pem -CAkey root.key -CAcreateserial -days 2 -sha384 -extfile ca.ext -out inter.pem");
  run("openssl ecparam -name prime256v1 -genkey -noout -out leaf.key");
  const point = new Uint8Array(execSync("openssl ec -in leaf.key -pubout -outform DER", { cwd: dir, stdio: ["pipe", "pipe", "pipe"] })).slice(-65);
  const keyID = await sha(point);
  const auth = await authData(0, aaguid, keyID);
  const nonce = await sha(auth, await sha(challenge));
  writeFileSync(join(dir, "leaf.ext"), `1.2.840.113635.100.8.2=DER:3024A1220420${hex(nonce)}\n`);
  run("openssl req -new -key leaf.key -subj /CN=Leaf -out leaf.csr");
  run("openssl x509 -req -in leaf.csr -CA inter.pem -CAkey inter.key -CAcreateserial -days 2 -sha256 -extfile leaf.ext -out leaf.pem");
  const attestation = encode({ fmt: "apple-appattest", attStmt: { x5c: [der(join(dir, "leaf.pem")), der(join(dir, "inter.pem"))], receipt: new Uint8Array(4) }, authData: auth });
  return { dir, keyID, challenge, attestation, root: der(join(dir, "root.pem")), leafKey: createPrivateKey(readFileSync(join(dir, "leaf.key"))) };
}

test("Apple kök sertifikası okunur", () => {
  const root = parseCertificate(base64ToBytes(APPLE_APP_ATTEST_ROOT));
  assert.equal(root.curve, "1.3.132.0.34");
  assert.equal(root.signatureAlgorithm, "1.2.840.10045.4.3.3");
});

test("geçerli attestation kabul edilir, assertion artan sayaçla doğrulanır", async () => {
  const f = await fixture();
  const keyIDText = Buffer.from(f.keyID).toString("base64");
  const key = await verifyAttestation(f.attestation, keyIDText, f.challenge, { appID: APP_ID, rootDER: f.root, allowDevelopment: true });
  assert.equal(key.environment, "development");

  const body = new TextEncoder().encode('{"country":"PT"}');
  const auth = await authData(1, "");
  const signature = nodeSign("sha256", await sha(auth, await sha(body)), f.leafKey);
  const assertion = encode({ signature: new Uint8Array(signature), authenticatorData: auth });
  assert.equal(await verifyAssertion(assertion, body, key.publicKey, 0, APP_ID), 1);
  assert.equal(await verifyAssertion(assertion, body, key.publicKey, 1, APP_ID), null, "tekrar oynatma: sayaç artmadı");
  assert.equal(await verifyAssertion(assertion, new TextEncoder().encode("{}"), key.publicKey, 0, APP_ID), null, "gövde değişti");
});

test("yanlış challenge, uygulama, ortam ya da kök reddedilir", async () => {
  const f = await fixture();
  const id = Buffer.from(f.keyID).toString("base64");
  const options = { appID: APP_ID, rootDER: f.root, allowDevelopment: true };
  await assert.rejects(verifyAttestation(f.attestation, id, new TextEncoder().encode("baska"), options), /nonce/);
  await assert.rejects(verifyAttestation(f.attestation, id, f.challenge, { ...options, appID: "X.other.app" }), /app id/);
  await assert.rejects(verifyAttestation(f.attestation, id, f.challenge, { ...options, allowDevelopment: false }), /environment/);
  await assert.rejects(verifyAttestation(f.attestation, id, f.challenge, { ...options, rootDER: undefined }), /chain/, "gerçek Apple kökü bu zinciri imzalamadı");
  await assert.rejects(verifyAttestation(f.attestation, Buffer.alloc(32).toString("base64"), f.challenge, options), /key id/);
  const production = await fixture("appattest");
  const key = await verifyAttestation(production.attestation, Buffer.from(production.keyID).toString("base64"), production.challenge,
                                      { appID: APP_ID, rootDER: production.root, allowDevelopment: false });
  assert.equal(key.environment, "production");
});

test("CBOR çözücü", () => {
  const value = decodeCBOR(encode({ a: [1, 300, "x"], b: new Uint8Array([7]) })) as Map<unknown, unknown>;
  assert.deepEqual(value.get("a"), [1, 300, "x"]);
  assert.deepEqual(value.get("b"), new Uint8Array([7]));
});
