# PayGuard — skrip demo 4 menit 30 detik

Rekam layar, bukan wajah. Semua angka di bawah ini sudah ada di chain; tidak ada yang
dipalsukan, jadi kalau kamu salah baca pun penonton bisa cek sendiri.

Legenda: **🖥️** = yang kamu lakukan di layar · **🎙️** = yang kamu ucapkan · **⏱️** = durasi.

---

## Persiapan sebelum rekam (5 menit, sekali saja)

Buka empat tab ini dulu, urutannya biar tidak ada jeda loading saat rekam:

1. `https://github.com/Alfonova-Node/payguard` — halaman repo (README)
2. `https://explorer-test.qday.info/address/0x5246b48c6791F1980f5F0d6b63b74A4940a2c7C8` — PayeeRegistry
3. `https://explorer-test.qday.info/address/0xE9960C67813CAD672Afe48d93E5199712f85C529` — SpendEnvelope
4. `https://explorer-test.qday.info/tx/0xe547bc31fafe307bed978b417a45da3ae589e06456a11202f3c87d47c2e0e4eb` — tx pembayaran

Tiga hal yang **tidak boleh** muncul di layar: isi `.env` / `.env.live`, isi `.keys/demo.json`,
dan terminal yang menampilkan private key. Kalau perlu buka terminal, pakai jendela baru
dengan ukuran font besar dan jangan `cat` file rahasia.

---

## 0:00 – 0:20 · Masalahnya

**🖥️** Layar bersih, hanya judul: `PayGuard — agent payments yang tidak bisa salah bayar`.

**🎙️** "Agen AI sekarang bisa memegang uang. Begitu bisa, dua hal langsung jadi masalah:
dia bisa membayar orang yang salah, dan dia bisa menghabiskan semuanya. Bukan karena jahat —
karena satu kalimat di dalam invoice bisa membelokkannya."

**⏱️** 20 detik.

---

## 0:20 – 0:50 · Dua primitifnya

**🖥️** Buka tab 1, scroll ke bagian atas README (bagian pembuka).

**🎙️** "PayGuard menjawab itu dengan dua hal yang hidup on-chain. Pertama, *Confirmation of
Payee*: yang terdaftar adalah nama **dan** dompetnya, dan hanya pemilik dompet yang boleh
mendaftarkan namanya sendiri. Kedua, *spend envelope*: kunci sesi untuk agen, dengan plafon
per transaksi, plafon harian, masa berlaku, dan pencabutan instan. Semua ditulis di Solidity,
bukan di prompt."

**⏱️** 30 detik.

---

## 0:50 – 1:30 · Registry: nama tidak bisa dipinjamkan

**🖥️** Pindah ke tab 2 (PayeeRegistry). Tunjuk alamat kontrak, lalu buka tx pendaftaran:
`https://explorer-test.qday.info/tx/0x0fdca39bdd9f0c32e15214a6aca1269b20fd9be9f244cbffb9203572affb9a57`

**🎙️** "Ini registry-nya. Transaksi ini bukan dari saya sebagai owner — ini dikirim oleh
dompet payee itu sendiri, `0xE9783E5B…`, mendaftarkan nama 'Warung Bu Sri'. Owner pun tidak
punya fungsi untuk menempelkan nama ke dompet orang lain. Jadi registry ini tidak bisa dipakai
untuk memberi restu ke dompet penyerang — satu-satunya cara sebuah dompet punya nama adalah
dompet itu menandatangani sendiri."

**⏱️** 40 detik.

---

## 1:30 – 2:15 · Pembayaran sungguhan

**🖥️** Pindah ke tab 4 (tx pembayaran). Tunjuk `Status: Success`, `Block 4041545`,
`To: 0xE9960C67…` (envelope), lalu scroll ke bagian transfer tUSD8.

**🎙️** "Ini pembayaran pertama, 1,5 tUSD8 lewat agen dengan kunci sesi — bukan kunci owner.
Statusnya sukses, blok 4.041.545. Perhatikan alamat pengirimnya: `0x3E29229E…`, itu dompet
agen. Agen tidak pernah melihat kunci owner; yang dia punya hanya sesi dengan plafon 2 tUSD8
per transaksi dan 4 tUSD8 per hari. Kalau kunci agen bocor besok, kerugiannya sudah dibatasi
oleh kontrak, bukan oleh niat baik."

**⏱️** 45 detik.

---

## 2:15 – 3:05 · Penolakan pertama, dan buktinya on-chain

