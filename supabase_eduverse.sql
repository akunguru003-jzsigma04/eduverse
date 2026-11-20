-- =====================================================================
--  EDUVERSE — Skema Supabase lengkap (satu file)
--  Versi skema: 2026.11.20.2
--  Menggantikan supabase_schema.sql dan seluruh supabase_patch_1 s.d. 17.
--
--  Cara pakai:
--    Supabase Dashboard > SQL Editor > New query > tempel SELURUH isi file ini > Run.
--
--  Aman dijalankan pada:
--    * proyek Supabase baru (kosong), atau
--    * proyek lama yang sudah memakai skema/patch sebelumnya (data tidak dihapus;
--      kolom, aturan, dan fungsi yang kurang akan dilengkapi).
--  Boleh dijalankan berulang kali.
--
--  Langkah terakhir (sekali saja): daftarkan akun guru — lihat bagian 11 di akhir file.
--  Setelah itu, pembaruan berikutnya cukup lewat menu 🛠️ Pembaruan Sistem di aplikasi.
-- =====================================================================


-- =====================================================================
-- 1. GURU (siapa yang boleh mengelola data)
-- =====================================================================
create table if not exists public.guru (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nama text,
  mapel text default 'Matematika'
);
alter table public.guru add column if not exists mapel text default 'Matematika';

create or replace function public.is_guru()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.guru where user_id = auth.uid());
$$;


-- =====================================================================
-- 2. TABEL AKADEMIK
-- =====================================================================
create table if not exists public.kelas (
  id uuid primary key default gen_random_uuid(),
  nama text not null unique,
  tahun_ajaran text,
  wali_kelas text
);

create table if not exists public.siswa (
  id uuid primary key default gen_random_uuid(),
  kelas_id uuid not null references public.kelas(id) on delete cascade,
  nis text not null,
  nama text not null,
  gaya_belajar text check (gaya_belajar in ('Visual','Auditori','Kinestetik')),
  unique (kelas_id, nis)
);

-- Jam pelajaran (slot 30 menit)
create table if not exists public.jam_pelajaran (
  jam_ke smallint primary key check (jam_ke between 1 and 12),
  mulai time not null,
  selesai time not null
);

create table if not exists public.jadwal (
  id uuid primary key default gen_random_uuid(),
  kelas_id uuid not null references public.kelas(id) on delete cascade,
  hari smallint not null check (hari between 1 and 5),          -- 1 = Senin ... 5 = Jumat
  jam_ke smallint not null check (jam_ke between 1 and 12),
  mapel text not null,
  semester text not null default 'Ganjil' check (semester in ('Ganjil','Genap')),
  jenis text not null default 'Reguler' check (jenis in ('Reguler','Kokurikuler'))
);

