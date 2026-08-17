/** Shapes returned by the Plumber API (backend/plumber.R). */

export type Gender = 'all' | 'F' | 'M'

/** The ~230 metric keys are dynamic, so this stays an index signature. */
export type MetricMap = Record<string, number>

export interface MetricsResponse {
  total: MetricMap
  monthly: Record<string, MetricMap>
  months: string[]
  /** What the legacy dashboard would have reported: sum of monthly buckets. */
  sum_of_monthly: MetricMap
  /** Non-zero entries only — the double-counting removed by range dedup. */
  overcount: MetricMap
  computed_at: string
  filters: { from: string; to: string; gender: Gender }
}

export interface SourceStatus {
  key: 'ris' | 'crd_mis' | 'nikshay'
  present: boolean
  files: string[]
  modified: string | null
}

export interface SchemaConflict {
  index: number
  header: string | null
  claimants: string[]
}

export type AuthLevel = 'admin' | 'viewer' | 'anonymous'

export interface AuthStatus {
  read_protected: boolean
  write_protected: boolean
  mode: string
  /** What this caller is allowed to do, decided by the server. */
  level: AuthLevel
}

export interface MetaResponse {
  months: string[]
  loaded_at: string
  /** Snapshot only: when the figures were calculated. */
  generated_at?: string
  /** True when served from a published snapshot rather than a live API. */
  static?: boolean
  fingerprint: string
  project_start: string
  rows: number
  beneficiaries: number
  sources: SourceStatus[]
  cache: { loaded: boolean; fingerprint: string | null; entries: number; load_error: string | null }
  auth: AuthStatus
  schema: { warnings: string[]; conflicts: SchemaConflict[] }
  notes: {
    raw_sheet_available: boolean
    crd_available: boolean
    nikshay_available: boolean
    using_excel_logic: boolean
  }
}

export interface CohortCounts {
  n: number; sp_coll: number; sp_test: number; tb: number; mbc: number
  spiro: number; copd: number; asthma: number; crd_dx: number
}

export interface NnsCohort {
  theme: string
  label: string
  total: CohortCounts
  monthly: Record<string, CohortCounts>
}

export interface NnsResponse {
  months: string[]
  cohorts: NnsCohort[]
}

export interface WeekSummary {
  week: string; week_end: string; n_camps: number; n_screen: number
  avg_ff: number; pct_male: number; n_elig: number; n_coll: number; n_test: number
  pct_coll: number; pct_test: number; pct_spo2: number; pct_rbs: number
  pct_bp: number; n_le40: number; n_scd_pos: number
}

export interface CampDetail {
  camp_id: string; camp_date: string; district: string
  n_screen: number; n_male: number; n_female: number
  n_elig: number; n_coll: number; n_test: number
  lat?: number; lon?: number
}

export interface WeeklyResponse {
  weeks: WeekSummary[]
  camps: { week: string; camps: CampDetail[] }[]
  has_coordinates: boolean
}

export interface SputumRow {
  cohort: string; n: number; elig: number; coll: number
  test: number; mbp: number; cd: number
}

export interface SputumResponse { rows: SputumRow[] }

export interface ApiError {
  error: string
  message: string
  sources?: SourceStatus[]
}

export type UploadSlot = 'ris' | 'crd_mis' | 'nikshay'

export interface UploadSaved {
  slot: UploadSlot
  stored: string
  original: string
  bytes: number
  /** Files moved to incoming/archive/ because this upload replaced them. */
  archived: string[]
}

export interface UploadFailed {
  original: string
  error: string
}

export interface UploadResponse {
  saved: UploadSaved[]
  failed: UploadFailed[]
  reload: {
    ok: boolean
    message?: string
    rows?: number
    beneficiaries?: number
    months?: string[]
    loaded_at?: string
    schema_warnings?: string[]
  }
  sources: SourceStatus[]
  /** Present only on a fully rejected upload. */
  error?: string
}