**🖥️** Buka tx penolakan:
`https://explorer-test.qday.info/tx/0x7257b7b40d2dd63f7343794aa2594c7f847f055b6197cd528540c3ee0ef2921c`
lalu tunjuk input data / event `PaymentBlocked`.

**🎙️** "Sekarang yang lebih penting: invoice yang **ditolak**. Invoice ini menyebut nama yang
sama persis — 'Warung Bu Sri' — tapi dompetnya `0x3C44CdDd…`, dompet lain. Agen memanggil
`previewPay`, registry bilang nama itu milik `0xE9783E5B…`, dan transaksi tidak pernah
dibuat. Yang menarik, penolakannya sendiri tetap jadi transaksi: fungsi `logBlocked` menulis
alasan penolakan ke chain. Jadi agen tidak bisa menghapus catatan kegagalannya sendiri —
audit trail-nya bukan file log yang bisa diedit, tapi state kontrak."

**⏱️** 50 detik.

---

## 3:05 – 3:45 · Plafon, dan penghitung yang tidak bisa dibohongi

**🖥️** Pindah ke tab 3 (SpendEnvelope), buka bagian Read Contract, panggil `sessions` dengan
alamat agen `0x3E29229E79528dfAe409F24FbeaC3e4FC4c4A377`. Kalau explorer tidak punya read
contract, tampilkan saja tangkapan terminal yang sudah kamu siapkan sebelumnya.

**🎙️** "Invoice ketiga mintanya 3 tUSD8, padahal plafon per transaksinya 2. Ditolak, kode 2.
Dan lihat struct sesi ini: `perTxCap` 2 juta, `dailyCap` 4 juta, `payments` satu, `blocked`
tiga. Angka satu banding tiga itu tersimpan di kontrak, jadi siapa pun bisa memverifikasi
bahwa tiga percobaan benar-benar terjadi dan tidak ada satu pun yang diam-diam lolos."

**⏱️** 40 detik.

---

## 3:45 – 4:15 · Yang membedakan ini dari sekadar allowlist

**🖥️** Kembali ke README, scroll ke bagian **Security properties worth stating**.

**🎙️** "Tiga hal yang sering salah diimplementasikan. Pertama, pemakaian harian dihitung per
`(agen, hari)`, bukan per sesi — jadi mencabut sesi lalu membuat sesi baru **tidak** mereset
plafon harian. Kedua, sesi di-scope ke `msg.sender`, jadi `previewPay` tidak bisa berbohong
tentang limit milik pemanggil lain. Ketiga, tidak ada kunci di dalam repo: kunci agen
disuntikkan lewat environment, dan `.env` masuk gitignore."

**⏱️** 30 detik.

---

## 4:15 – 4:30 · Penutup

**🖥️** Tampilkan repo: `github.com/Alfonova-Node/payguard`. Scroll cepat ke tabel bukti.

**🎙️** "Semua yang kamu lihat tadi bisa kamu ulang sendiri: dua kontraknya publik di Aevum
testnet, `forge test` dua belas lulus, dan setiap hash di tabel ini bisa diklik. PayGuard
bukan agen yang dilatih untuk tidak salah bayar — ini agen yang secara mekanis tidak bisa
salah bayar."

**⏱️** 15 detik.

---

## Kalau kehabisan waktu

Potong urutan ini, jangan yang lain: **3:45–4:15** dulu, lalu **0:20–0:30**. Yang wajib
tinggal: penolakan on-chain (2:15) dan penghitung 1/3 (3:05). Dua bagian itu yang paling
sulit ditandingi peserta lain.

## Kalau ada yang ditanya

- *"Kenapa tidak pakai akun pintar / ERC-4337?"* — Envelope-nya kompatibel: kontrak yang sama
  bisa jadi validator untuk smart account. Yang saya kirim ini primitifnya, bukan wallet-nya.
- *"Bagaimana kalau nama payee didahului orang lain?"* — Itu batasan yang saya tulis di
  README: satu nama satu dompet, siapa cepat dia dapat. Perluasan yang benar adalah
  menambahkan merchant ID di samping `nameHash`, bukan melonggarkan aturan pendaftaran.
- *"Apa yang mencegah agen memalsukan invoice?"* — Tidak ada yang perlu mencegah: agen boleh
  memalsukan apa saja, tapi dompet yang tidak terdaftar untuk nama itu tidak akan pernah
  lolos `registry.confirm`, dan nominal di atas plafon tidak akan pernah lolos `previewPay`.