create table if not exists public.pengumuman (
  id uuid primary key default gen_random_uuid(),
  judul text not null,
  isi text,
  tag text not null default 'Info',                               -- Info / Penting / Kokurikuler
  aktif boolean not null default true,
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.tugas (
  id uuid primary key default gen_random_uuid(),
  kelas_id uuid references public.kelas(id) on delete cascade,
  mapel text not null,
  judul text not null,
  deskripsi text,
  tenggat date not null,
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.absensi (
  id uuid primary key default gen_random_uuid(),
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  tanggal date not null default current_date,
  status text not null,
  catatan text,
  unique (siswa_id, tanggal)
);

create table if not exists public.jurnal (
  id uuid primary key default gen_random_uuid(),
  kelas_id uuid references public.kelas(id) on delete set null,
  tanggal date not null default current_date,
  jenis text not null default 'harian' check (jenis in ('harian','p5')),
  pertemuan integer,
  materi text,
  kegiatan text,
  kokurikuler text,
  refleksi text,
  dibuat_pada timestamptz not null default now()
);

-- Materi per tingkat (X, XI, XII) dan semester
create table if not exists public.materi (
  id uuid primary key default gen_random_uuid(),
  kelas_id uuid references public.kelas(id) on delete cascade,  -- lama; materi kini per tingkat
  tingkat text check (tingkat in ('X','XI','XII')),
  elemen text,
  nama text not null,
  urutan integer not null default 1,
  semester text not null default 'Ganjil' check (semester in ('Ganjil','Genap')),
  tanggal_mulai date,
  tanggal_selesai date
);

create table if not exists public.tp (
  id uuid primary key default gen_random_uuid(),
  materi_id uuid not null references public.materi(id) on delete cascade,
  urutan integer not null default 1,
  deskripsi text not null
);

create table if not exists public.nilai_formatif (
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  tp_id uuid not null references public.tp(id) on delete cascade,
  predikat text not null check (predikat in ('IST','BAIK','PB')),
  primary key (siswa_id, tp_id)
);

-- Nilai sumatif per materi: skor_awal (hasil tes/CBT) -> tindak lanjut -> skor (nilai akhir)
create table if not exists public.nilai_sumatif (
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  materi_id uuid not null references public.materi(id) on delete cascade,
  skor numeric(5,2) check (skor between 0 and 100),
  skor_awal numeric(5,2) check (skor_awal between 0 and 100),
  status_pp text not null default 'belum' check (status_pp in ('belum','selesai')),
  tindak_lanjut text,
  primary key (siswa_id, materi_id)
);

-- Pengaturan Program Perbaikan & Pengayaan per kelas dan materi
create table if not exists public.pp_sesi (
  kelas_id uuid not null references public.kelas(id) on delete cascade,
  materi_id uuid not null references public.materi(id) on delete cascade,
  tanggal date,
  kkm numeric(5,2) not null default 70,
  nilai_min numeric(5,2) not null default 0,
  nilai_maks numeric(5,2) not null default 100,
  nilai_diinginkan numeric(5,2) not null default 100,
  primary key (kelas_id, materi_id)
);


-- =====================================================================
-- 3. TABEL CBT SUMATIF
-- =====================================================================
-- Stimulus bersama (bacaan / tabel / grafik untuk beberapa soal)
create table if not exists public.stimulus (
  id uuid primary key default gen_random_uuid(),
  materi_id uuid not null references public.materi(id) on delete cascade,
  judul text not null,
  teks text,
  gambar_url text,
  dibuat_pada timestamptz not null default now()
);

-- Bank soal. tipe: PG | PGK (PG kompleks MCMA) | KATEGORI (Benar/Salah per pernyataan) | ISIAN
--   kunci      : indeks opsi benar (khusus PG)
--   kunci_json : PGK {"jawab":[0,2]} | KATEGORI {"jawab":[true,false],"label":["Benar","Salah"]}
--                ISIAN {"angka":0.5,"toleransi":0,"teks":["1/2"]}
--   panca_cinta: ALLAH | ILMU | LINGKUNGAN | DIRI | TANAHAIR (Kurikulum Berbasis Cinta)
create table if not exists public.soal_bank (
  id uuid primary key default gen_random_uuid(),
  materi_id uuid not null references public.materi(id) on delete cascade,
  tp_id uuid references public.tp(id) on delete set null,
  stimulus_id uuid references public.stimulus(id) on delete set null,
  tipe text not null default 'PG',
  pertanyaan text not null,
  gambar_url text,
  opsi jsonb not null,
  kunci smallint,
  kunci_json jsonb,
  parsial boolean not null default false,
  bobot numeric not null default 1 check (bobot > 0),
  level text check (level in ('L1','L2','L3')),               -- Pemahaman / Aplikasi / Penalaran
  indikator text,
  pembahasan text,
  panca_cinta text[],
  stat_p numeric(4,2),                                          -- tingkat kesukaran
  stat_d numeric(4,2),                                          -- daya pembeda
  stat_n integer,
  stat_pada timestamptz,
  diarsip_pada timestamptz,
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.cbt_tes (
  id uuid primary key default gen_random_uuid(),
  kode text not null unique,
  judul text not null,
  jenis text not null check (jenis in ('Sumatif Lintas Materi','Sumatif Akhir Semester')),
  tingkat text not null check (tingkat in ('X','XI','XII')),
  semester text not null check (semester in ('Ganjil','Genap')),
  durasi_menit integer not null default 60 check (durasi_menit between 5 and 300),
  acak_soal boolean not null default true,
  acak_opsi boolean not null default false,
  tampil_skor boolean not null default false,
  pakai_token boolean not null default true,
  token_rahasia text not null default md5(random()::text || clock_timestamp()::text),
  ikrar boolean not null default true,
  refleksi boolean not null default true,
  umpan_balik_tp boolean not null default true,
  status text not null default 'draft' check (status in ('draft','buka','tutup')),
  dibuat_pada timestamptz not null default now()
);

create table if not exists public.cbt_tes_kelas (
  tes_id uuid not null references public.cbt_tes(id) on delete cascade,
  kelas_id uuid not null references public.kelas(id) on delete cascade,
  primary key (tes_id, kelas_id)
);

create table if not exists public.cbt_tes_soal (
  tes_id uuid not null references public.cbt_tes(id) on delete cascade,
  soal_id uuid not null,
  urutan integer not null,
  bobot numeric,
  dianulir boolean not null default false,
  primary key (tes_id, soal_id)
);

create table if not exists public.cbt_sesi (
  id uuid primary key default gen_random_uuid(),
  tes_id uuid not null references public.cbt_tes(id) on delete cascade,
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  urutan jsonb not null,
  peta_opsi jsonb,
  perangkat text,
  mulai timestamptz not null default now(),
  selesai timestamptz,
  status text not null default 'berjalan' check (status in ('berjalan','selesai')),
  tambahan_menit integer not null default 0,
  pelanggaran integer not null default 0,
  ikrar_pada timestamptz,
  refleksi jsonb,
  benar integer,
  total integer,
  skor numeric(5,2),
  unique (tes_id, siswa_id)
);

create table if not exists public.cbt_jawaban (
  sesi_id uuid not null references public.cbt_sesi(id) on delete cascade,
  soal_id uuid not null,
  pilihan smallint,
  jawaban jsonb,
  diubah timestamptz not null default now(),
  primary key (sesi_id, soal_id)
);

create table if not exists public.cbt_hasil_materi (
  sesi_id uuid not null references public.cbt_sesi(id) on delete cascade,
  materi_id uuid not null references public.materi(id) on delete cascade,
  benar integer not null,
  total integer not null,
  skor numeric(5,2) not null,
  primary key (sesi_id, materi_id)
);

create table if not exists public.cbt_hasil_tp (
  sesi_id uuid not null references public.cbt_sesi(id) on delete cascade,
  tp_id uuid not null references public.tp(id) on delete cascade,
  benar integer not null,
  total integer not null,
  skor numeric(5,2) not null,
  primary key (sesi_id, tp_id)
);

-- Nilai Sumatif Akhir Semester (terpisah dari sumatif lingkup materi)
create table if not exists public.nilai_sas (
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  semester text not null check (semester in ('Ganjil','Genap')),
  skor numeric(5,2) check (skor between 0 and 100),
  tes_id uuid references public.cbt_tes(id) on delete set null,
  diperbarui timestamptz not null default now(),
  primary key (siswa_id, semester)
);


-- =====================================================================
-- 3b. MEDIA INTERAKTIF (file HTML yang diunggah guru)
-- =====================================================================
create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  judul text not null,
  deskripsi text,
  materi_id uuid references public.materi(id) on delete set null,
  tp_id uuid references public.tp(id) on delete set null,      -- TP tujuan nilai formatif
  file_path text not null,                                      -- lokasi di bucket "media"
  ukuran integer,
  penilaian boolean not null default false,                     -- media mengirim nilai ke EDUVERSE
  kktp numeric(5,2) not null default 75 check (kktp between 1 and 100), -- informasi: KKTP yang diatur di dalam media
  pengaturan jsonb not null default '{}'::jsonb,
  formatif_otomatis boolean not null default true,             -- predikat terbaik langsung masuk nilai_formatif TP tujuan                -- pengaturan guru di dalam media (mis. jadwal & KKTP), dibagikan ke semua siswa
  kode_akses text,                                              -- opsional; bila diisi, siswa wajib memasukkannya
  aktif boolean not null default true,
  urutan integer not null default 1,
  dibuat_pada timestamptz not null default now(),
  diperbarui timestamptz not null default now()
);

-- Setiap kiriman nilai dari media (satu baris per percobaan)
create table if not exists public.media_hasil (
  id uuid primary key default gen_random_uuid(),
  media_id uuid not null references public.media(id) on delete cascade,
  siswa_id uuid not null references public.siswa(id) on delete cascade,
  bagian text,                                                  -- mis. Berlatih / Bermain
  skor numeric(5,2) not null check (skor between 0 and 100),
  benar integer,
  salah integer,
  penilaian boolean not null default true,                      -- dihitung untuk nilai formatif
  predikat text check (predikat in ('IST', 'BAIK', 'PB')),     -- predikat menurut penilaian di dalam media
  kktp numeric(5,2),                                            -- KKTP yang dipakai media saat itu
  rincian jsonb,
  dikirim_pada timestamptz not null default now()
);
-- proyek yang sudah memasang versi 2026.11.20.1
alter table public.media add column if not exists pengaturan jsonb not null default '{}'::jsonb;
alter table public.media add column if not exists formatif_otomatis boolean not null default true;
alter table public.media_hasil add column if not exists predikat text check (predikat in ('IST', 'BAIK', 'PB'));
alter table public.media_hasil add column if not exists kktp numeric(5,2);


-- =====================================================================
-- 4. PENYESUAIAN UNTUK PROYEK LAMA
--    (pada proyek baru, bagian ini tidak mengubah apa pun)
-- =====================================================================
-- Kolom yang ditambahkan oleh patch-patch terdahulu
alter table public.kelas          add column if not exists wali_kelas text;
alter table public.jadwal         add column if not exists semester text not null default 'Ganjil';
alter table public.jadwal         add column if not exists jenis text not null default 'Reguler';
alter table public.jurnal         add column if not exists kokurikuler text;
alter table public.jurnal         add column if not exists pertemuan integer;
alter table public.materi         add column if not exists semester text not null default 'Ganjil';
alter table public.materi         add column if not exists elemen text;
alter table public.materi         add column if not exists tingkat text;
alter table public.materi         alter column kelas_id drop not null;
alter table public.nilai_sumatif  alter column skor drop not null;
alter table public.nilai_sumatif  add column if not exists skor_awal numeric(5,2);
alter table public.nilai_sumatif  add column if not exists status_pp text not null default 'belum';
alter table public.nilai_sumatif  add column if not exists tindak_lanjut text;
alter table public.soal_bank      add column if not exists tp_id uuid references public.tp(id) on delete set null;
alter table public.soal_bank      add column if not exists stimulus_id uuid references public.stimulus(id) on delete set null;
alter table public.soal_bank      add column if not exists tipe text not null default 'PG';
alter table public.soal_bank      add column if not exists gambar_url text;
alter table public.soal_bank      add column if not exists kunci_json jsonb;
alter table public.soal_bank      add column if not exists parsial boolean not null default false;
alter table public.soal_bank      add column if not exists bobot numeric not null default 1;
alter table public.soal_bank      add column if not exists level text;
alter table public.soal_bank      add column if not exists indikator text;
alter table public.soal_bank      add column if not exists pembahasan text;
alter table public.soal_bank      add column if not exists panca_cinta text[];
alter table public.soal_bank      add column if not exists stat_p numeric(4,2);
alter table public.soal_bank      add column if not exists stat_d numeric(4,2);
alter table public.soal_bank      add column if not exists stat_n integer;
alter table public.soal_bank      add column if not exists stat_pada timestamptz;
alter table public.soal_bank      add column if not exists diarsip_pada timestamptz;
alter table public.soal_bank      add column if not exists dibuat_pada timestamptz not null default now();
alter table public.soal_bank      alter column kunci drop not null;
alter table public.cbt_tes        add column if not exists acak_opsi boolean not null default false;
alter table public.cbt_tes        add column if not exists pakai_token boolean not null default true;
alter table public.cbt_tes        add column if not exists token_rahasia text not null default md5(random()::text || clock_timestamp()::text);
alter table public.cbt_tes        add column if not exists ikrar boolean not null default true;
alter table public.cbt_tes        add column if not exists refleksi boolean not null default true;
alter table public.cbt_tes        add column if not exists umpan_balik_tp boolean not null default true;
alter table public.cbt_tes_soal   add column if not exists bobot numeric;
alter table public.cbt_tes_soal   add column if not exists dianulir boolean not null default false;
alter table public.cbt_sesi       add column if not exists peta_opsi jsonb;
alter table public.cbt_sesi       add column if not exists perangkat text;
alter table public.cbt_sesi       add column if not exists tambahan_menit integer not null default 0;
alter table public.cbt_sesi       add column if not exists pelanggaran integer not null default 0;
alter table public.cbt_sesi       add column if not exists ikrar_pada timestamptz;
alter table public.cbt_sesi       add column if not exists refleksi jsonb;
alter table public.cbt_jawaban    alter column pilihan drop not null;
alter table public.cbt_jawaban    add column if not exists jawaban jsonb;
alter table public.cbt_jawaban    add column if not exists diubah timestamptz not null default now();

-- Materi lama yang masih terikat kelas: tingkat diambil dari nama kelas (X 1 -> X)
update public.materi m
   set tingkat = case
       when upper(k.nama) ~ '^XII([^IVX]|$)' then 'XII'
       when upper(k.nama) ~ '^XI([^IVX]|$)'  then 'XI'
       when upper(k.nama) ~ '^X([^IVX]|$)'   then 'X'
     end
  from public.kelas k
 where m.kelas_id = k.id and m.tingkat is null;

-- Jurnal: satu per kelas per tanggal (yang terbaru dipertahankan)
delete from public.jurnal a
 using public.jurnal b
 where a.kelas_id = b.kelas_id and a.tanggal = b.tanggal
   and (a.dibuat_pada, a.id) < (b.dibuat_pada, b.id);

-- Jadwal: satu kelas boleh berbeda jadwal tiap semester
alter table public.jadwal drop constraint if exists jadwal_kelas_id_hari_jam_ke_key;


-- =====================================================================
-- 5. ATURAN DATA (constraint) — dibuat ulang agar seragam
-- =====================================================================
alter table public.absensi drop constraint if exists absensi_status_check;
alter table public.absensi add constraint absensi_status_check
  check (status in ('Hadir','Terlambat','Sakit','Izin','Alpa'));

alter table public.jadwal drop constraint if exists jadwal_semester_check;
alter table public.jadwal add constraint jadwal_semester_check check (semester in ('Ganjil','Genap'));
alter table public.jadwal drop constraint if exists jadwal_jenis_check;
alter table public.jadwal add constraint jadwal_jenis_check check (jenis in ('Reguler','Kokurikuler'));

alter table public.materi drop constraint if exists materi_semester_check;
alter table public.materi add constraint materi_semester_check check (semester in ('Ganjil','Genap'));
alter table public.materi drop constraint if exists materi_tingkat_check;
alter table public.materi add constraint materi_tingkat_check check (tingkat in ('X','XI','XII'));

alter table public.nilai_sumatif drop constraint if exists nilai_sumatif_skor_awal_check;
alter table public.nilai_sumatif add constraint nilai_sumatif_skor_awal_check check (skor_awal between 0 and 100);
alter table public.nilai_sumatif drop constraint if exists nilai_sumatif_status_pp_check;
alter table public.nilai_sumatif add constraint nilai_sumatif_status_pp_check check (status_pp in ('belum','selesai'));

alter table public.soal_bank drop constraint if exists soal_bank_tipe_check;
alter table public.soal_bank add constraint soal_bank_tipe_check check (tipe in ('PG','PGK','KATEGORI','ISIAN'));
alter table public.soal_bank drop constraint if exists soal_bank_opsi_check;
alter table public.soal_bank add constraint soal_bank_opsi_check check (
  jsonb_typeof(opsi) = 'array' and jsonb_array_length(opsi) <= 8
  and (tipe = 'ISIAN' or jsonb_array_length(opsi) >= 2));
alter table public.soal_bank drop constraint if exists soal_bank_kunci_check;
alter table public.soal_bank add constraint soal_bank_kunci_check check (kunci between 0 and 4);
alter table public.soal_bank drop constraint if exists soal_bank_kunci_tipe_check;
alter table public.soal_bank add constraint soal_bank_kunci_tipe_check check (
  (tipe = 'PG' and kunci is not null) or (tipe <> 'PG' and kunci_json is not null));
alter table public.soal_bank drop constraint if exists soal_bank_level_check;
alter table public.soal_bank add constraint soal_bank_level_check check (level in ('L1','L2','L3'));
alter table public.soal_bank drop constraint if exists soal_bank_panca_cinta_check;
alter table public.soal_bank add constraint soal_bank_panca_cinta_check
  check (panca_cinta is null or panca_cinta <@ array['ALLAH','ILMU','LINGKUNGAN','DIRI','TANAHAIR']);

alter table public.cbt_tes_soal drop constraint if exists cbt_tes_soal_bobot_check;
alter table public.cbt_tes_soal add constraint cbt_tes_soal_bobot_check check (bobot is null or bobot > 0);
alter table public.cbt_sesi drop constraint if exists cbt_sesi_tambahan_menit_check;
alter table public.cbt_sesi add constraint cbt_sesi_tambahan_menit_check check (tambahan_menit between 0 and 300);

-- Soal yang sudah dipakai tes tidak boleh terhapus (jawaban & nilai lama tetap utuh; soal diarsipkan)
alter table public.cbt_jawaban drop constraint if exists cbt_jawaban_soal_id_fkey;
alter table public.cbt_jawaban add constraint cbt_jawaban_soal_id_fkey
  foreign key (soal_id) references public.soal_bank(id) on delete restrict;
alter table public.cbt_tes_soal drop constraint if exists cbt_tes_soal_soal_id_fkey;
alter table public.cbt_tes_soal add constraint cbt_tes_soal_soal_id_fkey
  foreign key (soal_id) references public.soal_bank(id) on delete restrict;


-- =====================================================================
-- 6. INDEKS
-- =====================================================================
create index if not exists idx_siswa_kelas        on public.siswa(kelas_id);
create index if not exists idx_absensi_tanggal    on public.absensi(tanggal);
create index if not exists idx_tugas_tenggat      on public.tugas(tenggat);
create unique index if not exists jadwal_kelas_sem_hari_jam_idx on public.jadwal (kelas_id, semester, hari, jam_ke);
create unique index if not exists jurnal_kelas_tanggal_idx      on public.jurnal (kelas_id, tanggal);
create index if not exists idx_materi_kelas       on public.materi(kelas_id);
create index if not exists idx_materi_tingkat     on public.materi(tingkat);
create index if not exists idx_tp_materi          on public.tp(materi_id);
create index if not exists idx_stimulus_materi    on public.stimulus(materi_id);
create index if not exists idx_soal_materi        on public.soal_bank(materi_id);
create index if not exists idx_soal_stimulus      on public.soal_bank(stimulus_id);
create index if not exists idx_sesi_tes           on public.cbt_sesi(tes_id);
create index if not exists idx_hasil_tp_tp        on public.cbt_hasil_tp(tp_id);
create index if not exists idx_media_materi       on public.media(materi_id);
create index if not exists idx_media_hasil_media  on public.media_hasil(media_id, siswa_id);


-- =====================================================================
-- 7. KEAMANAN (Row Level Security) & HAK AKSES
-- =====================================================================
do $$
declare t text;
begin
  -- semua tabel: RLS aktif, guru boleh mengelola
  foreach t in array array['kelas','siswa','jam_pelajaran','jadwal','pengumuman','tugas','absensi','jurnal',
                           'materi','tp','nilai_formatif','nilai_sumatif','pp_sesi','stimulus','soal_bank',
                           'cbt_tes','cbt_tes_kelas','cbt_tes_soal','cbt_sesi','cbt_jawaban',
                           'cbt_hasil_materi','cbt_hasil_tp','nilai_sas','media','media_hasil']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "guru_kelola" on public.%I', t);
    execute format('create policy "guru_kelola" on public.%I for all to authenticated using (public.is_guru()) with check (public.is_guru())', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;

  -- tabel yang boleh dibaca murid tanpa login
  foreach t in array array['kelas','jam_pelajaran','jadwal','tugas','materi','tp']
  loop
    execute format('drop policy if exists "baca_publik" on public.%I', t);
    execute format('create policy "baca_publik" on public.%I for select to anon, authenticated using (true)', t);
    execute format('grant select on public.%I to anon', t);
  end loop;
end $$;

-- Pengumuman: murid hanya melihat yang aktif
drop policy if exists "baca_publik" on public.pengumuman;
create policy "baca_publik" on public.pengumuman for select to anon, authenticated using (aktif = true or public.is_guru());
grant select on public.pengumuman to anon;

-- Guru: melihat & mengubah nama dirinya sendiri (penambahan guru hanya lewat SQL Editor)
alter table public.guru enable row level security;
drop policy if exists "guru_baca_diri" on public.guru;
create policy "guru_baca_diri" on public.guru for select to authenticated using (user_id = auth.uid());
drop policy if exists "guru_ubah_diri" on public.guru;
create policy "guru_ubah_diri" on public.guru for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select on public.guru to authenticated;
grant update (nama) on public.guru to authenticated;

grant usage on schema public to anon, authenticated;
grant execute on function public.is_guru() to anon, authenticated;


-- =====================================================================
-- 8. FUNGSI CBT (penilaian di server; kunci jawaban tidak pernah dikirim ke siswa)
-- =====================================================================
-- Hapus versi lama yang tanda tangannya berbeda
drop function if exists public.cbt_mulai(text, text);
drop function if exists public.cbt_jawab(uuid, uuid, integer);
drop function if exists public.cbt_jawab(uuid, uuid, integer, text);
drop function if exists public.cbt_selesai(uuid);
drop function if exists public.cbt_intro(text);
drop function if exists public.cbt_butir(uuid);

-- ---------- Token tes (berganti tiap 15 menit) ----------
create or replace function public.cbt_token_hitung(p_rahasia text, p_slot bigint)
returns text language sql immutable set search_path = public as $$
  select upper(translate(substr(md5(p_rahasia || ':' || p_slot::text), 1, 5), '01', 'xy'));
$$;

create or replace function public.cbt_token(p_tes uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t public.cbt_tes; e bigint := floor(extract(epoch from now()))::bigint;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  select * into t from public.cbt_tes where id = p_tes;
  if not found then return jsonb_build_object('error', 'Tes tidak ditemukan.'); end if;
  return jsonb_build_object('token', public.cbt_token_hitung(t.token_rahasia, e / 900), 'sisa', 900 - (e % 900));
end $$;

-- ---------- Acak opsi: indeks tampil <-> indeks asli ----------
create or replace function public.cbt_opsi_asli(p_peta jsonb, p_soal uuid, p_tampil integer)
returns integer language sql immutable set search_path = public as $$
  select case when p_tampil is null then null
              when p_peta is null or not (p_peta ? p_soal::text) then p_tampil
              else (p_peta -> p_soal::text ->> p_tampil)::integer end;
$$;
create or replace function public.cbt_opsi_tampil(p_peta jsonb, p_soal uuid, p_asli integer)
returns integer language sql immutable set search_path = public as $$
  select case when p_peta is null or not (p_peta ? p_soal::text) then p_asli
              else (select (e.ord - 1)::integer from jsonb_array_elements_text(p_peta -> p_soal::text) with ordinality as e(v, ord)
                     where e.v::integer = p_asli) end;
$$;

-- ---------- Angka pada jawaban isian: "0,5" "0.5" "1/2" "1.000" (ribuan) "-3" ----------
create or replace function public.cbt_angka(p text)
returns numeric language plpgsql immutable set search_path = public as $$
declare t text := regexp_replace(coalesce(p, ''), '\s+', '', 'g'); m text[]; a numeric; b numeric;
begin
  if t ~ '^-?[0-9]{1,3}(\.[0-9]{3})+(,[0-9]+)?$' then t := replace(t, '.', ''); end if;
  t := replace(t, ',', '.');
  if t ~ '^-?[0-9]+(\.[0-9]+)?$' then return t::numeric; end if;
  m := regexp_match(t, '^(-?[0-9]+(?:\.[0-9]+)?)/(-?[0-9]+(?:\.[0-9]+)?)$');
  if m is not null then
    a := m[1]::numeric; b := m[2]::numeric;
    if b <> 0 then return a / b; end if;
  end if;
  return null;
end $$;

-- ---------- Nilai satu butir (0..1, bisa parsial) ----------
create or replace function public.cbt_skor_butir(p_tipe text, p_kunci smallint, p_kunci_json jsonb, p_parsial boolean, p_pilihan smallint, p_jawaban jsonb)
returns numeric language plpgsql immutable set search_path = public as $$
declare k jsonb; nk integer; benar integer := 0; salah integer := 0; cocok integer := 0; i integer; t text; v numeric; a numeric; tol numeric;
begin
  if p_tipe is null or p_tipe = 'PG' then
    return case when p_pilihan is not null and p_pilihan = p_kunci then 1 else 0 end;
  end if;
  if p_jawaban is null or p_kunci_json is null then return 0; end if;
  k := coalesce(p_kunci_json -> 'jawab', '[]'::jsonb);

  if p_tipe = 'PGK' then
    nk := jsonb_array_length(k);
    if nk = 0 or jsonb_typeof(p_jawaban) <> 'array' then return 0; end if;
    select count(*) filter (where k @> jsonb_build_array(e.v::integer)),
           count(*) filter (where not (k @> jsonb_build_array(e.v::integer)))
      into benar, salah
      from (select distinct x as v from jsonb_array_elements_text(p_jawaban) as x where x ~ '^[0-9]+$') e;
    if coalesce(p_parsial, false) then return round(greatest(0, benar - salah)::numeric / nk, 4); end if;
    return case when benar = nk and salah = 0 then 1 else 0 end;

  elsif p_tipe = 'KATEGORI' then
    nk := jsonb_array_length(k);
    if nk = 0 or jsonb_typeof(p_jawaban) <> 'array' then return 0; end if;
    for i in 0 .. nk - 1 loop
      if jsonb_typeof(p_jawaban -> i) = 'boolean' and (p_jawaban -> i) = (k -> i) then cocok := cocok + 1; end if;
    end loop;
    if coalesce(p_parsial, false) then return round(cocok::numeric / nk, 4); end if;
    return case when cocok = nk then 1 else 0 end;

  elsif p_tipe = 'ISIAN' then
    t := lower(regexp_replace(coalesce(p_jawaban #>> '{}', ''), '\s+', '', 'g'));
    if t = '' then return 0; end if;
    if exists (select 1 from jsonb_array_elements_text(coalesce(p_kunci_json -> 'teks', '[]'::jsonb)) x
                where lower(regexp_replace(x, '\s+', '', 'g')) = t) then return 1; end if;
    if jsonb_typeof(p_kunci_json -> 'angka') = 'number' then
      a := (p_kunci_json ->> 'angka')::numeric;
      tol := coalesce((p_kunci_json ->> 'toleransi')::numeric, 0);
      v := public.cbt_angka(t);
      if v is not null and abs(v - a) <= tol + 0.0000001 then return 1; end if;
    end if;
    return 0;
  end if;
  return 0;
end $$;

-- ---------- Butir sebuah sesi (bobot per tes; butir dianulir tidak dihitung) ----------
create function public.cbt_butir(p_sesi uuid)
returns table (materi_id uuid, tp_id uuid, bobot numeric, nilai numeric)
language sql stable security definer set search_path = public as $$
  select q.materi_id, q.tp_id, coalesce(ts.bobot, q.bobot),
         public.cbt_skor_butir(q.tipe, q.kunci, q.kunci_json, q.parsial, j.pilihan, j.jawaban)
  from public.cbt_sesi s
  cross join lateral jsonb_array_elements_text(s.urutan) as u(sid)
  join public.soal_bank q on q.id = u.sid::uuid
  left join public.cbt_tes_soal ts on ts.tes_id = s.tes_id and ts.soal_id = q.id
  left join public.cbt_jawaban j on j.sesi_id = s.id and j.soal_id = q.id
  where s.id = p_sesi and not coalesce(ts.dianulir, false);
$$;

-- ---------- Menilai satu sesi: skor total, per materi, per TP ----------
create or replace function public.cbt_nilai(p_sesi uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare v_benar integer; v_total integer; v_skor numeric;
begin
  if not exists (select 1 from public.cbt_sesi where id = p_sesi) then return; end if;

  delete from public.cbt_hasil_materi where sesi_id = p_sesi;
  insert into public.cbt_hasil_materi (sesi_id, materi_id, benar, total, skor)
    select p_sesi, b.materi_id, count(*) filter (where b.nilai >= 1), count(*),
           round(100.0 * sum(b.nilai * b.bobot) / sum(b.bobot), 2)
    from public.cbt_butir(p_sesi) b
    group by b.materi_id;

  delete from public.cbt_hasil_tp where sesi_id = p_sesi;
  insert into public.cbt_hasil_tp (sesi_id, tp_id, benar, total, skor)
    select p_sesi, b.tp_id, count(*) filter (where b.nilai >= 1), count(*),
           round(100.0 * sum(b.nilai * b.bobot) / sum(b.bobot), 2)
    from public.cbt_butir(p_sesi) b
    where b.tp_id is not null
    group by b.tp_id;

  select count(*) filter (where b.nilai >= 1), count(*),
         round(100.0 * coalesce(sum(b.nilai * b.bobot), 0) / nullif(sum(b.bobot), 0), 2)
    into v_benar, v_total, v_skor
  from public.cbt_butir(p_sesi) b;

  update public.cbt_sesi
     set status = 'selesai', selesai = coalesce(selesai, now()),
         benar = v_benar, total = v_total, skor = v_skor
   where id = p_sesi;
end $$;

-- ---------- Sisa waktu & pemeriksaan sesi ----------
create or replace function public.cbt_sisa(p_sesi uuid)
returns integer language sql stable security definer set search_path = public as $$
  select greatest(0, (t.durasi_menit + s.tambahan_menit) * 60 - floor(extract(epoch from (now() - s.mulai)))::integer)
    from public.cbt_sesi s join public.cbt_tes t on t.id = s.tes_id where s.id = p_sesi;
$$;

-- null = boleh lanjut; selain itu objek error dengan 'kode'
create or replace function public.cbt_periksa(p_sesi uuid, p_perangkat text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ses public.cbt_sesi; t public.cbt_tes; v_sisa integer;
begin
  select * into ses from public.cbt_sesi where id = p_sesi;
  if not found then return jsonb_build_object('error', 'Sesi tidak ditemukan.', 'kode', 'hilang'); end if;
  if ses.status <> 'berjalan' then return jsonb_build_object('error', 'Sesi sudah selesai.', 'kode', 'selesai'); end if;
  if ses.perangkat is distinct from p_perangkat then
    return jsonb_build_object('error', 'Akun ini dibuka di perangkat lain atau login direset guru.', 'kode', 'perangkat');
  end if;
  select * into t from public.cbt_tes where id = ses.tes_id;
  v_sisa := (t.durasi_menit + ses.tambahan_menit) * 60 - floor(extract(epoch from (now() - ses.mulai)))::integer;
  if v_sisa < -10 then
    perform public.cbt_nilai(p_sesi);
    return jsonb_build_object('error', 'Waktu pengerjaan sudah habis.', 'kode', 'waktu');
  end if;
  if t.status <> 'buka' then
    return jsonb_build_object('error', 'Tes sedang ditutup oleh guru. Jawaban ditahan dan dikirim saat tes dibuka kembali.', 'kode', 'tutup', 'sisa', greatest(v_sisa, 0));
  end if;
  return null;
end $$;

-- ---------- Siswa: info tes sebelum mulai (waktu belum berjalan) ----------
create or replace function public.cbt_intro(p_kode text, p_nis text default null, p_token text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare t public.cbt_tes; n integer; slot bigint;
begin
  select * into t from public.cbt_tes where upper(kode) = upper(trim(p_kode));
  if not found then return jsonb_build_object('error', 'Kode tes tidak ditemukan.'); end if;
  if t.status <> 'buka' then return jsonb_build_object('error', 'Tes belum dibuka atau sudah ditutup.'); end if;
  if t.pakai_token then
    slot := floor(extract(epoch from now()) / 900)::bigint;
    if upper(trim(coalesce(p_token, ''))) not in (public.cbt_token_hitung(t.token_rahasia, slot), public.cbt_token_hitung(t.token_rahasia, slot - 1)) then
      return jsonb_build_object('error', 'Token salah atau sudah kedaluwarsa. Minta token terbaru dari guru.');
    end if;
  end if;
  if p_nis is not null and not exists (select 1 from public.siswa sw join public.cbt_tes_kelas tk on tk.kelas_id = sw.kelas_id and tk.tes_id = t.id where sw.nis = trim(p_nis)) then
    return jsonb_build_object('error', 'NIS tidak terdaftar pada tes ini.');
  end if;
  select count(*) into n from public.cbt_tes_soal where tes_id = t.id and not dianulir;
  return jsonb_build_object('judul', t.judul, 'durasi', t.durasi_menit, 'jumlah', n, 'ikrar', t.ikrar);
end $$;

-- ---------- Siswa: mulai / lanjutkan tes ----------
create or replace function public.cbt_mulai(p_kode text, p_nis text, p_token text default null, p_perangkat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  t public.cbt_tes; s public.siswa; ses public.cbt_sesi; v_urut jsonb; v_peta jsonb; v_sisa integer; n integer; slot bigint;
begin
  select * into t from public.cbt_tes where upper(kode) = upper(trim(p_kode));
  if not found then return jsonb_build_object('error', 'Kode tes tidak ditemukan.'); end if;
  if t.status <> 'buka' then return jsonb_build_object('error', 'Tes belum dibuka atau sudah ditutup.'); end if;

  if t.pakai_token then
    slot := floor(extract(epoch from now()) / 900)::bigint;
    if upper(trim(coalesce(p_token, ''))) not in (public.cbt_token_hitung(t.token_rahasia, slot), public.cbt_token_hitung(t.token_rahasia, slot - 1)) then
      return jsonb_build_object('error', 'Token salah atau sudah kedaluwarsa. Minta token terbaru dari guru.');
    end if;
  end if;
  if coalesce(trim(p_perangkat), '') = '' then return jsonb_build_object('error', 'Perangkat tidak dikenali. Muat ulang halaman.'); end if;

  select count(*) into n
    from public.siswa sw join public.cbt_tes_kelas tk on tk.kelas_id = sw.kelas_id and tk.tes_id = t.id
   where sw.nis = trim(p_nis);
  if n = 0 then return jsonb_build_object('error', 'NIS tidak terdaftar pada tes ini.'); end if;
  if n > 1 then return jsonb_build_object('error', 'NIS ini terdaftar di lebih dari satu kelas peserta. Hubungi guru.'); end if;
  select sw.* into s
    from public.siswa sw join public.cbt_tes_kelas tk on tk.kelas_id = sw.kelas_id and tk.tes_id = t.id
   where sw.nis = trim(p_nis);

  select * into ses from public.cbt_sesi where tes_id = t.id and siswa_id = s.id;
  if not found then
    -- urutan soal: soal berstimulus sama tetap berdampingan
    with b as (
      select ts.soal_id, ts.urutan, coalesce(q.stimulus_id::text, q.id::text) as grp
        from public.cbt_tes_soal ts join public.soal_bank q on q.id = ts.soal_id
       where ts.tes_id = t.id
    ), g as (
      select grp, case when t.acak_soal then random() else min(urutan)::double precision end as r from b group by grp
    )
    select jsonb_agg(b.soal_id order by g.r, b.urutan) into v_urut from b join g using (grp);
    if v_urut is null then return jsonb_build_object('error', 'Tes belum memiliki soal.'); end if;
    if t.acak_opsi then
      select jsonb_object_agg(q.id::text, (select jsonb_agg(i order by random()) from generate_series(0, jsonb_array_length(q.opsi) - 1) as i))
        into v_peta
        from public.soal_bank q
       where q.tipe in ('PG', 'PGK') and q.id in (select ts.soal_id from public.cbt_tes_soal ts where ts.tes_id = t.id);
    end if;
    insert into public.cbt_sesi (tes_id, siswa_id, urutan, perangkat, peta_opsi)
      values (t.id, s.id, v_urut, p_perangkat, v_peta) returning * into ses;
  else
    if ses.status = 'selesai' then return jsonb_build_object('error', 'Anda sudah mengerjakan tes ini.'); end if;
    if ses.perangkat is not null and ses.perangkat <> p_perangkat then
      return jsonb_build_object('error', 'Akun ini sedang dipakai di perangkat lain. Minta guru melakukan Reset Login.');
    end if;
    update public.cbt_sesi set perangkat = p_perangkat where id = ses.id returning * into ses;
  end if;

  v_sisa := (t.durasi_menit + ses.tambahan_menit) * 60 - floor(extract(epoch from (now() - ses.mulai)))::integer;
  if v_sisa <= 0 then
    perform public.cbt_nilai(ses.id);
    return jsonb_build_object('error', 'Waktu pengerjaan sudah habis.');
  end if;

  return jsonb_build_object(
    'sesi_id', ses.id, 'nama', s.nama, 'judul', t.judul, 'durasi', t.durasi_menit, 'sisa', v_sisa,
    'pelanggaran', ses.pelanggaran,
    'soal', (select jsonb_agg(jsonb_build_object(
                     'id', q.id, 'tipe', q.tipe, 'pertanyaan', q.pertanyaan, 'gambar', q.gambar_url, 'stimulus_id', q.stimulus_id,
                     'label', case when q.tipe = 'KATEGORI' then coalesce(q.kunci_json -> 'label', '["Benar","Salah"]'::jsonb) end,
                     'opsi', case when ses.peta_opsi ? q.id::text
                                  then (select jsonb_agg(q.opsi -> (e.v::integer) order by e.ord)
                                          from jsonb_array_elements_text(ses.peta_opsi -> q.id::text) with ordinality as e(v, ord))
                                  else q.opsi end) order by u.ord)
               from jsonb_array_elements_text(ses.urutan) with ordinality as u(sid, ord)
               join public.soal_bank q on q.id = u.sid::uuid),
    'stimulus', coalesce((select jsonb_object_agg(st.id::text, jsonb_build_object('judul', st.judul, 'teks', st.teks, 'gambar', st.gambar_url))
                            from public.stimulus st
                           where st.id in (select q.stimulus_id from public.soal_bank q
                                            where q.id in (select x::uuid from jsonb_array_elements_text(ses.urutan) x))), '{}'::jsonb),
    'jawaban', coalesce((select jsonb_object_agg(j.soal_id::text,
                           case when q.tipe = 'PGK' then
                                  (select jsonb_agg(public.cbt_opsi_tampil(ses.peta_opsi, j.soal_id, x::integer)) from jsonb_array_elements_text(j.jawaban) x)
                                when q.tipe in ('KATEGORI', 'ISIAN') then j.jawaban
                                else to_jsonb(public.cbt_opsi_tampil(ses.peta_opsi, j.soal_id, j.pilihan)) end)
                           from public.cbt_jawaban j join public.soal_bank q on q.id = j.soal_id
                          where j.sesi_id = ses.id), '{}'::jsonb)
  );
end $$;

-- ---------- Siswa: catat ikrar kejujuran ----------
create or replace function public.cbt_ikrar(p_sesi uuid, p_perangkat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update public.cbt_sesi set ikrar_pada = coalesce(ikrar_pada, now())
   where id = p_sesi and perangkat is not distinct from p_perangkat;
  return jsonb_build_object('ok', found);
end $$;

-- ---------- Siswa: simpan jawaban (p_pilihan untuk PG, p_jawaban untuk tipe lain) ----------
create or replace function public.cbt_jawab(p_sesi uuid, p_soal uuid, p_pilihan integer default null, p_perangkat text default null, p_jawaban jsonb default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ses public.cbt_sesi; q public.soal_bank; n integer; cek jsonb; v jsonb; x jsonb; i integer;
begin
  cek := public.cbt_periksa(p_sesi, p_perangkat);
  if cek is not null then return cek; end if;
  select * into ses from public.cbt_sesi where id = p_sesi;
  if not (ses.urutan ? p_soal::text) then return jsonb_build_object('error', 'Soal tidak valid.', 'kode', 'soal'); end if;
  select * into q from public.soal_bank where id = p_soal;
  n := jsonb_array_length(q.opsi);

  if q.tipe = 'PG' then
    if p_pilihan is null then
      delete from public.cbt_jawaban where sesi_id = p_sesi and soal_id = p_soal;
      return jsonb_build_object('ok', true, 'sisa', public.cbt_sisa(p_sesi));
    end if;
    if p_pilihan < 0 or p_pilihan >= n then return jsonb_build_object('error', 'Pilihan tidak valid.', 'kode', 'soal'); end if;
    insert into public.cbt_jawaban (sesi_id, soal_id, pilihan, jawaban, diubah)
      values (p_sesi, p_soal, public.cbt_opsi_asli(ses.peta_opsi, p_soal, p_pilihan), null, now())
    on conflict (sesi_id, soal_id) do update set pilihan = excluded.pilihan, jawaban = null, diubah = now();
    return jsonb_build_object('ok', true, 'sisa', public.cbt_sisa(p_sesi));
  end if;

  if q.tipe = 'PGK' then
    if p_jawaban is not null and jsonb_typeof(p_jawaban) = 'array' then
      select jsonb_agg(distinct public.cbt_opsi_asli(ses.peta_opsi, p_soal, e::integer) order by public.cbt_opsi_asli(ses.peta_opsi, p_soal, e::integer))
        into v from jsonb_array_elements_text(p_jawaban) e where e ~ '^[0-9]+$' and e::integer < n;
    end if;
  elsif q.tipe = 'KATEGORI' then
    if p_jawaban is not null and jsonb_typeof(p_jawaban) = 'array' then
      v := '[]'::jsonb;
      for i in 0 .. n - 1 loop
        x := p_jawaban -> i;
        v := v || jsonb_build_array(case when jsonb_typeof(x) = 'boolean' then x else 'null'::jsonb end);
      end loop;
      if not exists (select 1 from jsonb_array_elements(v) e where jsonb_typeof(e) = 'boolean') then v := null; end if;
    end if;
  elsif q.tipe = 'ISIAN' then
    if p_jawaban is not null and coalesce(trim(p_jawaban #>> '{}'), '') <> '' then
      v := to_jsonb(left(trim(p_jawaban #>> '{}'), 100));
    end if;
  end if;

  if v is null then
    delete from public.cbt_jawaban where sesi_id = p_sesi and soal_id = p_soal;
  else
    insert into public.cbt_jawaban (sesi_id, soal_id, pilihan, jawaban, diubah)
      values (p_sesi, p_soal, null, v, now())
    on conflict (sesi_id, soal_id) do update set pilihan = null, jawaban = excluded.jawaban, diubah = now();
  end if;
  return jsonb_build_object('ok', true, 'sisa', public.cbt_sisa(p_sesi));
end $$;

-- ---------- Siswa: sinkron berkala & catat keluar halaman ----------
create or replace function public.cbt_ping(p_sesi uuid, p_perangkat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare cek jsonb;
begin
  cek := public.cbt_periksa(p_sesi, p_perangkat);
  if cek is not null then return cek; end if;
  return jsonb_build_object('ok', true, 'sisa', public.cbt_sisa(p_sesi));
end $$;

create or replace function public.cbt_lapor(p_sesi uuid, p_perangkat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.cbt_sesi set pelanggaran = pelanggaran + 1
   where id = p_sesi and status = 'berjalan' and perangkat is not distinct from p_perangkat
  returning pelanggaran into n;
  return jsonb_build_object('ok', n is not null, 'pelanggaran', n);
end $$;

-- ---------- Umpan balik per TP untuk siswa (kualitatif, tanpa angka) ----------
create or replace function public.cbt_umpan_tp(p_sesi uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'materi', x.materi, 'label', x.label, 'deskripsi', x.deskripsi,
           'tingkat', case when x.skor >= 80 then 'kuat' when x.skor >= 60 then 'berkembang' else 'ulang' end)
         order by x.mu, x.mn, x.no), '[]'::jsonb)
  from (
    select m.nama as materi, m.urutan as mu, m.nama as mn, t.no, 'TP' || t.no as label, t.deskripsi, h.skor
      from public.cbt_hasil_tp h
      join (select tp.id, tp.materi_id, tp.deskripsi,
                   row_number() over (partition by tp.materi_id order by tp.urutan, tp.id::text) as no
              from public.tp) t on t.id = h.tp_id
      join public.materi m on m.id = t.materi_id
     where h.sesi_id = p_sesi
  ) x;
$$;

-- ---------- Siswa: selesai ----------
create or replace function public.cbt_selesai(p_sesi uuid, p_perangkat text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ses public.cbt_sesi; t public.cbt_tes;
begin
  select * into ses from public.cbt_sesi where id = p_sesi;
  if not found then return jsonb_build_object('error', 'Sesi tidak ditemukan.'); end if;
  if ses.status = 'berjalan' then
    if ses.perangkat is distinct from p_perangkat then
      return jsonb_build_object('error', 'Akun ini dibuka di perangkat lain atau login direset guru.', 'kode', 'perangkat');
    end if;
    perform public.cbt_nilai(p_sesi);
  end if;
  select * into ses from public.cbt_sesi where id = p_sesi;
  select * into t from public.cbt_tes where id = ses.tes_id;
  return jsonb_build_object('selesai', true, 'tampil_skor', t.tampil_skor, 'total', ses.total,
                            'skor', case when t.tampil_skor then ses.skor end,
                            'benar', case when t.tampil_skor then ses.benar end,
                            'refleksi', t.refleksi and ses.refleksi is null,
                            'umpan_tp', case when t.umpan_balik_tp then public.cbt_umpan_tp(p_sesi) end);
end $$;

-- ---------- Siswa: refleksi diri (setelah selesai, perangkat sama, maks. 2 jam) ----------
create or replace function public.cbt_refleksi(p_sesi uuid, p_perangkat text, p_isi jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare ses public.cbt_sesi; v_yakin integer; v_rasa text; v_sulit text; v_belajar text;
begin
  select * into ses from public.cbt_sesi where id = p_sesi;
  if not found or ses.status <> 'selesai' then return jsonb_build_object('error', 'Refleksi diisi setelah tes selesai.'); end if;
  if ses.perangkat is distinct from p_perangkat then return jsonb_build_object('error', 'Perangkat tidak sesuai.'); end if;
  if ses.selesai < now() - interval '2 hours' then return jsonb_build_object('error', 'Waktu pengisian refleksi sudah lewat.'); end if;
  v_yakin := case when (p_isi ->> 'yakin') ~ '^[1-4]$' then (p_isi ->> 'yakin')::integer end;
  v_rasa := case when p_isi ->> 'perasaan' in ('lega','senang','biasa','cemas','lelah') then p_isi ->> 'perasaan' end;
  v_sulit := nullif(left(trim(coalesce(p_isi ->> 'sulit', '')), 300), '');
  v_belajar := nullif(left(trim(coalesce(p_isi ->> 'belajar', '')), 300), '');
  update public.cbt_sesi
     set refleksi = jsonb_strip_nulls(jsonb_build_object('yakin', v_yakin, 'perasaan', v_rasa, 'sulit', v_sulit, 'belajar', v_belajar, 'pada', now()))
   where id = p_sesi;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- Guru: tutup sesi yang waktunya habis / semua ----------
create or replace function public.cbt_tutup_sesi(p_tes uuid, p_semua boolean default false)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  for r in
    select s.id from public.cbt_sesi s join public.cbt_tes t on t.id = s.tes_id
     where s.tes_id = p_tes and s.status = 'berjalan'
       and (p_semua or now() - s.mulai > make_interval(mins => t.durasi_menit + s.tambahan_menit))
  loop
    perform public.cbt_nilai(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- Guru: nilai ulang, ubah kunci, anulir ----------
create or replace function public.cbt_nilai_ulang(p_tes uuid)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  for r in select id from public.cbt_sesi where tes_id = p_tes and status = 'selesai' loop
    perform public.cbt_nilai(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.cbt_ubah_kunci(p_soal uuid, p_kunci integer)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; k integer; tp text;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  select jsonb_array_length(opsi), tipe into k, tp from public.soal_bank where id = p_soal;
  if k is null then raise exception 'Soal tidak ditemukan'; end if;
  if tp <> 'PG' then raise exception 'Gunakan cbt_ubah_kunci_json untuk soal bertipe %', tp; end if;
  if p_kunci < 0 or p_kunci >= k then raise exception 'Kunci menunjuk opsi yang tidak ada'; end if;
  update public.soal_bank set kunci = p_kunci where id = p_soal;
  for r in select id from public.cbt_sesi where status = 'selesai' and urutan ? p_soal::text loop
    perform public.cbt_nilai(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.cbt_ubah_kunci_json(p_soal uuid, p_kunci_json jsonb, p_parsial boolean default null)
returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n integer := 0; q public.soal_bank;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  select * into q from public.soal_bank where id = p_soal;
  if not found then raise exception 'Soal tidak ditemukan'; end if;
  if q.tipe = 'PG' then raise exception 'Gunakan cbt_ubah_kunci untuk pilihan ganda'; end if;
  if q.tipe in ('PGK', 'KATEGORI') and (jsonb_typeof(p_kunci_json -> 'jawab') <> 'array' or jsonb_array_length(p_kunci_json -> 'jawab') = 0) then
    raise exception 'Kunci tidak lengkap';
  end if;
  if q.tipe = 'KATEGORI' and jsonb_array_length(p_kunci_json -> 'jawab') <> jsonb_array_length(q.opsi) then
    raise exception 'Jumlah kunci harus sama dengan jumlah pernyataan';
  end if;
  update public.soal_bank set kunci_json = p_kunci_json, parsial = coalesce(p_parsial, parsial) where id = p_soal;
  for r in select id from public.cbt_sesi where status = 'selesai' and urutan ? p_soal::text loop
    perform public.cbt_nilai(r.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.cbt_anulir(p_tes uuid, p_soal uuid, p_anulir boolean)
returns integer
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  update public.cbt_tes_soal set dianulir = p_anulir where tes_id = p_tes and soal_id = p_soal;
  return public.cbt_nilai_ulang(p_tes);
end $$;

-- ---------- Media interaktif: daftar untuk siswa (tanpa kode akses) ----------
create or replace function public.media_daftar()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', md.id, 'judul', md.judul, 'deskripsi', md.deskripsi, 'file_path', md.file_path,
           'penilaian', md.penilaian, 'perlu_kode', md.kode_akses is not null, 'pengaturan', md.pengaturan,
           'tingkat', m.tingkat, 'semester', m.semester, 'materi', m.nama, 'materi_urutan', m.urutan,
           'tp_label', case when t.id is not null then 'TP' || t.no end, 'tp', t.deskripsi)
         order by m.tingkat, m.semester, m.urutan, md.urutan, md.judul), '[]'::jsonb)
  from public.media md
  left join public.materi m on m.id = md.materi_id
  left join (select tp.id, tp.deskripsi, row_number() over (partition by tp.materi_id order by tp.urutan, tp.id::text) as no from public.tp) t on t.id = md.tp_id
  where md.aktif;
$$;

-- Memeriksa identitas siswa sebelum membuka media berpenilaian
create or replace function public.media_masuk(p_media uuid, p_kelas uuid, p_nis text, p_kode text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare md public.media; s public.siswa; k public.kelas;
begin
  select * into md from public.media where id = p_media and aktif;
  if not found then return jsonb_build_object('error', 'Media tidak ditemukan atau sedang dinonaktifkan.'); end if;
  if md.kode_akses is not null and upper(trim(coalesce(p_kode, ''))) <> upper(trim(md.kode_akses)) then
    return jsonb_build_object('error', 'Kode akses salah. Minta kode dari guru.');
  end if;
  select * into s from public.siswa where kelas_id = p_kelas and nis = trim(coalesce(p_nis, ''));
  if not found then return jsonb_build_object('error', 'NIS tidak ditemukan di kelas yang dipilih.'); end if;
  select * into k from public.kelas where id = s.kelas_id;
  return jsonb_build_object('nama', s.nama, 'kelas', k.nama, 'nis', s.nis);
end $$;

-- Menerima nilai dari media. Nilai belum masuk rapor: guru meninjau lalu menerapkannya ke nilai formatif.
create or replace function public.media_kirim(p_media uuid, p_kelas uuid, p_nis text, p_kode text, p_data jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare md public.media; s public.siswa; v_skor numeric; n integer; v_rinci jsonb; v_pred text; v_kktp numeric; v_formatif text; b record;
begin
  select * into md from public.media where id = p_media and aktif;
  if not found then return jsonb_build_object('error', 'Media tidak ditemukan atau sedang dinonaktifkan.'); end if;
  if md.kode_akses is not null and upper(trim(coalesce(p_kode, ''))) <> upper(trim(md.kode_akses)) then
    return jsonb_build_object('error', 'Kode akses salah.');
  end if;
  select * into s from public.siswa where kelas_id = p_kelas and nis = trim(coalesce(p_nis, ''));
  if not found then return jsonb_build_object('error', 'NIS tidak ditemukan di kelas yang dipilih.'); end if;
  if jsonb_typeof(p_data -> 'skor') <> 'number' then return jsonb_build_object('error', 'Skor tidak valid.'); end if;
  v_skor := (p_data ->> 'skor')::numeric;
  if v_skor < 0 or v_skor > 100 then return jsonb_build_object('error', 'Skor harus 0 sampai 100.'); end if;
  select count(*) into n from public.media_hasil where media_id = md.id and siswa_id = s.id and dikirim_pada > now() - interval '1 day';
  if n >= 60 then return jsonb_build_object('error', 'Batas kiriman hari ini tercapai.'); end if;
  -- predikat dari media: IST/BAIK/PB atau Istimewa/Baik/Perlu Bimbingan
  v_pred := case upper(regexp_replace(coalesce(p_data ->> 'predikat', ''), '\s+', '', 'g'))
              when 'IST' then 'IST' when 'ISTIMEWA' then 'IST' when 'A' then 'IST'
              when 'BAIK' then 'BAIK' when 'B' then 'BAIK'
              when 'PB' then 'PB' when 'PERLUBIMBINGAN' then 'PB' when 'C' then 'PB' when 'D' then 'PB' end;
  if jsonb_typeof(p_data -> 'kktp') = 'number' and (p_data ->> 'kktp')::numeric between 1 and 100 then v_kktp := round((p_data ->> 'kktp')::numeric, 2); end if;
  v_rinci := p_data -> 'rincian';
  if v_rinci is not null and length(v_rinci::text) > 20000 then v_rinci := null; end if;
  insert into public.media_hasil (media_id, siswa_id, bagian, skor, benar, salah, penilaian, predikat, kktp, rincian)
  values (md.id, s.id, left(nullif(trim(coalesce(p_data ->> 'bagian', '')), ''), 40), round(v_skor, 2),
          case when (p_data ->> 'benar') ~ '^[0-9]{1,4}$' then (p_data ->> 'benar')::integer end,
          case when (p_data ->> 'salah') ~ '^[0-9]{1,4}$' then (p_data ->> 'salah')::integer end,
          coalesce((p_data ->> 'penilaian')::boolean, true), v_pred, v_kktp, v_rinci);
  -- Terhubung ke nilai formatif: predikat percobaan penilaian terbaik (skor tertinggi) menjadi predikat TP tujuan.
  if md.formatif_otomatis and md.tp_id is not null then
    select h.skor, h.predikat, coalesce(h.kktp, md.kktp) as k into b from public.media_hasil h
     where h.media_id = md.id and h.siswa_id = s.id and h.penilaian
     order by h.skor desc, h.dikirim_pada desc limit 1;
    if found then
      v_formatif := coalesce(b.predikat, case when b.skor < b.k then 'PB'
                                              when b.skor >= least(100, b.k + ceil((100 - b.k) * 3 / 5)) then 'IST' else 'BAIK' end);
      insert into public.nilai_formatif (siswa_id, tp_id, predikat) values (s.id, md.tp_id, v_formatif)
      on conflict (siswa_id, tp_id) do update set predikat = excluded.predikat;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'formatif', v_formatif);
end $$;

-- ---------- Hak akses fungsi ----------
do $$
declare f text;
begin
  -- fungsi internal: tidak dapat dipanggil dari aplikasi
  foreach f in array array['cbt_token_hitung(text, bigint)', 'cbt_opsi_asli(jsonb, uuid, integer)', 'cbt_opsi_tampil(jsonb, uuid, integer)',
                           'cbt_angka(text)', 'cbt_skor_butir(text, smallint, jsonb, boolean, smallint, jsonb)', 'cbt_butir(uuid)',
                           'cbt_nilai(uuid)', 'cbt_sisa(uuid)', 'cbt_periksa(uuid, text)', 'cbt_umpan_tp(uuid)']
  loop
    execute 'revoke all on function public.' || f || ' from public, anon, authenticated';
  end loop;
  -- fungsi siswa (tanpa login)
  foreach f in array array['cbt_intro(text, text, text)', 'cbt_mulai(text, text, text, text)', 'cbt_ikrar(uuid, text)',
                           'cbt_jawab(uuid, uuid, integer, text, jsonb)', 'cbt_ping(uuid, text)', 'cbt_lapor(uuid, text)',
                           'cbt_selesai(uuid, text)', 'cbt_refleksi(uuid, text, jsonb)',
                           'media_daftar()', 'media_masuk(uuid, uuid, text, text)', 'media_kirim(uuid, uuid, text, text, jsonb)']
  loop
    execute 'revoke all on function public.' || f || ' from public';
    execute 'grant execute on function public.' || f || ' to anon, authenticated';
  end loop;
  -- fungsi guru (wajib login; tetap diperiksa is_guru di dalamnya)
  foreach f in array array['cbt_token(uuid)', 'cbt_tutup_sesi(uuid, boolean)', 'cbt_nilai_ulang(uuid)', 'cbt_ubah_kunci(uuid, integer)',
                           'cbt_ubah_kunci_json(uuid, jsonb, boolean)', 'cbt_anulir(uuid, uuid, boolean)']
  loop
    execute 'revoke all on function public.' || f || ' from public, anon';
    execute 'grant execute on function public.' || f || ' to authenticated';
  end loop;
end $$;


-- =====================================================================
-- 9. PENYIMPANAN BERKAS (Supabase Storage)
-- =====================================================================
-- foto: foto profil guru (publik)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/png','image/webp'];
-- soal: gambar soal & stimulus (berkas publik bernama acak; daftar isi folder tidak dapat dilihat siswa)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('soal', 'soal', true, 1048576, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- media: file HTML media interaktif (dibaca siswa; diunggah guru)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 10485760, array['text/html'])
on conflict (id) do update set public = true, file_size_limit = 10485760, allowed_mime_types = array['text/html'];

drop policy if exists "foto_baca" on storage.objects;
create policy "foto_baca" on storage.objects for select to anon, authenticated using (bucket_id = 'foto');
drop policy if exists "foto_guru_tambah" on storage.objects;
create policy "foto_guru_tambah" on storage.objects for insert to authenticated with check (bucket_id = 'foto' and public.is_guru());
drop policy if exists "foto_guru_ubah" on storage.objects;
create policy "foto_guru_ubah" on storage.objects for update to authenticated using (bucket_id = 'foto' and public.is_guru()) with check (bucket_id = 'foto' and public.is_guru());
drop policy if exists "foto_guru_hapus" on storage.objects;
create policy "foto_guru_hapus" on storage.objects for delete to authenticated using (bucket_id = 'foto' and public.is_guru());

drop policy if exists "media_guru_baca" on storage.objects;
create policy "media_guru_baca" on storage.objects for select to authenticated using (bucket_id = 'media' and public.is_guru());
drop policy if exists "media_guru_tambah" on storage.objects;
create policy "media_guru_tambah" on storage.objects for insert to authenticated with check (bucket_id = 'media' and public.is_guru());
drop policy if exists "media_guru_ubah" on storage.objects;
create policy "media_guru_ubah" on storage.objects for update to authenticated using (bucket_id = 'media' and public.is_guru()) with check (bucket_id = 'media' and public.is_guru());
drop policy if exists "media_guru_hapus" on storage.objects;
create policy "media_guru_hapus" on storage.objects for delete to authenticated using (bucket_id = 'media' and public.is_guru());

drop policy if exists "soal_guru_baca" on storage.objects;
create policy "soal_guru_baca" on storage.objects for select to authenticated using (bucket_id = 'soal' and public.is_guru());
drop policy if exists "soal_guru_tambah" on storage.objects;
create policy "soal_guru_tambah" on storage.objects for insert to authenticated with check (bucket_id = 'soal' and public.is_guru());
drop policy if exists "soal_guru_ubah" on storage.objects;
create policy "soal_guru_ubah" on storage.objects for update to authenticated using (bucket_id = 'soal' and public.is_guru()) with check (bucket_id = 'soal' and public.is_guru());
drop policy if exists "soal_guru_hapus" on storage.objects;
create policy "soal_guru_hapus" on storage.objects for delete to authenticated using (bucket_id = 'soal' and public.is_guru());


-- =====================================================================
-- 10. VERSI & PEMERIKSAAN SISTEM (untuk menu Pembaruan Sistem)
-- =====================================================================
create table if not exists public.sistem (
  kunci text primary key,
  nilai text,
  diperbarui timestamptz not null default now()
);
create table if not exists public.sistem_riwayat (
  id bigserial primary key,
  versi text not null,
  dijalankan timestamptz not null default now()
);
-- hanya dapat dibaca lewat fungsi sistem_cek()
alter table public.sistem enable row level security;
alter table public.sistem_riwayat enable row level security;

create or replace function public.sistem_cek()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  tabel text[] := array['guru','kelas','siswa','jam_pelajaran','jadwal','pengumuman','tugas','absensi','jurnal',
                        'materi','tp','nilai_formatif','nilai_sumatif','pp_sesi','stimulus','soal_bank',
                        'cbt_tes','cbt_tes_kelas','cbt_tes_soal','cbt_sesi','cbt_jawaban','cbt_hasil_materi',
                        'cbt_hasil_tp','nilai_sas','media','media_hasil','sistem','sistem_riwayat'];
  fungsi text[] := array['is_guru','cbt_token_hitung','cbt_token','cbt_opsi_asli','cbt_opsi_tampil','cbt_angka',
                         'cbt_skor_butir','cbt_butir','cbt_nilai','cbt_sisa','cbt_periksa','cbt_intro','cbt_mulai',
                         'cbt_ikrar','cbt_jawab','cbt_ping','cbt_lapor','cbt_umpan_tp','cbt_selesai','cbt_refleksi',
                         'cbt_tutup_sesi','cbt_nilai_ulang','cbt_ubah_kunci','cbt_ubah_kunci_json','cbt_anulir',
                         'media_daftar','media_masuk','media_kirim','sistem_cek'];
  bucket text[] := array['foto','soal','media'];
  ns oid := 'public'::regnamespace;
begin
  if not public.is_guru() then raise exception 'Hanya guru yang dapat melakukan ini'; end if;
  return jsonb_build_object(
    'versi', (select nilai from public.sistem where kunci = 'versi_skema'),
    'jumlah_tabel', array_length(tabel, 1),
    'jumlah_fungsi', array_length(fungsi, 1),
    'tabel_kurang', (select coalesce(jsonb_agg(t), '[]'::jsonb) from unnest(tabel) t where to_regclass('public.' || t) is null),
    'rls_mati', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb) from pg_class c
                  where c.relnamespace = ns and c.relkind = 'r' and c.relname = any(tabel) and not c.relrowsecurity),
    'fungsi_kurang', (select coalesce(jsonb_agg(f), '[]'::jsonb) from unnest(fungsi) f
                       where not exists (select 1 from pg_proc p where p.pronamespace = ns and p.proname = f)),
    'fungsi_ganda', (select coalesce(jsonb_agg(x.proname order by x.proname), '[]'::jsonb) from
                      (select p.proname from pg_proc p where p.pronamespace = ns and p.proname = any(fungsi)
                        group by p.proname having count(*) > 1) x),
    -- versi lama yang pernah membuat error (mis. menjalankan ulang patch lama)
    'fungsi_lama', (select coalesce(jsonb_agg(p.proname), '[]'::jsonb) from pg_proc p
                     where p.pronamespace = ns and (
                           (p.proname = 'cbt_butir' and not ('nilai' = any(coalesce(p.proargnames, '{}'))))
                        or (p.proname = 'cbt_jawab' and not ('p_jawaban' = any(coalesce(p.proargnames, '{}'))))
                        or (p.proname = 'cbt_intro' and not ('p_token' = any(coalesce(p.proargnames, '{}'))))
                        or (p.proname = 'media_kirim' and p.prosrc not like '%v_pred%'))),
    'bucket_kurang', (select coalesce(jsonb_agg(b), '[]'::jsonb) from unnest(bucket) b
                       where not exists (select 1 from storage.buckets sb where sb.id = b)),
    'riwayat', (select coalesce(jsonb_agg(jsonb_build_object('versi', r.versi, 'pada', r.dijalankan) order by r.dijalankan desc), '[]'::jsonb)
                  from (select * from public.sistem_riwayat order by dijalankan desc limit 5) r)
  );
end $$;
revoke all on function public.sistem_cek() from public, anon;
grant execute on function public.sistem_cek() to authenticated;


-- =====================================================================
-- 11. DATA AWAL & PENUTUP
-- =====================================================================
-- Jam pelajaran bawaan (11 slot x 30 menit). Ubah di Table Editor > jam_pelajaran bila perlu.
insert into public.jam_pelajaran (jam_ke, mulai, selesai) values
  (1,'07:00','07:30'), (2,'07:30','08:00'), (3,'08:00','08:30'), (4,'08:30','09:00'),
  (5,'09:00','09:30'), (6,'09:30','10:00'), (7,'10:30','11:00'), (8,'11:00','11:30'),
  (9,'11:30','12:00'), (10,'13:00','13:30'), (11,'13:30','14:00')
on conflict (jam_ke) do nothing;

-- Proyek lama: hitung ulang skor tes yang sudah selesai dengan aturan terbaru
do $$
declare r record;
begin
  for r in select id from public.cbt_sesi where status = 'selesai' loop
    perform public.cbt_nilai(r.id);
  end loop;
end $$;

-- Catat versi skema (dibaca menu Pembaruan Sistem)
insert into public.sistem (kunci, nilai, diperbarui) values ('versi_skema', '2026.11.20.2', now())
on conflict (kunci) do update set nilai = excluded.nilai, diperbarui = now();
insert into public.sistem_riwayat (versi) values ('2026.11.20.2');

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------
-- DAFTARKAN AKUN GURU (sekali saja)
-- 1. Authentication > Users > Add user: isi email & kata sandi, centang Auto Confirm.
-- 2. Ganti email di bawah, hapus tanda -- di depan dua baris itu, lalu jalankan:
--
-- insert into public.guru (user_id, nama)
-- select id, 'Nama Guru, S.Pd.' from auth.users where email = 'EMAIL_GURU@contoh.com';
-- ---------------------------------------------------------------------
